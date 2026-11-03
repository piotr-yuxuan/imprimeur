// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The source's lines on the page: what the page reads of a line from what a
// document wrote, and the map between lines and offsets.  It sees numbers and
// strings alone.  An offset runs along the page's block axis, whichever that
// is: this map depends on no writing mode.

// The line that TEXT names, when TEXT is an integer of at most nine digits, or
// null.  A marker reaches the page from the document, which may write its own.
export function parseLine(text) {
  return /^\d{1,9}$/.test(text) ? Number(text) : null;
}

// The first line that POS names, a data-pos value, or null.  A table has
// several ranges, each line:column-line:column and separated by semicolons,
// that of its first row of cells before the one of the whole table, so the
// first line is the least, wherever it comes.
export function firstLine(pos) {
  let first = null;
  for (const [, line] of String(pos).matchAll(/(?:^|;)(\d{1,9}):\d+-\d+:\d+(?=;|$)/g)) {
    if (first === null || Number(line) < first) first = Number(line);
  }
  return first;
}

// The map, a list of {line, offset} that interpolation takes as it is, from
// POINTS, the same in the page's order, of a document of TOTAL lines on a page
// of HEIGHT.  A point that does not go on from those kept is dropped, as a
// document can write the line of its own block: its line must rise, and its
// offset must not fall.  Without any point, as in a format that says nothing of
// its lines, the map goes in proportion from the top of both to the end of both.
export function lineMap(points, total, height) {
  const rising = (list) => list.reduce((kept, point) => {
    const last = kept.at(-1);
    if (!last || (point.line > last.line && point.offset >= last.offset)) kept.push(point);
    return kept;
  }, []);
  return points.length > 0 ? rising(points)
    : rising([{ line: 0, offset: 0 }, { line: total, offset: height }]);
}

// The value in TO, by interpolation, of VALUE in FROM, along MAP, which rises in
// FROM.  Beyond either end, it is the value of that end.  The point before VALUE
// is found by bisection, as a page may have many blocks and a scroll comes often.
function along(map, from, to, value) {
  let low = 0;
  for (let high = map.length - 1; low < high;) {
    const middle = Math.ceil((low + high) / 2);
    if (map[middle][from] <= value) low = middle;
    else high = middle - 1;
  }
  const before = map[low];
  const after = map[low + 1];
  if (!after || value <= before[from]) return before[to];
  return before[to] + (value - before[from]) * (after[to] - before[to]) / (after[from] - before[from]);
}

// The offset on the page of LINE, which may hold a fraction, along MAP.
export function offsetForLine(map, line) {
  return along(map, 'line', 'offset', line);
}

// The line, which may hold a fraction, of OFFSET on the page, along MAP.
export function lineForOffset(map, offset) {
  return along(map, 'offset', 'line', offset);
}
