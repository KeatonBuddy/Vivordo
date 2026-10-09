// Read-only DevTools export summary. No measurements/account payloads printed.
// Usage: node scripts/profile_summary.js export.json [comparison-export.json]
const fs = require("node:fs");
function report(path) {
  const data = JSON.parse(fs.readFileSync(path, "utf8"));
  const performance = data.performance;
  const frames = performance?.flutterFrames || [];
  if (!frames.length) throw new Error("No Flutter frame data in export");
  const hz = performance.displayRefreshRate || 60;
  const budget = 1000000 / hz;
  function timings(field) {
    const values = frames.map((frame) => frame[field]).filter((n) => Number.isFinite(n) && n >= 0).sort((a, b) => a - b);
    const percentile = (p) => values[Math.min(values.length - 1, Math.floor(values.length * p))] / 1000;
    return {p50Ms: percentile(.5), p95Ms: percentile(.95), p99Ms: percentile(.99),
      maxMs: percentile(1), overBudget: values.filter((v) => v > budget).length};
  }
  return {profileBuild: data.connectedApp?.isProfileBuild, hz, frames: frames.length,
    durationSeconds: (frames.at(-1).startTime - frames[0].startTime) / 1000000,
    ui: timings("build"), raster: timings("raster")};
}
for (const path of process.argv.slice(2)) console.log(JSON.stringify(report(path), null, 2));
if (process.argv.length < 3) throw new Error("Pass a DevTools JSON export");
