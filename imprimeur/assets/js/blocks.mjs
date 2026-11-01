// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The block diff, which tells the page what an edit left untouched.  It
// sees only the keys of the blocks, one per top-level node, and nothing of
// the page itself.

// The most pairs of blocks that the middle of a diff compares, for a table
// of about 4 MiB; typing never comes near it.  A larger middle reuses
// nothing.
export const middleLimit = 1 << 20;

// The number of offsets from 0 on, at most LIMIT, that satisfy SAME in a row.
function agreeing(limit, same) {
  let count = 0;
  while (count < limit && same(count)) count += 1;
  return count;
}

// Return, for each key of NEXT, the index of the key of PREVIOUS whose
// block it reuses, or -1 for a block made anew.  Reused blocks keep their
// order and none is reused twice.  The common prefix is reused, then the
// common suffix of what follows it, then a longest common subsequence of
// the middle, unless the middle has more than `middleLimit` pairs of
// blocks.  Where several subsequences are longest, each new block in turn
// is reused if one of them allows it, with the earliest old block it can
// be paired with.  Keys are compared with ===.
export function reuse(previous, next) {
  const shorter = Math.min(previous.length, next.length);
  const start = agreeing(shorter, (offset) => previous[offset] === next[offset]);
  const end = agreeing(shorter - start, (offset) => previous.at(-1 - offset) === next.at(-1 - offset));
  // Each key as a small number, so that comparing two costs the same
  // however long their blocks are.
  const ids = new Map();
  const id = (key) => ids.get(key) ?? ids.set(key, ids.size).get(key);
  const a = previous.slice(start, previous.length - end).map(id);
  const b = next.slice(start, next.length - end).map(id);
  const pairs = [...Array(start).keys(), ...b.map(() => -1),
                 ...Array.from({ length: end }, (_, offset) => previous.length - end + offset)];
  if (a.length * b.length > middleLimit) return pairs;
  // lengths[i * width + j]: the length of a longest common subsequence of
  // A from i and B from j.
  const width = b.length + 1;
  const lengths = new Uint32Array((a.length + 1) * width);
  for (let i = a.length - 1; i >= 0; i -= 1) {
    for (let j = b.length - 1; j >= 0; j -= 1) {
      lengths[i * width + j] = a[i] === b[j] ? lengths[(i + 1) * width + j + 1] + 1
        : Math.max(lengths[(i + 1) * width + j], lengths[i * width + j + 1]);
    }
  }
  for (let i = 0, j = 0; j < b.length; j += 1) {
    const k = a.indexOf(b[j], i);
    if (k >= 0 && lengths[(k + 1) * width + j + 1] + 1 === lengths[i * width + j]) {
      pairs[start + j] = start + k;
      i = k + 1;
    }
  }
  return pairs;
}
