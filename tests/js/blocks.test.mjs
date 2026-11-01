// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirements (plan 003, "Block diff"): for each new block, `reuse` gives
// the index of the shown block it reuses, or -1; reused blocks keep their
// order and none is reused twice; the common prefix is reused, then the
// common suffix of what follows it, then a longest common subsequence of
// the middle, unless the middle has more than `middleLimit` pairs of
// blocks.  Blank keys, of white space alone, take no part in that
// subsequence, so that the white space between blocks cannot outvote a
// video that could stay.  Where several subsequences are longest, each new
// block in turn is reused if one of them allows it, with the earliest shown
// block it can be paired with.  A shown block without a key, whose load
// failed, is reused by none.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { middleLimit, reuse } from '../../imprimeur/assets/js/blocks.mjs';

const table = [
  ['both lists empty', [], [], []],
  ['nothing shown yet', [], ['a', 'b'], [-1, -1]],
  ['every block removed', ['a', 'b'], [], []],
  ['no change', ['a', 'b', 'c'], ['a', 'b', 'c'], [0, 1, 2]],
  ['the prefix of an edit in the last block', ['a', 'b', 'c'], ['a', 'b', 'C'], [0, 1, -1]],
  ['the suffix of an edit in the first block', ['a', 'b', 'c'], ['A', 'b', 'c'], [-1, 1, 2]],
  ['both around an edit in the middle', ['a', 'b', 'c'], ['a', 'B', 'c'], [0, -1, 2]],
  ['a block split in two', ['a', 'b', 'c'], ['a', 'b1', 'b2', 'c'], [0, -1, -1, 2]],
  ['an insertion', ['a', 'c'], ['a', 'b', 'c'], [0, -1, 1]],
  ['an insertion at the start', ['b', 'c'], ['a', 'b', 'c'], [-1, 0, 1]],
  ['a deletion', ['a', 'b', 'c'], ['a', 'c'], [0, 2]],
  ['a deletion at the end', ['a', 'b', 'c'], ['a', 'b'], [0, 1]],
  ['a block moved down', ['a', 'b', 'c', 'd'], ['b', 'c', 'a', 'd'], [1, 2, -1, 3]],
  ['a block moved up', ['a', 'b', 'c', 'd'], ['c', 'a', 'b', 'd'], [-1, 0, 1, 3]],
  ['two blocks swapped: the earlier new one is reused', ['a', 'b'], ['b', 'a'], [1, -1]],
  ['duplicates, each reused once', ['x', 'x'], ['x', 'x', 'x'], [0, 1, -1]],
  ['a duplicate of the prefix reused by the suffix', ['a', 'x', 'b', 'x', 'c'], ['a', 'x', 'x', 'c'], [0, 1, 3, 4]],
  ['the earliest of duplicates in the middle', ['p', 'x', 'x', 'q'], ['r', 'x', 's'], [-1, 1, -1]],
  ['blocks between equal text nodes', ['h', '\n', 'p', '\n', 'q'], ['h', '\n', 'P', '\n', 'q'], [0, 1, -1, 3, 4]],
  ['the suffix before an earlier pair of the middle', ['c', 'a'], ['a', 'b', 'a'], [-1, -1, 1]],
  ['white space outvotes no block', ['a', '\n', 'b', '\n', 'c', '\n', 'V'], ['x', '\n', 'V', '\n', 'y', '\n', 'z'],
   [-1, -1, 6, -1, -1, -1, -1]],
  ['white space of any kind in the middle', ['a', ' \t\n', 'b'], ['x', ' \t\n', 'y'], [-1, -1, -1]],
  ['text that is not blank in the middle', ['a', ' t ', 'b'], ['x', ' t ', 'y'], [-1, 1, -1]],
  ['a shown block without a key', ['a', undefined, 'c'], ['a', 'b', 'c'], [0, -1, 2]],
];

