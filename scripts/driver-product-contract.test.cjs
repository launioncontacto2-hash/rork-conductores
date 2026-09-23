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
