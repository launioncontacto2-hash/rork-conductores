#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const simulator = require('./copilot-simulator.cjs');

function usage() {
  return [
    'Uso:',
    '  node scripts/run-copilot-simulator.cjs single [A|B|C|D|E] [opciones]',
    '  node scripts/run-copilot-simulator.cjs hours [A|B|C|D|E] [opciones]',
    '  node scripts/run-copilot-simulator.cjs input <archivo.json> [opciones]',
    '  node scripts/run-copilot-simulator.cjs mass [--minimum-net-hourly 120]',
    '',
    'Opciones: --hour --demand --battery --remaining --pickup --fare --distance',
    '          --destination-value --minimum-net-hourly'
  ].join('\n');
}

function parse(args) {
  const positional = [];
  const options = {};
  const names = new Set(['hour', 'demand', 'battery', 'remaining', 'pickup', 'fare', 'distance', 'destination-value', 'minimum-net-hourly']);
  for (let index = 0; index < args.length; index += 1) {
    const token = args[index];
    if (!token.startsWith('--')) { positional.push(token); continue; }
    const name = token.slice(2);
    if (!names.has(name) || index + 1 >= args.length) throw new Error(`invalid_option_${name}`);
    options[name] = args[index + 1];
    index += 1;
  }
  return { positional, options };
}

function number(options, name, fallback) {
  if (options[name] === undefined) return fallback;
  const value = Number(options[name]);
  if (!Number.isFinite(value)) throw new Error(`invalid_option_${name}`);
  return value;
}

function settings(options) {
  return {
    minimumNetHourly: number(options, 'minimum-net-hourly', 120),
    variables: {
      hour: number(options, 'hour', undefined),
      demand: options.demand,
      battery: number(options, 'battery', undefined),
      remaining: number(options, 'remaining', undefined),
      pickup: number(options, 'pickup', undefined),
      fare: number(options, 'fare', undefined),
      distance: number(options, 'distance', undefined),
      destinationValue: number(options, 'destination-value', undefined)
    }
  };
}

function main(argv) {
  const { positional, options } = parse(argv);
  const command = positional[0];
  const config = settings(options);
  let output;
  if (command === 'single') {
    output = simulator.runIndividual({ fixture: positional[1] || 'A', ...config });
  } else if (command === 'hours') {
    const base = simulator.runIndividual({ fixture: positional[1] || 'C', ...config }).input;
    output = simulator.runHourlySweep(base, {
      demand: config.variables.demand || 'automatic',
      minimumNetHourly: config.minimumNetHourly
    });
  } else if (command === 'input') {
    if (!positional[1]) throw new Error('missing_input_file');
    output = simulator.evaluateInput(JSON.parse(fs.readFileSync(positional[1], 'utf8')), config);
  } else if (command === 'mass') {
    output = simulator.runMassSimulation({ minimumNetHourly: config.minimumNetHourly });
  } else {
    throw new Error(usage());
  }
  process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
}

try {
  main(process.argv.slice(2));
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
