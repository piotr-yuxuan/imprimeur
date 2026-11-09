// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The minitocs of the page, the third adapter and the surface of docs/reference/minitoc-rules.md.
// readOutline makes the tree from the flat headings of a page that shows them, and the
// rules decide the rest.  The pill says the local minitoc, its popover lists a scope, and
// a run's anchor has a button that opens its inline minitoc.  Titles reach the page as
// text.  What depends on the page's block axis or on following Emacs is the runtime's,
// which mountMinitoc asks; what the document holds of its tables, finish.lua has marked.

import { firstLine } from './line-map.mjs';
import { local, minitocs, panel, stepDepth } from './minitoc-rules.mjs';

// A heading that pandoc made has an id under its prefix, unlike one written in raw HTML,
// which the rules leave out; one in a block quote or a list item has an id too, which
// pandoc's own table of contents leaves out.  So may a document forge one, which at worst
// misleads its minitocs.
const headingSelector = ':is(h1, h2, h3, h4, h5, h6)[id^="doc-"]';

const outsideOutline = 'blockquote, li';

// What is text on the page though it holds none, and what toc-org names its container by.
const substantive = 'img, video, audio, svg, math, hr, picture, canvas';
const containerTag = /^TOC(?:[@_]\d(?:[@_][a-z]+)?)?$/i;

// In Org, a cookie of statistics anywhere, and a priority first in what the keyword leaves.
const statistics = /\[\d*(?:%|\/\d*)\]/g;
const priority = /^\s*\[#(?:[A-Za-z]|\d{1,2})\]/;

const tidy = (text) => text.replaceAll('­', '').replace(/\s+/g, ' ').trim();

// What the reader sees of a heading, by "Titles" of the rules.  pandoc's Org reader keeps
// a priority and a cookie in the text; a keyword and the tags it marks.
function titleOf(heading, org) {
  if (!org) return tidy(heading.textContent);
  const alternative = heading.getAttribute('data-alt_title');
  if (alternative) return tidy(alternative);
  const text = [...heading.childNodes]
    .filter((node) => !node.matches?.('.tag, .todo, .done'))
    .map((node) => node.textContent)
    .join('');
  return tidy(text.replace(priority, '').replace(statistics, ''));
}

// The line in the source of a heading, or null: the runtime's for a block, or its own.
function lineOf(heading) {
  const line = heading.getAttribute('data-line');
  return line === null ? firstLine(heading.getAttribute('data-pos')) : Number(line);
}

// The flat headings of MAIN in document order, with the flags of tree schema 1.  ROOT, a
// heading-to-be, takes what comes before any heading and what is the whole document's.
// The walk does not recurse, and goes once over the page.  What it leaves alone of a
// dropped subtree, or of a table up to its end or the next heading, is no introduction.
function readHeadings(main, org, root) {
  const headings = [];
  let current = root;
  let dropped = null;
  let table = false;

  const atHeading = (element) => {
    const level = Number(element.tagName[1]);
    if (dropped !== null && level > dropped) return;
    dropped = null;
    table = false;
    const tags = org ? [...element.querySelectorAll(':scope > .tag')].map((tag) => tag.dataset.tagName) : [];
    const container = tags.some((tag) => containerTag.test(tag));
    if (container) root.explicit = true;
    if (container || (org && element.hasAttribute('data-imprimeur_notoc'))) {
      dropped = level;
      return;
    }
    current = { element, level, archived: tags.includes('ARCHIVE'), intro: false, explicit: false };
    headings.push(current);
    if (element.hasAttribute('data-imprimeur-toc')) {
      root.explicit = true;
      table = true;
    }
  };

  const atMarker = (kind) => {
    if (dropped !== null) return;
    if (kind === 'local') current.explicit = true;
    else root.explicit = true;
    table = kind === 'start';
  };

  const atSubstance = () => {
    if (dropped === null && !table) current.intro = true;
  };

  // Whether to go on into NODE, an element of the page or its text.
  const visit = (node) => {
    if (node.nodeType === Node.TEXT_NODE) {
      if (/\S/.test(node.data)) atSubstance();
      return false;
    }
    if (node.matches(headingSelector) && !node.closest(outsideOutline)) {
      atHeading(node);
      return false;
    }
    if (node.hasAttribute('data-imprimeur-toc')) {
      atMarker(node.getAttribute('data-imprimeur-toc'));
      return false;
    }
    if (org && node.matches('.drawer')) {
      if (node.matches('.CONTENTS')) atMarker('local');
      return false;
    }
    if (node.matches(substantive)) {
      atSubstance();
      return false;
    }
    return true;
  };

  const walker = document.createTreeWalker(main, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => (visit(node) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT),
  });
  while (walker.nextNode());
  return headings;
}

