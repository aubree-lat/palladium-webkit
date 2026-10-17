import { readFile, readdir } from 'node:fs/promises';
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
for (const file of (await readdir('.palladium/tests')).filter(file => file.endsWith('.js'))) {
  new AsyncFunction(await readFile('.palladium/tests/' + file, 'utf8'));
}
process.stdout.write('Native probe JavaScript syntax passed\n');
