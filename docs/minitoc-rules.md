# Minitoc rules

This file is the authority on which mini tables of contents a document gets, and
where. Two implementations follow it: `sommaire/sommaire-rules.el` for Org and
Markdown buffers, and the JavaScript of imprimeur's page. The fixtures in
`tests/fixtures/minitoc/`, written by hand from this file, judge both. When an
implementation and this file disagree, the implementation is wrong.

Three parties are involved, and only the second one decides anything:

- An *adapter* reads a document and produces a tree (tree schema 1). There is one
  for Org, one for Markdown and one for the page.
- The *rules* are two pure functions of that tree. They produce the decisions (the
  decision schema).
- A *surface* draws the decisions: a header line and overlays in Emacs, a pill and
  buttons in the page.

Below, a *heading* is a node of the tree, the root included, unless the text says
otherwise.

## Constants

| Name | Value | Meaning |
|---|---|---|
| `min_children` | 2 | R1: the fewest children of a heading worth a minitoc |
| `max_depth` | 2 | R1: the greatest depth of a heading worth a minitoc |
| `root_levels` | 2 | R1: the levels of entries that the root lists |
| `section_levels` | 1 | R1: the levels of entries that any other heading lists |

These are constants, not options, so that the implementations cannot drift.

## Tree schema 1

A model is the JSON object `{"schema": 1, "root": NODE}`. A NODE has these keys, all
required, in this order:

| Key | Type | Meaning |
|---|---|---|
| `id` | integer | The node's number in a preorder walk of the tree; the root is 0 |
| `title` | string or null | The text of its entries; null only at a root with no title |
| `archived` | boolean | An archived heading: listed, dimmed, never expanded |
| `intro` | boolean | Substantive content lies between its metadata and its first child |
| `explicit` | boolean | An explicit table stands in its section (R2) |
| `children` | array of NODE | Its eligible children, in document order |

Invariants:

- Ids count 0, 1, 2 and so on in document order, with no gap. A model holds no
  position: each adapter keeps its own map from id to place, a buffer position or an
  element of the page.
- The *depth* of a node is its distance from the root in the tree, whatever the
  levels of the headings: the root has depth 0, its children depth 1. No rule reads
  a heading's level.
- An archived node has no children, `intro` false and `explicit` false. The root is
  not archived.

### What an adapter puts in the tree

**Eligible headings.** The tree holds the root and every eligible heading. A heading's
parent is the nearest preceding eligible heading of a lower level, or else the root,
so levels may skip. These are not eligible:

- In Org, each with its whole subtree: a COMMENT heading, a heading with a tag of
  `org-export-exclude-tags` (`:noexport:` by default), a heading with the property
  `UNNUMBERED: notoc`, and a toc-org container, that is a heading tagged `:TOC:` or
  with a variant such as `:TOC_2:`.
- In Markdown, what merely looks like a heading: inside front matter, fenced code,
  indented code or an HTML block, a comment among them.
- In Markdown, a heading inside a block quote, a list item or a footnote definition,
  which belongs to that block and not to the outline of the document. Pandoc's syntax
  tree holds it, but its table of contents and its sections leave it out.

A Markdown heading inside a `<div>` is eligible when a blank line has ended the HTML
block of the opening tag, as pandoc's table of contents lists it. A heading that carries
toc-org's marker is eligible too, for the same reason. An adapter's Markdown headings
are therefore checked against that table of contents, with `toc-depth` at 6, and not
against every `Header` of pandoc's syntax tree.

**Archived headings.** An Org heading with the tag `ARCHIVE` stays in the tree as a
leaf: its body and its descendants are not read. Markdown has no archived heading.

**The root.**

- In Org, the root is the document, and `#+title` gives its title.
- In Markdown, when the first heading has level 1 and no other heading has, that
  heading is the root. Otherwise the root is the document, and the `title` of the
  front matter gives its title.
- With no such title, `title` is null.
- Under narrowing, R6 replaces all of the above.

**Titles.** In Org, `title` is the property `ALT_TITLE` when the heading has one, or
else the heading's text without its TODO keyword, priority, tags and statistics
cookies. A priority is a cookie `[#X]`, where X is one letter or a number of at most
two digits, right after the keyword, or at the start of the text when there is no
keyword; anywhere else, such a cookie stays in the title, whatever the version of Org
makes of it. In Markdown, it is the heading's text without the marks of the heading and
without HTML comments.

