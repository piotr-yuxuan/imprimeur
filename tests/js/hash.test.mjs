// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirement (plan 003, "Mermaid"): `fnv1a` is FNV-1a of 32 bits over the
// UTF-8 bytes of a string, as 8 hexadecimal digits.  The first three values
// are the reference vectors of FNV's authors; the others come from a separate
// implementation: bytes beyond ASCII, a character outside the basic plane, and
// a value whose first digit is 0.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fnv1a } from '../../imprimeur/assets/js/hash.mjs';

const table = [
  ['', '811c9dc5'],
  ['a', 'e40c292c'],
  ['foobar', 'bf9cf968'],
  ['é', '1e9de8c1'],
  ['日本語', '805f5ce7'],
  ['😀', '33a29608'],
  ['akd', '0d368b73'],
];

for (const [text, expected] of table) {
  test(`fnv1a of ${JSON.stringify(text)}`, () => {
    assert.equal(fnv1a(text), expected);
  });
}
