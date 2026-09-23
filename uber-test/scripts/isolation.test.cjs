const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const root = path.resolve(__dirname, "..");
const migration = fs.readFileSync(path.resolve(root, "..", "supabase", "migrations", "20260923063241_uber_test_offer_batches.sql"), "utf8");
const sourceFiles = [
  path.join(root, "Sources", "UberTestCore", "OfferBatch.swift"),
  path.join(root, "Sources", "UberTestCore", "UberTestStore.swift"),
  path.join(root, "Sources", "UberTestCore", "UberTestOfferView.swift"),
  path.join(root, "UberTestApp", "UberTestApp.swift"),
];

test("UBER Test sources do not import or execute DORI Copiloto", () => {
  const source = sourceFiles.map((file) => fs.readFileSync(file, "utf8")).join("\n");
  assert.doesNotMatch(source, /dori-copilot|dori_copilot|recommendation|recomendaci[oó]n/i);
});

test("UBER Test source is marked TEST-only", () => {
  const source = fs.readFileSync(path.join(root, "Sources", "UberTestCore", "OfferBatch.swift"), "utf8");
  assert.match(source, /environment == \"TEST\"/);
  assert.match(source, /offers\.count <= 10/);
});

test("recovery RPC emits the public camelCase offer contract", () => {
  for (const field of ["pickupDistanceKm", "tripDurationMinutes", "tripDistanceKm", "riderRating", "expiresAfterSeconds"]) {
    assert.match(migration, new RegExp(`'${field}'`));
  }
  assert.match(migration, /driver_get_uber_test_batch/);
});
