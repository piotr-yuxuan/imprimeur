// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirements (plan 004, "Line map" and acceptance 6): anchors (1, 0),
// (11, 100), (21, 400) map line 16 to 250, line 0 to 0 and line 30 to 400, and
// offset 250 back to line 16; an RST fixture, which has no anchor, at line 50
// of 100 maps to half its height.  "data-line": a marker's value is a line when
// it is an integer and nothing else, and the first line of a data-pos is the
// least of its ranges', as a table's lists another range first.  A document
// may write its own marker and data-pos, which can at worst mislead scrolling:
// no value it writes makes the map throw or give anything but a number within
// its ends.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { firstLine, lineForOffset, lineMap, offsetForLine, parseLine } from '../../imprimeur/assets/js/line-map.mjs';

const anchors = [{ line: 1, offset: 0 }, { line: 11, offset: 100 }, { line: 21, offset: 400 }];

test('the anchors of the plan map as it says', () => {
  const map = lineMap(anchors, 30, 400);
  assert.equal(offsetForLine(map, 16), 250);
  assert.equal(offsetForLine(map, 0), 0);
  assert.equal(offsetForLine(map, 30), 400);
  assert.equal(lineForOffset(map, 250), 16);
});

test('an RST fixture at line 50 of 100 maps to half its height', () => {
  const map = lineMap([], 100, 2000);
  assert.equal(offsetForLine(map, 50), 1000);
  assert.equal(lineForOffset(map, 1000), 50);
});

test('both ways, between anchors and at them', () => {
  const map = lineMap(anchors, 30, 400);
  for (const [line, offset] of [[1, 0], [6, 50], [11, 100], [13, 160], [21, 400]]) {
    assert.equal(offsetForLine(map, line), offset);
    assert.equal(lineForOffset(map, offset), line);
  }
  assert.equal(offsetForLine(map, 1.5), 5);
});

test('both ways, clamped at each end', () => {
  const map = lineMap([{ line: 10, offset: 200 }, { line: 20, offset: 300 }], 30, 900);
  assert.equal(offsetForLine(map, 1), 200);
  assert.equal(offsetForLine(map, 29), 300);
  assert.equal(lineForOffset(map, 0), 10);
  assert.equal(lineForOffset(map, 899), 20);
});

test('a single anchor maps everything to itself', () => {
  const map = lineMap([{ line: 7, offset: 70 }], 9, 90);
  for (const line of [0, 7, 9]) assert.equal(offsetForLine(map, line), 70);
  for (const offset of [0, 70, 90]) assert.equal(lineForOffset(map, offset), 7);
});

test('the bisection finds each of many anchors', () => {
  const many = Array.from({ length: 1000 }, (_, index) => ({ line: 2 * index + 1, offset: 5 * index }));
  const map = lineMap(many, 2000, 5000);
  for (const { line, offset } of many) {
    assert.equal(offsetForLine(map, line), offset);
    assert.equal(lineForOffset(map, offset), line);
    assert.equal(offsetForLine(map, line + 1), offset === 4995 ? 4995 : offset + 2.5);
  }
});

test('blocks of no height keep the map a function both ways', () => {
  const map = lineMap([{ line: 1, offset: 0 }, { line: 5, offset: 100 }, { line: 6, offset: 100 },
                       { line: 9, offset: 400 }], 10, 400);
  assert.equal(offsetForLine(map, 5), 100);
  assert.equal(offsetForLine(map, 6), 100);
  assert.equal(offsetForLine(map, 5.5), 100);
  // At an offset that several lines share, the last of them.
  assert.equal(lineForOffset(map, 100), 6);
  assert.equal(lineForOffset(map, 99), 4.96);
  assert.equal(lineForOffset(map, 250), 7.5);
});

test('a point that does not go on from those kept is dropped', () => {
  for (const [title, points, kept] of [
    ['a line that falls', [[1, 0], [50, 100], [2, 200], [60, 300]], [[1, 0], [50, 100], [60, 300]]],
    ['a line repeated', [[1, 0], [5, 100], [5, 200]], [[1, 0], [5, 100]]],
    ['an offset that falls', [[1, 100], [2, 50], [3, 150]], [[1, 100], [3, 150]]],
    ['a first line beyond all others', [[900, 0], [1, 10], [2, 20]], [[900, 0]]],
    ['an offset repeated stays', [[1, 0], [2, 0], [3, 10]], [[1, 0], [2, 0], [3, 10]]],
  ]) {
    assert.deepEqual(lineMap(points.map(([line, offset]) => ({ line, offset })), 100, 900),
                     kept.map(([line, offset]) => ({ line, offset })), title);
  }
});

test('whatever a document writes, the map gives numbers within its ends', () => {
  const map = lineMap([[999999999, 0], [1, 10], [999999999, 20], [5, 30]]
    .map(([line, offset]) => ({ line, offset })), 40, 900);
  for (const line of [0, 1, 20, 999999999]) {
    const offset = offsetForLine(map, line);
    assert.ok(offset >= 0 && offset <= 30);
  }
  for (const offset of [0, 15, 900]) assert.equal(lineForOffset(map, offset), 999999999);
});

test('an empty document or page gives a map all the same', () => {
  for (const [total, height] of [[0, 0], [0, 500], [10, 0], [1, 1]]) {
    const map = lineMap([], total, height);
    assert.ok(Number.isFinite(offsetForLine(map, 5)));
    assert.ok(Number.isFinite(lineForOffset(map, 5)));
  }
  assert.equal(offsetForLine(lineMap([], 0, 500), 3), 0);
  assert.equal(offsetForLine(lineMap([], 10, 0), 3), 0);
  assert.equal(lineForOffset(lineMap([], 10, 0), 0), 10);
});

test('a marker gives a line when it holds an integer alone', () => {
  for (const [text, line] of [
    ['1', 1], ['12', 12], ['0', 0], ['007', 7], ['999999999', 999999999],
    ['', null], ['-1', null], ['1.5', null], ['1e3', null], ['0x10', null], [' 1', null], ['1 ', null],
    ['1\n', null], ['one', null], ['1"><script>', null], ['1000000000', null], [null, null], [undefined, null],
  ]) {
    assert.equal(parseLine(text), line, JSON.stringify(text));
  }
});

test('the first line of a data-pos is the least of its ranges', () => {
  for (const [pos, line] of [
    ['5:1-7:1', 5],
    // A table of pandoc's, from its first row of cells and then from the whole.
    ['2:1-3:1;1:1-4:1', 1],
    ['12:3-13:1;11:3-15:1', 11],
    ['1:1-2:1;7:1-8:1', 1],
    ['7:1-8:1;3:1-4:1;5:1-6:1', 3],
    ['999999999:1-999999999:2', 999999999],
    [null, null], [undefined, null], ['', null], ['own', null], ['5', null], ['5:1', null], ['5:1-', null],
    ['a:1-2:1', null], ['5:1-7:1;', 5], [';5:1-7:1', 5], ['own;5:1-7:1', 5], ['5:1-7:1;own', 5],
    ['1000000000:1-2:1', null], ['x5:1-7:1', null], ['5:1-7:1x', null], ['-5:1-7:1', null],
  ]) {
    assert.equal(firstLine(pos), line, JSON.stringify(pos));
  }
});

test('a data-pos of a great many ranges costs no recursion', () => {
  assert.equal(firstLine(Array.from({ length: 200000 }, (_, index) => `${index + 2}:1-${index + 3}:1`).join(';')), 2);
});
