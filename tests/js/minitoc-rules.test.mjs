// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirement: docs/reference/minitoc-rules.md (plan 006, acceptance 1).  For every fixture in
// tests/fixtures/minitoc, written by hand from that file, the rules applied to
// NAME.model.json give NAME.expected.json, the scopes and the steps of NAME.panel.json.
// What the caller gets wrong, the functions signal.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  local, maxDepth, minChildren, minitocs, panel, rootLevels, sectionLevels, stepDepth,
} from '../../imprimeur/assets/js/minitoc-rules.mjs';

const directory = fileURLToPath(new URL('../fixtures/minitoc/', import.meta.url));
const read = (name, part) => JSON.parse(readFileSync(`${directory}${name}.${part}.json`, 'utf8'));
const names = readdirSync(directory)
  .filter((file) => file.endsWith('.model.json'))
  .map((file) => file.replace('.model.json', ''));

test('the fixtures are all there', () => {
  assert.equal(names.length, 16);
});

test('the constants are those of the rules', () => {
  assert.deepEqual([minChildren, maxDepth, rootLevels, sectionLevels], [2, 2, 2, 1]);
});

for (const name of names) {
  const model = read(name, 'model');
  const expected = read(name, 'expected');
  const table = read(name, 'panel');

  test(`${name}: the inline minitocs`, () => {
    assert.deepEqual(minitocs(model), expected.minitocs);
  });

  test(`${name}: the local minitoc of every heading`, () => {
    for (const one of expected.locals) assert.deepEqual(local(model, one.active), one, `heading ${one.active}`);
  });

  test(`${name}: the table of scopes`, () => {
    for (const { active, root, depth, panel: wanted } of table.scopes) {
      assert.deepEqual(panel(model, active, root, depth), wanted, `${active} ${root} ${depth}`);
    }
  });

  test(`${name}: the table of steps`, () => {
    for (const { active, root, depth, key, expected: wanted } of table.steps) {
      assert.equal(stepDepth(model, active, root, depth, key), wanted, `${active} ${root} ${depth} ${key}`);
    }
  });
}

test('the tables of steps hold steps', () => {
  assert.ok(names.reduce((sum, name) => sum + read(name, 'panel').steps.length, 0) > 0);
});

test('what the caller gets wrong is signalled', () => {
  const model = read('normal', 'model');
  for (const [title, call] of [
    ['an id of no heading, in a local minitoc', () => local(model, 99)],
    ['an id of no heading, in a panel', () => panel(model, 99, 'document', 1)],
    ['an id of no heading, in a step', () => stepDepth(model, 99, 'document', 1, '+')],
    ['another root', () => panel(model, 0, 'chapter', 1)],
    ['a depth of none', () => panel(model, 0, 'document', 0)],
    ['a depth that is no integer', () => panel(model, 0, 'document', 1.5)],
    ['a depth by another name', () => panel(model, 0, 'document', 'every')],
    ['a depth in a string', () => panel(model, 0, 'document', '1')],
    ['another key', () => stepDepth(model, 0, 'document', 1, '=')],
  ]) {
    assert.throws(call, RangeError, title);
  }
});