Any other inline markup, such as a link or emphasis, stays in a buffer's title as its
source has it, since an adapter of Emacs reads the heading's text and renders nothing. A
page sees what pandoc rendered, and so has the rendered text. The two differ on such a
heading, which is why the fixtures use plain titles.

**The introduction.** `intro` is true when something substantive lies between the
heading's metadata and its first child, or the end of its subtree when it has no
child. For the root, that span starts where the document starts. These are not
substantive: blank lines, planning lines, drawers, keywords (`#+html:` and `#+TOC:`
among them), comments, Markdown link definitions, the tags `<div>` and `</div>` alone
on their line, and an explicit table, a toc-org container included. In Markdown, a
table runs from its marker to the marker `<!-- markdown-toc end`, or to the next heading.
In a buffer, any other dropped subtree is substantive, since it is visible text between
two headings, and so is a footnote definition; a page sees neither there.

**Explicit tables.** `explicit` is true at a heading when its section holds one of
these, and at no other heading:

- `#+TOC: headlines N local` before its first child;
- a `:CONTENTS:` drawer, as org-make-toc writes it, before its first child;
- at the root only, for the whole document: a toc-org table (a container heading, or
  in Markdown the marker `<!-- :TOC: -->`, which toc-org expects at the end of a
  heading) or a markdown-toc table (the marker `<!-- markdown-toc start`).

At the root, `explicit` decides nothing under these rules, since the root is never a
candidate and the local minitoc ignores R2. The model carries it for a layout that shows
the root inline.

## The rules

### R1, worth a minitoc

A heading is *worth a minitoc* when it has at least `min_children` children and its
depth is at most `max_depth`. A minitoc's entries are the heading's children, in
`section_levels` level; the root's, in `root_levels` levels. An archived entry is
listed like the others, and a surface dims it.

### R2, an explicit table wins

A heading with `explicit` true never has an automatic inline minitoc, either as an
anchor or merged into one. The local minitoc ignores this rule: an explicit table stands
in one place, and the local minitoc follows the reader everywhere.

### R3, no stacking

A *run* is a maximal chain of headings in which each one is the first child of the
one before it, and the one before it has `intro` false. Every heading belongs to
exactly one run. A run starts at the root, at any child that is not a first child,
and at the first child of a heading with an introduction.

A *candidate* is a heading other than the root that is worth a minitoc and has
`explicit` false. The root is never a candidate, since only the local minitoc shows it.

- A run's *anchor* is its first candidate. It has one inline minitoc, and a button
  "▸ N", where N is the number of its entries.
- A later candidate of the run is *merged*: it has no minitoc and no button, and its
  entry in the anchor's minitoc lists its own children, one level deep.
- With the constants above, only the first child of an anchor at depth 1 can be
  merged, and nothing under it can be a candidate.
- A run without a candidate shows nothing. So a chain in which each heading has one
  child has no inline minitoc and no button.

No other heading carries a button. Opening an inline minitoc closes any other in the
same Emacs window or the same page, so that at most one is open in each.

### R4, the active local section

The *active heading* is the innermost eligible heading that contains the reader's
position:

- a heading's line belongs to that heading;
- a position in a dropped subtree belongs to its nearest eligible ancestor;
- a position under an archived heading belongs to that heading;
- a position before the first heading belongs to the root.

In a buffer, the position is point. The page has its own way of finding it. An
adapter finds the active heading; the rules take its id.

The *section* is the nearest ancestor of the active heading, or the active heading
itself, that is worth a minitoc. R2 does not apply here. When there is none, only the
path shows. The *current* entry is the child of the section that contains the active
heading; it is absent when the active heading is the section.

Each view shows exactly one local minitoc automatically: the header-line segment in a
buffer, the pill in the page. An inline minitoc appears only when the reader opens it,
and leaves the local minitoc as it is.

### R5, placement

An inline minitoc goes after its heading's metadata and before its introduction.

### R6, folding and narrowing

A folded heading hides its minitoc: the surface anchors the minitoc on the first
character after the metadata, which folding makes invisible.

