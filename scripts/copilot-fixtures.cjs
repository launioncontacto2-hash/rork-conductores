// Controlled unit-test fixtures. No simulation UI or mass simulator in Block 1.
function scenario(name) {
  const now = '2026-09-07T10:00:00-06:00';
  const input = {
    trip: { fare: 240, pickupMinutes: 4, pickupKm: 1, tripMinutes: 22, tripKm: 10, origin: 'Centro', destination: 'Zona de oficinas', timestamp: now },
    market: { now, hour: 10, weekday: 1, originZone: 'Centro', destinationZone: 'Oficinas', demand: 'normal', historicalDemand: null, forecastDemand: null, nextWaitMinutes: 8, destinationValue: 85, repositionKm: 1, repositionMinutes: 3, traffic: null, events: null, weather: null },
    vehicle: { vehicleId: 'simulated-vehicle', batteryPercent: 80, rangeKm: 200, consumptionKwhPerKm: 0.16, energyCostPerKm: 0.6, odometerKm: 20000, distanceToStationKm: 3, destinationToStationKm: 8, requiredReturnAt: '2026-09-07T16:00:00-06:00' },
    driver: { driverId: 'simulated-driver', shiftStart: '2026-09-07T08:00:00-06:00', shiftEnd: '2026-09-07T16:00:00-06:00', remainingMinutes: 360, connectedMinutes: 120, accumulatedIncome: 300, completedTrips: 3 },
    source: 'simulated'
  };
  if (name === 'B') Object.assign(input.trip, { fare: 350, pickupMinutes: 95, pickupKm: 45 });
  if (name === 'C' || name === 'D') {
    Object.assign(input.trip, { fare: 115, pickupMinutes: 6, pickupKm: 2, tripMinutes: 24, tripKm: 9 });
    input.market.demand = name === 'C' ? 'low' : 'high'; input.market.destinationValue = 65;
    input.market.nextWaitMinutes = 15;
  }
  if (name === 'E') {
    input.trip.fare = 650; input.vehicle.batteryPercent = 12; input.vehicle.rangeKm = 25;
    input.vehicle.destinationToStationKm = 35; input.driver.remainingMinutes = 35;
  }
  return input;
}
module.exports = { scenario };