// The tree of the page and the place of each of its ids: { model, places }, a place being
// { element, line }, which the root has only when it is a heading.  FORMAT and TITLE are
// what the page knows of the revision that MAIN shows.
export function readOutline(main, format, title) {
  const org = format === 'org';
  const start = { element: null, level: 0, archived: false, intro: false, explicit: false };
  const headings = readHeadings(main, org, start);
  const lone = !org && headings[0]?.level === 1 && !headings.slice(1).some(({ level }) => level === 1);
  const first = lone ? headings.shift() : start;
  const root = {
    id: 0,
    title: first.element ? titleOf(first.element, org) : title || null,
    archived: false,
    intro: start.intro || first.intro,
    explicit: start.explicit || first.explicit,
    children: [],
  };
  const places = [{ element: first.element, line: first.element && lineOf(first.element) }];
  const stack = [{ level: 0, node: root }];
  headings.forEach(({ element, level, archived, intro, explicit }, index) => {
    const node = { id: index + 1, title: titleOf(element, org), archived, intro, explicit, children: [] };
    while (stack.at(-1).level >= level) stack.pop();
    stack.at(-1).node.children.push(node);
    stack.push({ level, node });
    places.push({ element, line: lineOf(element) });
  });
  return { model: { schema: 1, root }, places };
}

// Where a key sends the reader from LOCAL, the local minitoc of the heading at the top of
// the view: the id of a heading, or null.  ] and [ go to the next and the previous entry,
// ] from the section's own heading to its first; u to the parent of the active heading.
export function movement({ active, current, entries, path }, key) {
  if (key === 'u') return active === 0 ? null : (path.at(-2)?.id ?? 0);
  const index = entries.findIndex(({ id }) => id === current);
  if (key === ']') return entries[index + 1]?.id ?? null;
  return index > 0 ? entries[index - 1].id : null;
}

function element(tag, properties, ...children) {
  const node = document.createElement(tag);
  Object.assign(node, properties);
  node.append(...children);
  return node;
}

// The button of an entry, by which the reader goes to its heading.
function entryButton({ id, title, archived }) {
  const button = element('button', { type: 'button', textContent: title });
  button.dataset.minitocId = id;
  if (archived) button.className = 'imprimeur-minitoc-archived';
  return button;
}

// The list of an inline minitoc, whose entries may have their own, a merged heading's.
function entryList(entries) {
  return element('ul', {}, ...entries.map((entry) => element(
    'li',
    {},
    entryButton(entry),
    ...(entry.children.length > 0 ? [entryList(entry.children)] : []),
  )));
}

