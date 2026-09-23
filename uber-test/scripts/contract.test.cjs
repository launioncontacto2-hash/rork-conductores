const assert = require("node:assert/strict");
const test = require("node:test");

const offer = (id) => ({ id, service: "UberX", fare: 120, currency: "MXN", pickup: "Centro", pickupDistanceKm: 1.2, tripDurationMinutes: 20, tripDistanceKm: 8, riderRating: 4.9, expiresAfterSeconds: 15 });
const batch = (count = 3) => ({ id: "batch-1", environment: "TEST", offers: Array.from({ length: count }, (_, i) => offer(`offer-${i + 1}`)) });

function receive(state, incoming) {
  if (incoming.environment !== "TEST") throw new Error("production_payload_rejected");
  if (incoming.offers.length < 1 || incoming.offers.length > 10) throw new Error("invalid_batch_size");
  if (state.batches.has(incoming.id)) {
    if (!state.current.length || state.current.map((item) => item.id).join(",") !== incoming.offers.map((item) => item.id).join(",")) throw new Error("duplicate_batch");
    state.index = Math.min(state.results.length, incoming.offers.length); return;
  }
  for (const item of incoming.offers) if (state.offers.has(item.id)) throw new Error("duplicate_offer");
  state.batches.add(incoming.id); incoming.offers.forEach((item) => state.offers.add(item.id)); state.current = incoming.offers; state.index = 0;
}
function finish(state, outcome) { const item = state.current[state.index++]; state.results.push({ id: item.id, outcome }); return item; }

test("accept, discard and expiry advance FIFO", () => {
  const state = { batches: new Set(), offers: new Set(), current: [], index: 0, results: [] };
  receive(state, batch());
  assert.equal(finish(state, "accepted").id, "offer-1");
  assert.equal(finish(state, "discarded").id, "offer-2");
  assert.equal(finish(state, "expired").id, "offer-3");
  assert.deepEqual(state.results.map((item) => item.outcome), ["accepted", "discarded", "expired"]);
});
test("rejects production, duplicates and more than ten", () => {
  const state = { batches: new Set(), offers: new Set(), current: [], index: 0, results: [] };
  assert.throws(() => receive(state, { ...batch(), environment: "PRODUCTION" }), /production/);
  assert.throws(() => receive(state, batch(11)), /batch_size/);
  receive(state, batch(1));
  assert.doesNotThrow(() => receive(state, batch(1)));
  assert.throws(() => receive(state, { ...batch(1), id: "batch-2" }), /duplicate_offer/);
});
test("supports ten consecutive offers", () => {
  const state = { batches: new Set(), offers: new Set(), current: [], index: 0, results: [] };
  receive(state, batch(10));
  for (let i = 0; i < 10; i++) finish(state, "accepted");
  assert.equal(state.results.length, 10); assert.equal(state.index, 10);
});
test("future source event is independent from DORI and shift state", () => {
  const sourceEventFor = (shiftStatus) => ({ type: "offer_batch_ready", environment: "TEST", doriConsumer: false, shiftStatus });
  assert.deepEqual(sourceEventFor("open"), { type: "offer_batch_ready", environment: "TEST", doriConsumer: false, shiftStatus: "open" });
  assert.deepEqual(sourceEventFor("closed"), { type: "offer_batch_ready", environment: "TEST", doriConsumer: false, shiftStatus: "closed" });
});