for (const [name, previous, next, expected] of table) {
  test(`reuse: ${name}`, () => {
    assert.deepEqual(reuse(previous, next), expected);
  });
}

test('reuse: a middle of more than middleLimit pairs reuses nothing', () => {
  // The shown and the new blocks have only m in common.
  const side = Math.sqrt(middleLimit);
  assert.ok(Number.isInteger(side));
  const shown = ['m', ...Array.from({ length: side }, (_, index) => `old ${index}`)];
  const next = [...Array.from({ length: side - 1 }, (_, index) => `new ${index}`), 'm'];
  assert.ok(shown.length * next.length > middleLimit);
  assert.deepEqual(reuse(shown, next), next.map(() => -1));
  const within = shown.slice(0, side);
  assert.equal(within.length * next.length, middleLimit);
  assert.deepEqual(reuse(within, next), [...next.slice(1).map(() => -1), 0]);
});

test('reuse: the prefix and suffix of a document of any length', () => {
  // Around an edit, more blocks than a middle of middleLimit pairs holds.
  const around = Array.from({ length: Math.sqrt(middleLimit) }, (_, index) => `block ${index}`);
  const shown = [...around, 'edited', ...around];
  const pairs = reuse(shown, [...around, 'edited again', ...around]);
  assert.deepEqual(pairs, [...around.keys(), -1, ...around.map((_, index) => around.length + 1 + index)]);
});

// Every list of at most 4 keys among a, b, c and a blank one: the loop also
// visits the lists it adds.
const blank = '\n';
const lists = [[]];
for (const list of lists) {
  if (list.length < 4) lists.push(...['a', 'b', 'c', blank].map((key) => [...list, key]));
}

// The earliest indices of A at which B's elements at INDICES appear in
// order, or null when they do not.
function embed(a, b, indices) {
  const found = [];
  for (const j of indices) {
    const i = a.indexOf(b[j], found.length ? found.at(-1) + 1 : 0);
    if (i < 0) return null;
    found.push(i);
  }
  return found;
}

// What the middle must give, from the contract: of the subsets of B's
// indices without a blank key that appear in A, the largest, then the first
// in lexicographic order (indices of one digit compare as text), paired with
// the earliest indices of A.
function longest(a, b) {
  const subsets = [[]];
  for (let j = 0; j < b.length; j += 1) {
    if (b[j] !== blank) subsets.push(...subsets.map((subset) => [...subset, j]));
  }
  const common = subsets.filter((subset) => embed(a, b, subset));
  common.sort((x, y) => y.length - x.length || x.join().localeCompare(y.join()));
  const pairs = b.map(() => -1);
  embed(a, b, common[0]).forEach((i, k) => { pairs[common[0][k]] = i; });
  return pairs;
}

test('reuse: as its contract says, on every pair of short lists', () => {
  for (const previous of lists) {
    for (const next of lists) {
      const context = `${previous} and ${next}`;
      const pairs = reuse(previous, next);
      pairs.forEach((index, j) => assert.ok(index < 0 || previous[index] === next[j], context));
      const reused = pairs.filter((index) => index >= 0);
      reused.forEach((index, k) => assert.ok(k === 0 || index > reused[k - 1], context));
      // The common prefix, then the common suffix of what follows it.
      const shorter = Math.min(previous.length, next.length);
      let prefix = 0;
      while (prefix < shorter && previous[prefix] === next[prefix]) prefix += 1;
      let suffix = 0;
      while (prefix + suffix < shorter && previous.at(-1 - suffix) === next.at(-1 - suffix)) suffix += 1;
      const middle = longest(previous.slice(prefix, previous.length - suffix),
                             next.slice(prefix, next.length - suffix));
      assert.deepEqual(pairs, [...Array(prefix).keys(), ...middle.map((index) => (index < 0 ? index : prefix + index)),
                               ...Array.from({ length: suffix }, (_, k) => previous.length - suffix + k)], context);
    }
  }
});
