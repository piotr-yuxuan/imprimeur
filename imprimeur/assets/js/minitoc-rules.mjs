// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The rules of docs/minitoc-rules.md, which is the authority, as pure functions of a
// model, that file's JSON: no page, no clock, no state.  The fixtures written by hand
// from it judge them, as they judge sommaire's, with which no code is shared.

export const minChildren = 2;
export const maxDepth = 2;
export const rootLevels = 2;
export const sectionLevels = 1;

const worth = (node, depth) => depth <= maxDepth && node.children.length >= minChildren;

// R3: the root never has an inline minitoc, and R2: an explicit table wins over it.
const candidate = (node, depth) => depth > 0 && !node.explicit && worth(node, depth);

function entry(node, levels) {
  return {
    id: node.id,
    title: node.title,
    archived: node.archived,
    children: levels > 1 ? node.children.map((child) => entry(child, levels - 1)) : [],
  };
}

const reference = ({ id, title }) => ({ id, title });

// The inline minitocs, in document order: R3.  No candidate lies deeper than maxDepth,
// so the walk stops there, whatever the depth of the document.  The merging relies on
// that constant being 2: only the first child of an anchor can then be merged, and
// nothing under it can be a candidate.
export function minitocs(model) {
  const visit = (node, depth, merged) => {
    const anchor = !merged && candidate(node, depth);
    const [first] = node.children;
    const expansion = anchor && !node.intro && first && candidate(first, depth + 1) ? first : null;
    const own = anchor
      ? [{
          anchor: node.id,
          entries: node.children.map((child) => entry(child, child === expansion ? sectionLevels + 1 : sectionLevels)),
        }]
      : [];
    const below = depth < maxDepth
      ? node.children.flatMap((child) => visit(child, depth + 1, child === expansion))
      : [];
    return [...own, ...below];
  };
  return visit(model.root, 0, false);
}

// The headings from the root down to the one of id ACTIVE, so that an index is a depth.
// Ids count in preorder, so the way down goes through the last child that does not
// exceed it.  An id that the model does not hold is the caller's error.
function chainTo(model, active) {
  const chain = [model.root];
  while (chain.at(-1).id !== active) {
    const next = chain.at(-1).children.findLast((child) => child.id <= active);
    if (!next) throw new RangeError(`No heading of id ${active} in the model`);
    chain.push(next);
  }
  return chain;
}

// The tail of CHAIN from the section of R4, or nothing when it has no section.
function fromSection(chain) {
  const depth = chain.findLastIndex((node, index) => worth(node, index));
  return depth < 0 ? [] : chain.slice(depth);
}

// The local minitoc for the active heading: R4.
export function local(model, active) {
  const chain = chainTo(model, active);
  const way = fromSection(chain);
  const [section, current] = way;
  const levels = section === chain[0] ? rootLevels : sectionLevels;
  return {
    active,
    section: section ? reference(section) : null,
    current: current ? current.id : null,
    entries: section ? section.children.map((child) => entry(child, levels)) : [],
    path: chain.slice(1).map(reference),
  };
}

// What each root of a scope makes of the way down to the active heading.
const scopeRoots = new Map([['document', (chain) => chain], ['section', fromSection]]);

// The list of a scope, in document order.  The walk does not recurse, since a document
// chooses its depth.
export function panel(model, active, root, depth) {
  const limit = depth === 'all' ? Infinity : depth;
  if (!(limit >= 1 && Math.floor(limit) === limit)) throw new RangeError(`No scope has the depth ${depth}`);
  const wayFrom = scopeRoots.get(root);
  if (!wayFrom) throw new RangeError(`No scope has the root ${root}`);
  const way = wayFrom(chainTo(model, active));
  const pending = way.slice(0, 1).flatMap(({ children }) => children).map((node) => ({ node, level: 1 })).reverse();
  const entries = [];
  while (pending.length > 0) {
    const { node, level } = pending.pop();
    entries.push({ id: node.id, title: node.title, archived: node.archived, depth: level });
    if (level < limit) {
      for (const child of node.children.toReversed()) pending.push({ node: child, level: level + 1 });
    }
  }
  return {
    root: way.slice(0, 1).map(reference)[0] ?? null,
    current: way.slice(1, limit + 1).map(({ id }) => id).at(-1) ?? null,
    entries,
  };
}

const stepDeltas = new Map([['+', 1], ['-', -1]]);

// The depth after one step of the reader's, KEY `+` going deeper and `-` shallower:
// "The scope".  A step looks at the root as it stands at that moment.
export function stepDepth(model, active, root, depth, key) {
  const delta = stepDeltas.get(key);
  if (!delta) throw new RangeError(`No step has the key ${key}`);
  const rows = panel(model, active, root, 'all').entries;
  const deepest = Math.max(0, ...rows.map((row) => row.depth));
  if (depth === 'all' && delta > 0) return 'all';
  const known = rows.length > 0 ? deepest : depth;
  const next = (depth === 'all' ? deepest : Math.min(depth, known)) + delta;
  if (next < 1) return 1;
  return rows.length > 0 && next >= deepest ? 'all' : next;
}
