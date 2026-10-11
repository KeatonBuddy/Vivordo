"use strict";

/**
 * Builds the `exercise_catalog/current` document body.
 *
 * Entry order is preserved: the Circle challenge picker renders the catalog
 * unsorted, so the stored order is what users see.
 *
 * @param {Array<{n: string, c: string}>} entries Exercises, in display order.
 * @param {number} version Catalog version, bumped on every write.
 * @return {{version: number, exercises: Array<{n: string, c: string}>}} Body.
 */
function buildCatalogDocument(entries, version) {
  const exercises = entries.map((entry, index) => {
    const name = String(entry.n || "").trim();
    if (!name) {
      throw new Error(`entry ${index} has no name`);
    }
    const category = String(entry.c || "").trim();
    return {n: name, c: category || "Other"};
  });

  return {version, exercises};
}

module.exports = {buildCatalogDocument};
