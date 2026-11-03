// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirement: plan 006, "keys", as its implementation notes settle them.  From the
// local minitoc of the heading at the top of the view, ] and [ go to the next and the
// previous entry of its section, ] from the section's own heading to its first; u goes to
// the parent of the active heading, the root included; and with nowhere to go, nothing.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { local } from '../../imprimeur/assets/js/minitoc-rules.mjs';
import { movement } from '../../imprimeur/assets/js/minitoc-ui.mjs';

const model = JSON.parse(readFileSync(
  fileURLToPath(new URL('../fixtures/minitoc/normal.model.json', import.meta.url)),
  'utf8',
));

test('a key goes as its table says, in the fixture normal', () => {
  for (const [title, active, key, target] of [
    ['next, from an entry', 3, ']', 6],
    ['next, from the last entry', 6, ']', null],
    ['next, from under an entry', 4, ']', 6],
    ['next, from the section itself', 2, ']', 3],
    ['next, from the root', 0, ']', 1],
    ['previous, from an entry', 6, '[', 3],
    ['previous, from the first entry', 3, '[', null],
    ['previous, from the section itself', 2, '[', null],
    ['up, from deep down', 4, 'u', 3],
    ['up, from an entry', 3, 'u', 2],
    ['up, to the root', 1, 'u', 0],
    ['up, from the root', 0, 'u', null],
  ]) {
    assert.equal(movement(local(model, active), key), target, title);
  }
});
