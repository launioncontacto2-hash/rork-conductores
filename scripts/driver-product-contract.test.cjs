const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

test('driver navigation exposes the approved five product areas', () => {
  const source = read('ios-turno-ev/TurnoEV/ContentView.swift');
  for (const label of ['Turno', 'Metas', 'Bonos', 'Cartera', 'Guardias']) {
    assert.match(source, new RegExp(`Tab\\("${label}"|Label\\("${label}"`));
  }
});

test('driver wallet keeps product flows navigable without fake remote mutations', () => {
  const source = read('ios-turno-ev/TurnoEV/Views/BackendDriverFinanceView.swift');
  for (const phrase of [
    'Transferir fondos a mi cuenta',
    'Efectivo / Depositar a DORI',
    'Crédito automotriz / abono',
    'Historial',
    'Simular abono a capital',
    'no escriben en Supabase',
  ]) {
    assert.match(source, new RegExp(phrase.replace(/[.*+?^${}()|[\\]\\]/g, '\\$&')));
  }
  assert.doesNotMatch(source, /UserDefaults/);
});

test('driver evidence and recovery surfaces remain part of the conductor contract', () => {
  const incident = read('ios-turno-ev/TurnoEV/Views/IncidentView.swift');
  for (const photo of ['Foto daño 1', 'Foto daño 2', 'Frente', 'Lateral conductor', 'Trasera', 'Lateral copiloto']) {
    assert.match(incident, new RegExp(photo));
  }
  assert.match(read('ios-turno-ev/TurnoEV/Views/HourRecoveryView.swift'), /Recuperación de horas/);
  assert.match(read('ios-turno-ev/TurnoEV/Views/UnitDocumentsView.swift'), /Documentos de consulta/);
});

test('driver turn keeps the assigned-unit and QR contracts explicit', () => {
  const shift = read('ios-turno-ev/TurnoEV/Views/ShiftView.swift');
  assert.match(shift, /assignedUnitCard/);
  assert.match(shift, /Tolerancia de 15 minutos antes de afectar bonos/);
  assert.doesNotMatch(shift, /\.toolbar\s*\{/);

  const start = read('ios-turno-ev/TurnoEV/Views/StartShiftView.swift');
  assert.match(start, /\$0\.internalNumber\.uppercased\(\) == normalized/);
  assert.doesNotMatch(start, /\$0\.qrCode\.uppercased\(\) == normalized/);
  assert.match(start, /QR leído no coincide con tu unidad asignada/);

  const lab = read('ios-turno-ev/TurnoEV/Views/Lab/LabWorldViews.swift');
  assert.match(lab, /LabQrCode\(text: vehicle\.internalNumber\)/);
});

test('driver ODO surface keeps administrative mileage rules out of the UI', () => {
  const start = read('ios-turno-ev/TurnoEV/Views/StartShiftView.swift');
  const policy = read('ios-turno-ev/TurnoEV/Models/OdometerAdministrationPolicy.swift');
  assert.match(policy, /masterToleranceKm/);
  assert.match(policy, /static let `default` = Self\(masterToleranceKm: 5\)/);
  assert.doesNotMatch(start, /Registro de estación/);
  assert.doesNotMatch(start, /Rango aceptado/);
  assert.doesNotMatch(start, /odometerToleranceKm/);
  assert.match(start, /ODO y el kilometraje sean legibles/);
});

test('driver evidence UI derives success from analysis state, not photo existence', () => {
  const start = read('ios-turno-ev/TurnoEV/Views/StartShiftView.swift');
  const capture = read('ios-turno-ev/TurnoEV/Views/CaptureViews.swift');
  assert.match(start, /validation: odometerStatus/);
  assert.match(start, /validation: batteryStatus/);
  assert.match(start, /isEnabled: validOdometerManual/);
  assert.match(start, /isEnabled: validBatteryManual/);
  assert.match(capture, /validation\?\.symbol/);
  assert.doesNotMatch(capture, /Image\(systemName: "checkmark"\)/);
});
