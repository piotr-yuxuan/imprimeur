// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirement: tests/run-node fails unless every test file ran tests that
// all passed: on a failing test, on a directory without tests, on a file
// that defines no test, and on a skipped or to-do test (plan 001,
// acceptance 2, and the review of plan 001).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const runNode = join(dirname(fileURLToPath(import.meta.url)), '..', 'run-node');

// Run tests/run-node on a scratch directory holding FILES, a map of file
// names to contents, and return its exit status.  NODE_TEST_CONTEXT is
// removed, or the inner runner would report to this one instead of exiting.
function runOn(files) {
  const directory = mkdtempSync(join(tmpdir(), 'run-node-'));
  for (const [name, text] of Object.entries(files)) {
    writeFileSync(join(directory, name), text);
  }
  const env = { ...process.env };
  delete env.NODE_TEST_CONTEXT;
  return spawnSync(runNode, [directory], { env, encoding: 'utf8', timeout: 60000 }).status;
}

const header = "import { test } from 'node:test';\n";
const passing = header + "test('passes', () => {});\n";

test('passes when every test passes', () => {
  assert.equal(runOn({ 'a.test.mjs': passing, 'b.test.mjs': passing }), 0);
});

test('fails on a failing test', () => {
  const failing = header + "test('fails', () => { throw new Error('no'); });\n";
  assert.notEqual(runOn({ 'a.test.mjs': passing, 'b.test.mjs': failing }), 0);
});

test('fails on a directory without tests', () => {
  assert.notEqual(runOn({ 'README': 'No test here.\n' }), 0);
});

test('fails on a file that defines no test', () => {
  assert.notEqual(runOn({ 'a.test.mjs': passing, 'b.test.mjs': '// Nothing.\n' }), 0);
});

test('fails on a skipped test', () => {
  const skipped = header + "test('skipped', { skip: 'not yet' }, () => {});\n";
  assert.notEqual(runOn({ 'a.test.mjs': passing, 'b.test.mjs': skipped }), 0);
});

test('fails on a test left to do', () => {
  const todo = header + "test.todo('later');\n";
  assert.notEqual(runOn({ 'a.test.mjs': passing, 'b.test.mjs': todo }), 0);
});
