// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirements (plan 004, "Page to Emacs" and acceptance 4): only scrolls that
// follow a wheel, key, touch or pointer event within 250 ms reach Emacs, one per
// 50 ms; a scroll that the page made itself, as Emacs or a link asked, reaches it
// not at all, even right after an input.  The page moves for a scroll of Emacs
// that it has not applied, and not for the same one sent again; a page that shows
// nothing does not count it as applied.  "Lines on the page" and acceptance 4: a
// scroll names the line of the block at the top of the view, and a block too long
// for the view, or a format without lines, is followed by proportion; the source's
// first line and the page's top stand for each other.  Plan 006, "R4 on the page":
// the active heading is the last at or above a line 25% down the view, or at or above
// Emacs's point, and with none there the root; a heading that knows no place counts
// as absent.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { lineMap } from '../../imprimeur/assets/js/line-map.mjs';
import {
  activeShare, applies, inputWindow, lastUpTo, lineAt, offsetOfLine, onScroll, postInterval,
} from '../../imprimeur/assets/js/sync.mjs';

test('the rule gives 250 ms for an input and 50 ms between posts', () => {
  assert.equal(inputWindow, 250);
  assert.equal(postInterval, 50);
});

test('a scroll goes to Emacs as its table says', () => {
  const never = -Infinity;
  for (const [title, expected, input, posted, position, now, decision] of [
    ['just after an input', null, 1000, never, 500, 1010, 'post'],
    ['at the limit of an input', null, 1000, never, 500, 1250, 'post'],
    ['just past the limit of an input', null, 1000, never, 500, 1250.5, 'ignore'],
    ['with no input yet', null, never, never, 500, 1000, 'ignore'],
    ['long after a post, past an input', null, 1000, 1100, 500, 1300, 'ignore'],
    ['too soon after a post', null, 1000, 1080, 500, 1100, 30],
    ['right after a post', null, 1000, 1100, 500, 1100, 50],
    ['the moment the interval ends', null, 1000, 1050, 500, 1100, 'post'],
    ['after the interval', null, 1000, 1040, 500, 1100, 'post'],
    ['the page moved itself, with no input', 500, never, never, 500, 1000, 'echo'],
    ['the page moved itself, right after an input', 500, 1000, never, 500, 1010, 'echo'],
    ['the page moved itself, right after a post', 500, 1000, 1005, 500, 1010, 'echo'],
    ['the reader moved on from there', 500, 1000, never, 501, 1010, 'post'],
    ['the page moved elsewhere with no input', 500, never, never, 501, 1010, 'ignore'],
    ['at the top of the page', 0, 1000, never, 0, 1010, 'echo'],
  ]) {
    assert.equal(onScroll({ expected, input, posted }, position, now), decision, title);
  }
});

test('a scroll of Emacs moves the page as its table says', () => {
  for (const [title, applied, seq, shown, moves] of [
    ['the first, on a page that shows a revision', 0, 1, 1, true],
    ['the next', 4, 5, 3, true],
    ['one further on', 4, 9, 3, true],
    ['the same again, as for point alone', 5, 5, 3, false],
    ['an older one', 5, 4, 3, false],
    ['the first, on a page that shows nothing yet', 0, 1, 0, false],
    ['the next, on a page that shows nothing yet', 4, 5, 0, false],
  ]) {
    assert.equal(applies(applied, seq, shown), moves, title);
  }
});

// Blocks at lines 1, 11 and 21 of a document of 30 lines, below a title of 100,
// the one at 11 being much longer than a view of 600.
const page = lineMap([[1, 100], [11, 300], [21, 2000], [30, 2100]].map(([line, offset]) => ({ line, offset })), 30, 2100);

test('the page goes to a line along the map, and to its top for the first', () => {
  for (const [line, offset] of [
    [0, 0], [1, 0], [11, 300], [16, 1150], [21, 2000], [30, 2100], [90, 2100],
  ]) {
    assert.equal(offsetOfLine(page, line), offset, `line ${line}`);
  }
});

test('the page names the line of the block there', () => {
  for (const [title, offset, view, line] of [
    ['the top', 0, 600, 1],
    ['past the top', -5, 600, 1],
    ['the title', 50, 600, 1],
    ['the start of a block', 100, 600, 1],
    ['within a block', 299, 600, 1],
    ['the start of the next', 300, 600, 11],
    ['within a block that fits', 2050, 600, 21],
    ['the end', 2100, 600, 30],
    ['within a block longer than the view', 1150, 600, 16],
    ['within it, to the line above', 1160, 600, 16],
    ['the start of it all the same', 300, 600, 11],
    ['a block just a view long', 1150, 1700, 11],
    ['a block just longer than the view', 1150, 1699, 16],
  ]) {
    assert.equal(lineAt(page, offset, view), line, title);
  }
});

test('the page above a first block that starts lower in the source', () => {
  const map = lineMap([{ line: 3, offset: 100 }, { line: 9, offset: 200 }], 10, 300);
  assert.equal(lineAt(map, 0, 600), 1);
  assert.equal(lineAt(map, 50, 600), 3);
  assert.equal(offsetOfLine(map, 1), 0);
  assert.equal(offsetOfLine(map, 2), 100);
});

test('the page without lines goes by proportion, from the first line on', () => {
  const map = lineMap([], 100, 2000);
  assert.equal(offsetOfLine(map, 1), 0);
  assert.equal(offsetOfLine(map, 50), 1000);
  for (const [offset, line] of [[0, 1], [10, 1], [40, 2], [1000, 50], [1010, 50], [1999, 99], [2000, 100]]) {
    assert.equal(lineAt(map, offset, 600), line, `offset ${offset}`);
  }
});

test('whatever the map, a line named is a whole number of at least one', () => {
  const single = lineMap([{ line: 0, offset: 10 }], 5, 50);
  for (const map of [single, lineMap([], 0, 0), lineMap([], 0, 500), lineMap([], 3, 0)]) {
    for (const offset of [-1, 0, 1, 10, 500, 1e6]) {
      const line = lineAt(map, offset, 600);
      assert.ok(Number.isInteger(line) && line >= 1, `${JSON.stringify(map)} at ${offset}: ${line}`);
    }
  }
});

test('the active heading is at a quarter of the view', () => {
  assert.equal(activeShare, 0.25);
});

test('the active heading goes as its table says', () => {
  for (const [title, values, limit, index] of [
    ['just past a heading', [0, 10, 20], 21, 2],
    ['exactly on one', [0, 10, 20], 20, 2],
    ['just before one', [0, 10, 20], 19, 1],
    ['before all, the root', [5, 10, 20], 1, 0],
    ['a root that knows no place', [null, 10, 20], 1, 0],
    ['a heading that knows no place', [null, 10, null, 30], 20, 1],
    ['none knows one', [null, null], 20, 0],
  ]) {
    assert.equal(lastUpTo(values, limit), index, title);
  }
});