An adapter reads only the accessible part of a buffer. Under narrowing, when that part
starts at a heading and every other heading in it is deeper, that heading becomes the
root, with its own title, `intro` and `explicit`, and depths count from it. Otherwise
the root has a null title and the headings hang from it as usual.

## Decision schema

Both functions take a model and return JSON values made of these shapes, whose keys
are all required, in this order:

| Shape | Value |
|---|---|
| ENTRY | `{"id": integer, "title": string, "archived": boolean, "children": [ENTRY]}` |
| REFERENCE | `{"id": integer, "title": string or null}` |
| BLOCK | `{"anchor": integer, "entries": [ENTRY]}` |
| LOCAL | `{"active": integer, "section": REFERENCE or null, "current": integer or null, "entries": [ENTRY], "path": [REFERENCE]}` |

### Inline minitocs

`minitocs(model)` returns an array of BLOCK, one per run anchor, in document order.
`anchor` is the anchor's id, and there is a button at each anchor and nowhere else.
An ENTRY's `children` is empty, except on a merged heading's entry.

### Local minitoc

`local(model, active)` returns a LOCAL for the active heading whose id is `active`:

- `section` names the section, or is null when there is none.
- `current` is the id of the current entry, or null.
- `entries` lists the section's entries, or is empty when there is no section. Entries
  of the root have their own children as `children`; all others have none.
- `path` runs from the root's child down to the active heading, both included, and
  leaves the root out: it is empty when the root is active.

An `active` that is not an id of the model is the caller's error, and the function
signals it.

## Fixtures

Each fixture in `tests/fixtures/minitoc/` is a document, in Org, in Markdown or in
both, with one model for all its documents:

- `NAME.org`, `NAME.md`: the document.
- `NAME.model.json`: the tree of the document.
- `NAME.expected.json`: `{"schema": 1, "minitocs": [BLOCK], "locals": [LOCAL]}`, with
  one LOCAL per node of the tree, in the order of their ids.

| NAME | Documents | What it pins down |
|---|---|---|
| `chain` | Org, Markdown | Each heading has one child: no inline minitoc, no button, only paths |
| `chain-siblings` | Org, Markdown | The same chain with a sibling at each level: one block, one merged heading; a Markdown root from the front matter |
| `normal` | Org, Markdown | The usual document: a merged heading whose sibling has its own minitoc; the traps of each format, headings in a block quote, a list item and a `<div>` among them; `ALT_TITLE`; a lone first H1 as root |
| `merged-introduction` | Org, Markdown | R3: a merged heading's own introduction changes nothing, since only the heading before it must have none |
| `later-child` | Org, Markdown | R3: an anchor's first child is no candidate and a later one is: that one starts its own run, so two blocks |
| `single-top` | Org, Markdown | An anchor under a root not worth a minitoc: one top-level heading, which in Markdown is no H1, as a lone first H1 would be the root |
| `deep-anchor` | Org, Markdown | An anchor under a parent not worth a minitoc, whose root is worth one |
| `explicit-table` | Org | R2: a local `#+TOC:`, a drawer, a toc-org container; R2 above a candidate and on a merged heading; a nested container, which makes only the root explicit |
| `markdown-toc` | Markdown | R2 at the root of a Markdown document |
| `archive` | Org | Archived entries listed, and archived headings never expanded |
| `comment-noexport` | Org | Dropped subtrees, `UNNUMBERED: notoc`; a dropped subtree as an introduction |
| `narrowing` | Org, Markdown | R6: the model is that of the buffer narrowed to the subtree of "Usage" |
| `skipped-levels` | Org, Markdown | Depth counts in the tree: a heading before any first-level heading, skipped levels |
| `root-introduction` | Org, Markdown | The root's introduction changes nothing inline |
| `untitled` | Org, Markdown | A root with no title that is still a section; two H1 in Markdown |
| `empty` | Org, Markdown | No heading at all, no title, zero bytes |

**The page view.** A page sees only what pandoc kept, so it compares its own model with
the *page view* of `model.json`. The page view is `model.json` itself, except that
`intro` is false at a heading whose only introduction is a dropped subtree: the root
and heading 6 of `comment-noexport`. A page is never narrowed, so `narrowing` has no
page view. The rules still apply to `model.json` as it stands in every implementation.
