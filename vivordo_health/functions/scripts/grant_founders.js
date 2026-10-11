"use strict";

// Marks every account that exists today as a founder (beta user). Dry-run by
// default. Usage:
//   node scripts/grant_founders.js PROJECT [--apply]
//     [--before=2026-10-08T00:00:00Z] [--exclude=UID,UID]
//   --before   only accounts created before this instant (default: now).
//   --exclude  accounts to leave out, such as internal test accounts.
//   --apply    write founders/{uid}; without it nothing is written.
// Re-running is safe: existing founder records are left untouched, so the
// original grantedAt is kept. The app unlocks the Founder achievement for an
// account the next time it reconciles achievements.
// List founders later: the `founders` collection, one document per account.
const admin = require("firebase-admin");

/**
 * Picks the accounts that qualify as founders.
 * @param {Array<{uid: string, metadata: {creationTime: string}}>} users
 *     Firebase Auth user records.
 * @param {number} cutoffMs Accounts created at or after this are excluded.
 * @param {Set<string>} excluded Account IDs to leave out.
 * @return {Array<{uid: string, createdAt: Date}>}
 */
function founderCandidates(users, cutoffMs, excluded = new Set()) {
  return users
      .map((user) => ({
        uid: user.uid,
        createdAt: new Date(user.metadata?.creationTime),
      }))
      .filter(({uid, createdAt}) =>
        !excluded.has(uid) &&
        !Number.isNaN(createdAt.getTime()) &&
        createdAt.getTime() < cutoffMs);
}

/**
 * Reads every Firebase Auth account.
 * @param {object} auth Admin Auth instance.
 * @return {Promise<object[]>}
 */
async function listAllUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

/** Runs the grant. */
async function main() {
  const [projectId, ...flags] = process.argv.slice(2);
  const value = (name) => flags.find((flag) => flag.startsWith(`${name}=`))
      ?.slice(name.length + 1);
  const known = ["--apply", "--before", "--exclude"];
  if (!projectId || projectId.startsWith("--") ||
      flags.some((flag) => !known.includes(flag.split("=")[0]))) {
    throw new Error("Expected PROJECT [--apply] [--before=ISO] " +
      "[--exclude=UID,UID]");
  }
  const cutoffMs = value("--before") ? Date.parse(value("--before")) :
    Date.now();
  if (Number.isNaN(cutoffMs)) throw new Error("--before is not a date");
  const excluded = new Set((value("--exclude") ?? "").split(",")
      .map((uid) => uid.trim()).filter(Boolean));
  const apply = flags.includes("--apply");

  admin.initializeApp({projectId});
  const db = admin.firestore();
  const users = await listAllUsers(admin.auth());
  const founders = founderCandidates(users, cutoffMs, excluded);
  console.log(`${users.length} accounts; ${founders.length} created before ` +
    `${new Date(cutoffMs).toISOString()}` +
    (excluded.size > 0 ? ` (${excluded.size} excluded)` : "") + ".");
  if (!apply) {
    console.log("Dry run: nothing written.");
    return;
  }

  let granted = 0;
  let existing = 0;
  const writer = db.bulkWriter();
  writer.onWriteError((error) => {
    // create() fails on an existing record; keep it as it is.
    if (error.code === 6) {
      existing++;
      return false;
    }
    return error.failedAttempts < 3;
  });
  writer.onWriteResult(() => granted++);
  for (const {uid, createdAt} of founders) {
    void writer.create(db.collection("founders").doc(uid), {
      uid,
      accountCreatedAt: admin.firestore.Timestamp.fromDate(createdAt),
      grantedAt: admin.firestore.FieldValue.serverTimestamp(),
    }).catch(() => {});
  }
  await writer.close();
  const failed = founders.length - granted - existing;
  console.log(`Done: ${granted} granted, ${existing} already founders` +
    (failed > 0 ? `, ${failed} failed (re-run to retry).` : "."));
  if (failed > 0) process.exitCode = 1;
}

if (require.main === module) {
  main().catch((error) => {
    console.error(error.message); process.exitCode = 1;
  });
}

module.exports = {founderCandidates};