// The minitocs of MAIN.  PLACE is what only the runtime knows: active(places) and
// top(places) give an id, of the active heading and of the one at the top of the view,
// view() where the view stands, and goTo(element) goes to a heading, or to the top for
// nothing.  The owner of what it adds
// to the text, which strip takes away before a revision and refresh puts back after it, so
// that the block diff sees the document's markup alone.
export function mountMinitoc(main, place) {
  let outline = null;
  let added = [];
  // The heading whose inline minitoc is open, with its button and its list.
  let open = null;
  // The scope, which holds for as long as this page, and what the popover shows of it.
  const scope = { root: 'section', depth: 1 };
  let drawn = null;
  // Where a key last sent the reader, and where the view stood after it.  A heading near
  // the end of the page may never reach the top of the view, so while the view stands
  // there, the next key counts from that heading, and a key can reach what follows it.
  let moved = null;

  const section = element('span', { className: 'imprimeur-minitoc-section' });
  const count = element('span', { className: 'imprimeur-minitoc-count' });
  const mark = element('span', { className: 'imprimeur-minitoc-mark', textContent: '§' });
  const currentEntry = element('span');
  const pill = element('button', {
    type: 'button', className: 'imprimeur-minitoc-pill', ariaExpanded: 'false', ariaHasPopup: 'true',
  }, mark, ' ', section, ' ', count, currentEntry);
  pill.setAttribute('aria-controls', 'imprimeur-minitoc-popover');

  // The popover's own words are English, left to right, whatever the document's language.
  const english = { type: 'button', lang: 'en', dir: 'ltr' };
  const documentChoice = element('button', { ...english, textContent: 'Document' });
  const sectionChoice = element('button', { ...english, textContent: 'This section' });
  const shallower = element('button', { ...english, textContent: '-', ariaLabel: 'One level fewer' });
  const deeper = element('button', { ...english, textContent: '+', ariaLabel: 'One level more' });
  const depthLabel = element('span');
  const list = element('ul');
  const popover = element('div', {
    id: 'imprimeur-minitoc-popover', className: 'imprimeur-minitoc-popover', hidden: true, tabIndex: -1,
  }, element(
    'div',
    { className: 'imprimeur-minitoc-scope' },
    documentChoice,
    sectionChoice,
    element('span', { className: 'imprimeur-minitoc-depth' }, shallower, ' ', depthLabel, ' ', deeper),
  ), list);
  const box = element('div', { id: 'imprimeur-minitoc', className: 'imprimeur-minitoc', hidden: true }, pill, popover);
  document.body.append(box);

  function drawPill(here) {
    section.textContent = here.section ? here.section.title ?? '' : here.path.map(({ title }) => title).join(' › ');
    mark.hidden = !here.section;
    count.textContent = here.section ? `▾${here.entries.length}` : '';
    currentEntry.textContent = here.path.find(({ id }) => id === here.current)?.title ?? '';
    if (here.current === null) currentEntry.removeAttribute('aria-current');
    else currentEntry.setAttribute('aria-current', 'true');
  }

  // A panel holds no active heading, so this draws only when what it shows changes.
  function drawPanel(active) {
    const shown = panel(outline.model, active, scope.root, scope.depth);
    documentChoice.ariaPressed = String(scope.root === 'document');
    sectionChoice.ariaPressed = String(scope.root === 'section');
    depthLabel.textContent = String(scope.depth);
    const text = JSON.stringify(shown);
    if (text === drawn) return;
    drawn = text;
    list.replaceChildren(...shown.entries.map((row) => {
      const button = entryButton(row);
      if (row.id === shown.current) button.setAttribute('aria-current', 'true');
      const item = element('li', {}, button);
      item.style.setProperty('--imp-minitoc-depth', row.depth);
      return item;
    }));
  }

  function update() {
    if (!outline) return;
    const active = place.active(outline.places);
    drawPill(local(outline.model, active));
    drawPanel(active);
  }

  const goTo = (id) => place.goTo(outline.places[id].element);

  function closeInline() {
    if (!open) return false;
    open.nav.remove();
    open.button.ariaExpanded = 'false';
    open = null;
    return true;
  }

  function openInline(button, entries, heading) {
    closeInline();
    const nav = element('nav', { className: 'imprimeur-minitoc imprimeur-minitoc-inline' }, entryList(entries));
    heading.after(nav);
    added.push(nav);
    button.ariaExpanded = 'true';
    open = { heading, button, nav };
  }

  function setPopover(shown) {
    const opened = !popover.hidden;
    popover.hidden = !shown;
    pill.ariaExpanded = String(shown);
    if (shown && !opened) popover.focus({ preventScroll: true });
    else if (!shown && opened) pill.focus({ preventScroll: true });
  }

  // Put back what strip took away, on the page as it now stands.  An inline minitoc
  // stays open for as long as its heading is still shown and still an anchor.
  function refresh() {
    const wasOpen = open?.heading;
    open = null;
    moved = null;
    outline = readOutline(main, document.documentElement.dataset.format, document.getElementById('imprimeur-title').textContent);
    box.hidden = outline.places.length === 1 && !outline.places[0].element;
    for (const { anchor, entries } of minitocs(outline.model)) {
      const heading = outline.places[anchor].element;
      // Its label is English, but what it shows, a sign and a count, takes its heading's
      // direction, so that the sign turns in right-to-left text.
      const button = element('button', {
        type: 'button',
        className: 'imprimeur-minitoc imprimeur-minitoc-button',
        ariaExpanded: 'false',
        ariaLabel: `Contents of this section: ${entries.length}`,
        lang: 'en',
      });
      button.dataset.count = entries.length;
      button.addEventListener('click', () => {
        if (open?.button === button) closeInline();
        else openInline(button, entries, heading);
      });
      heading.append(button);
      added.push(button);
      if (heading === wasOpen) openInline(button, entries, heading);
    }
    update();
  }

  const step = (key) => {
    scope.depth = stepDepth(outline.model, place.active(outline.places), scope.root, scope.depth, key);
    update();
  };

  // Each answers whether it took the key: one with nothing to do is the skin's, or Emacs's.
  const stepKey = (name) => () => {
    if (popover.hidden) return false;
    step(name);
    return true;
  };
  const moveKey = (name) => () => {
    const from = moved?.view === place.view() ? moved.target : place.top(outline.places);
    const target = movement(local(outline.model, from), name);
    if (target === null) return false;
    goTo(target);
    moved = { target, view: place.view() };
    return true;
  };
  const keys = new Map([
    ['t', () => {
      setPopover(popover.hidden);
      return true;
    }],
    ['+', stepKey('+')],
    ['-', stepKey('-')],
    ['[', moveKey('[')],
    [']', moveKey(']')],
    ['u', moveKey('u')],
    ['Escape', () => {
      if (popover.hidden) return closeInline();
      setPopover(false);
      return true;
    }],
  ]);

  pill.addEventListener('click', () => setPopover(popover.hidden));
  documentChoice.addEventListener('click', () => {
    scope.root = 'document';
    update();
  });
  sectionChoice.addEventListener('click', () => {
    scope.root = 'section';
    update();
  });
  shallower.addEventListener('click', () => step('-'));
  deeper.addEventListener('click', () => step('+'));
  list.addEventListener('click', ({ target }) => {
    const id = target.closest('[data-minitoc-id]')?.dataset.minitocId;
    if (id === undefined) return;
    setPopover(false);
    goTo(Number(id));
  });
  main.addEventListener('click', ({ target }) => {
    const id = target.closest?.('.imprimeur-minitoc-inline [data-minitoc-id]')?.dataset.minitocId;
    if (id !== undefined) goTo(Number(id));
  });

  return {
    strip() {
      for (const node of added) node.remove();
      added = [];
    },
    refresh,
    update,
    key: (name) => Boolean(outline && !box.hidden && keys.get(name)?.()),
  };
}
