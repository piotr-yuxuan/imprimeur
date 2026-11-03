// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// What the page decides about scrolling.  Each decision is pure: it sees
// numbers alone, with the time as an argument, and knows nothing of the page.
// An offset runs along the page's block axis, whichever that is.

import { lineForOffset, offsetForLine } from './line-map.mjs';

// A scroll of the page is the reader's when it comes within this many
// milliseconds of a wheel, key, touch or pointer event.
export const inputWindow = 250;

// The least time between two scrolls posted to Emacs, in milliseconds.
export const postInterval = 50;

// The line across the view at which a page finds its active heading, when it goes by
// its own place, as a share of the view from where the view starts.
export const activeShare = 0.25;

// One step of a zoom by the wheel, in the units of wheelDeltaY: a notch of a mouse's
// wheel, which a touchpad or a fine wheel sends in parts.
export const wheelNotch = 120;

// What to do about a scroll that has brought the page to POSITION at the time
// NOW.  EXPECTED is where the page last moved itself, as Emacs or a link asked,
// INPUT the time of the reader's last input, POSTED that of the last post.
// `echo`: this is that move, even right after an input.  `ignore`: no input of
// the reader's comes before it, as for a change of the page's own height.
// `post`: Emacs is to hear of it.  A number: the milliseconds until it may.
export function onScroll({ expected, input, posted }, position, now) {
  if (position === expected) return 'echo';
  if (now - input > inputWindow) return 'ignore';
  const wait = posted + postInterval - now;
  return wait > 0 ? wait : 'post';
}

// Whether the scroll SEQ of Emacs moves a page that has applied the one APPLIED
// and shown the revision SHOWN.  Emacs numbers its scrolls and sends the number
// again when point alone moves, or when a page reports a revision, so that only
// a page that has never been aligned moves then.  A page that shows nothing has
// nowhere to go, and gets it again when it reports its first revision.
export function applies(applied, seq, shown) {
  return shown > 0 && seq > applied;
}

// The offset on the page of LINE, along MAP.  The source's first line is the
// page's top, whatever stands above the first block, such as the title.
export function offsetOfLine(map, line) {
  return line <= 1 ? 0 : offsetForLine(map, line);
}

// The line that the page names at OFFSET, along MAP, in a view of VIEW long: that
// of the block there.  A block too long to be seen whole, up to the next point of
// the map, is followed through by interpolation, and so is a page without lines,
// which is one such block.  The page's top is the source's first line.
export function lineAt(map, offset, view) {
  if (offset <= 0) return 1;
  const here = Math.max(0, map.findLastIndex((point) => point.offset <= offset));
  const next = map[here + 1];
  const line = next && next.offset - map[here].offset > view ? lineForOffset(map, offset) : map[here].line;
  return Math.max(1, Math.floor(line));
}

// The index of the last of VALUES at or before LIMIT, each a line or an offset along
// the page, or null if it has none.  None of them there means the first, the root's,
// which holds whatever comes before any heading.
export function lastUpTo(values, limit) {
  return Math.max(0, values.findLastIndex((value) => value !== null && value <= limit));
}

// The line at OFFSET along MAP, with its fraction: a place to come back to, where lineAt
// names a line for Emacs.  The page's top is the source's first line.
export function exactLine(map, offset) {
  return offset <= 0 ? 1 : lineForOffset(map, offset);
}

// The whole STEPS that a wheel event of DELTA completes, with REST left of the ones before,
// each towards the larger when positive; and the REST that it leaves.
export function wheelSteps(rest, delta) {
  const total = rest + delta;
  const steps = Math.trunc(total / wheelNotch) + 0;
  return { steps, rest: total - steps * wheelNotch };
}
