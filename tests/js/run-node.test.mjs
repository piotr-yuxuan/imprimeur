// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirement: tests/run-node fails on a failing test and on a directory
// without tests, and passes when every test passes (plan 001, acceptance 2).

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

const passing = "import { test } from 'node:test';\ntest('passes', () => {});\n";
const failing = "import { test } from 'node:test';\ntest('fails', () => { throw new Error('no'); });\n";

test('passes when every test passes', () => {
  assert.equal(runOn({ 'a.test.mjs': passing }), 0);
});

test('fails on a failing test', () => {
  assert.notEqual(runOn({ 'a.test.mjs': passing, 'b.test.mjs': failing }), 0);
});

test('fails on a directory without tests', () => {
  assert.notEqual(runOn({ 'README': 'No test here.\n' }), 0);
});
