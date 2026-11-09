// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The page's runtime.  It follows the session's event stream, fetches each
// new revision, sanitises it and shows it, and hands every link followed to
// Emacs, which decides where it may lead.  The document's markup reaches
// `main` only through DOMPurify; everything else on the page, banners and
// title included, is set as text.

import DOMPurify from '../vendor/dompurify/purify.es.mjs';
import { reuse } from './blocks.mjs';
import { firstLine, lineMap, parseLine } from './line-map.mjs';
import { draw } from './mermaid.mjs';
import { mountMinitoc } from './minitoc-ui.mjs';
import {
  activeShare, applies, exactLine, lastUpTo, lineAt, offsetOfLine, onScroll, wheelSteps,
} from './sync.mjs';

// The session's routes: this module is served at .imprimeur/a/VERSION/js/.
const api = new URL('../../../', import.meta.url);
const main = document.getElementById('imprimeur-main');
const banner = document.getElementById('imprimeur-banner');
const heading = document.getElementById('imprimeur-title');
const palette = document.getElementById('imprimeur-palette');
const root = document.documentElement;

// What this page knows of scrolling: the last scroll of Emacs that it applied,
// by its number; the source's lines when the revision shown left Emacs; the line
// that Emacs last told it or heard from it; the line of Emacs's point, while the
// source and the page follow each other; the time of the reader's last input
// and of the last post; where the page last moved itself, until the next scroll
// event; the timer of a post to come; and what a zoom came back to, the line and
// where the page then stood, or null.
const sync = {
  seq: 0, total: 0, line: null, point: null, input: -Infinity, posted: -Infinity, expected: null, flush: null,
  kept: null,
};

// Beyond DOMPurify's defaults: elements that submit, take input, style the
// whole page or hold inert markup; image maps, whose areas are links; and
// attributes that open a new page, save a file or send a request.
const policy = {
  FORBID_TAGS: ['style', 'form', 'input', 'button', 'select', 'textarea', 'template', 'map', 'area'],
  FORBID_ATTR: ['download', 'target', 'ping'],
  RETURN_DOM_FRAGMENT: true,
};

// The languages written right to left, by their primary subtag: a page in one of
// them is rtl, and any other ltr.
const rightToLeft = new Set(['ar', 'fa', 'ur', 'ps', 'ckb', 'sd', 'ug', 'he', 'yi', 'dv', 'ota']);

// How long a block stays marked once Emacs has asked for it, in milliseconds,
// as long as the animation in base.css.
const flashTime = 800;

// How long a video has to leave NETWORK_NO_SOURCE once shown, in milliseconds,
// which a browser that can load it does at once.
const videoPatience = 1000;

let shown = 0;
let wanted = 0;
let fetching = false;

// How long one change of skin may wait, in all, in milliseconds: for its sheets,
// its render and the fonts.  Past it, the sheet applies on the markup there is.
const skinDeadline = 5000;

// A change of skin under way: the last event to apply, or null, for which a new
// revision waits; the queue, as one runs at a time; the generation of the last
// revision; whether a render has failed since that event; what ends the wait for
// its render; the attributes of the options in force; and whether the banner
// holds a skin's failure.
const skin = {
  newest: null, turn: Promise.resolve(), rendered: 0, failed: false, wake: () => {}, attributes: [], said: false,
};

// The module of the skin shown, if it has one: what ends it, what its failure says,
// which a new revision leaves on the banner, and the handlers of the keys it took.
const skinModule = { controller: null, failure: '', handlers: new Map() };

// Whether a module holds the page where it is, which then neither shows a new revision
// nor follows the scrolling of Emacs; and the revision that it asked to see anyway.
const holding = { held: false, asked: 0 };

// What says where a block comes from in the source, which an edit above it
// changes, and which a block that stays takes from the new text.
const sourceAttributes = ['data-pos', 'data-line'];

// The key of each block in main, a top-level node: its sanitised HTML
// without the attributes above.  A block keeps the key it was shown with,
// whatever happened to it since, until something in it fails to load.
const keys = new WeakMap();

// The timer of the next look at the videos, and the links that the page has made.
let videoCheck = null;
const offered = new WeakSet();

function post(message) {
  return fetch(new URL('post', api), {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(message),
  });
}

function say(kind, text) {
  banner.dataset.kind = kind;
  banner.textContent = text;
  banner.hidden = !text;
}

// What a skin's sticky bar covers of the view's start, in pixels: where the view
// starts for what scrolling aligns.  base.css registers the property as a length.
function viewInset() {
  return parseFloat(getComputedStyle(root).getPropertyValue('--imp-view-inset')) || 0;
}

// The page along its block axis.  This function and scrollToOffset alone know
// that axis to be vertical, so that a vertical skin has only them to replace.
// `offset` is where the view starts, or where EVENT happened if given, `view` how
// long it is and `height` how long the page is; `along` says how far along an element
// is; `points` has each block that knows its line, as far along as it is.
function measure(event) {
  const start = window.scrollY;
  const along = (element) => element.getBoundingClientRect().top + start;
  return {
    offset: start + (event ? event.clientY : viewInset()),
    view: window.innerHeight,
    height: document.documentElement.scrollHeight,
    along,
    get points() {
      return [...main.querySelectorAll(':scope > [data-line]')].map((block) => ({
        line: Number(block.getAttribute('data-line')),
        offset: along(block),
        block,
      }));
    },
  };
}

function scrollToOffset(offset) {
  window.scrollTo({ top: offset - viewInset(), behavior: 'instant' });
}

// The map of the page as MEASURED, whose last block ends with the source.
function pageMap({ height, points }) {
  return lineMap(points.length > 0 ? [...points, { line: sync.total, offset: height }] : [], sync.total, height);
}

// Scroll the page by MOVE, as Emacs or a link asks: Emacs is to hear nothing of it.
function moveItself(move) {
  clearTimeout(sync.flush);
  sync.flush = null;
  move();
  sync.expected = measure().offset;
}

// The minitocs ask here what depends on the page's block axis and on following Emacs.
// The active heading of R4 is that of Emacs's point, while the page follows it and the
// headings know their lines, and otherwise the last above the line at activeShare of the
// view.  A heading at the view's very start is where the page went for one, so a move
// from it counts from there.  A place is { element, line }, and the root may have neither.
const offsets = (places, measured) => places.map(({ element }) => (element ? measured.along(element) : null));
const minitoc = mountMinitoc(main, {
  active(places) {
    const lines = places.map(({ line }) => line);
    if (sync.point !== null && !holding.held && lines.some((line) => line !== null)) return lastUpTo(lines, sync.point);
    const measured = measure();
    return lastUpTo(offsets(places, measured), measured.offset + activeShare * measured.view);
  },
  top(places) {
    const measured = measure();
    return lastUpTo(offsets(places, measured), measured.offset + 1);
  },
  view: () => measure().offset,
  // Like the wheel, so that Emacs follows the reader.  Rounded up, or a heading at a
  // fraction of a pixel would leave the block before it at the top of the view.
  goTo(element) {
    sync.input = performance.now();
    scrollToOffset(element ? Math.ceil(measure().along(element)) : viewInset());
  },
});

// Tell Emacs the line at the top of the view, if it does not know it.
function report() {
  if (holding.held) return;
  const measured = measure();
  const line = lineAt(pageMap(measured), measured.offset, measured.view);
  sync.posted = performance.now();
  if (line === sync.line) return;
  sync.line = line;
  post({ type: 'scroll', line, seq: sync.seq });
}

// Give each block of FRAGMENT, which holds a document's markup, its line in the
// source as its data-line, from the marker before it, which goes, so that it
// stands between no two blocks, or else from its own data-pos.  A marker is empty
// and at the top level; the document may write its own, which at worst misleads
// scrolling.  Its own data-line on a block goes.
function readLines(fragment) {
  let marked = null;
  for (const element of [...fragment.children]) {
    if (element.matches('div[data-imprimeur-line]:empty')) {
      marked = parseLine(element.getAttribute('data-imprimeur-line'));
      element.remove();
    } else {
      const line = marked ?? firstLine(element.getAttribute('data-pos'));
      if (line === null) element.removeAttribute('data-line');
      else element.setAttribute('data-line', line);
      marked = null;
    }
  }
}

// Only the blocks that an edit touched are replaced.  DOMPurify builds the
// fragment in a document of its own, which loads nothing, so a block that
// is not shown fetches no picture and no video.
function show(doc) {
  const fragment = DOMPurify.sanitize(doc.html, policy);
  readLines(fragment);
  minitoc.strip();
  const blocks = [...fragment.childNodes];
  const bare = fragment.cloneNode(true);
  for (const element of bare.querySelectorAll('[data-pos], [data-line]')) {
    element.removeAttribute('data-pos');
    element.removeAttribute('data-line');
  }
  const box = bare.ownerDocument.createElement('div');
  const blockKeys = [...bare.childNodes].map((node) => {
    box.replaceChildren(node);
    return box.innerHTML;
  });
  const live = [...main.childNodes];
  const reused = reuse(live.map((node) => keys.get(node)), blockKeys);
  // The blocks kept stay where they are, so that a video plays on, and the
  // new ones go between them.
  const kept = new Set(reused);
  live.forEach((node, index) => {
    if (!kept.has(index)) node.remove();
  });
  let place = main.firstChild;
  blocks.forEach((block, index) => {
    if (reused[index] < 0) {
      keys.set(block, blockKeys[index]);
      main.insertBefore(block, place);
      return;
    }
    const node = live[reused[index]];
    place = node.nextSibling;
    if (node.nodeType !== Node.ELEMENT_NODE) return;
    // Its elements, in document order, take the new block's data-pos and
    // data-line.  What a diagram holds is its drawing's on the page and its
    // code's here; and Mermaid removes what bears the id it draws under, so a
    // block may have lost elements since it was shown.
    const outside = '*:not(pre.mermaid *)';
    const sources = [block, ...block.querySelectorAll(outside)];
    const targets = [node, ...node.querySelectorAll(outside)];
    for (let at = 0; at < Math.min(sources.length, targets.length); at += 1) {
      for (const name of sourceAttributes) {
        const value = sources[at].getAttribute(name);
        if (value === null) targets[at].removeAttribute(name);
        else targets[at].setAttribute(name, value);
      }
    }
  });
  heading.textContent = doc.title;
  heading.hidden = !doc.title;
  document.title = doc.title || 'imprimeur';
  document.documentElement.lang = doc.lang;
  document.documentElement.dir = rightToLeft.has(doc.lang.split('-')[0].toLowerCase()) ? 'rtl' : 'ltr';
  document.documentElement.dataset.format = doc.format;
  document.documentElement.dataset.revision = doc.rev;
  if (doc.error) say('error', doc.error);
  else say(skinModule.failure ? 'error' : 'notice', skinModule.failure || doc.warnings);
  shown = doc.rev;
  sync.total = doc.total;
  // A line that the page knows means another place in this text.
  sync.line = null;
  sync.kept = null;
  minitoc.refresh();
  draw();
  clearTimeout(videoCheck);
  videoCheck = setTimeout(offerStuckVideos, videoPatience);
  document.dispatchEvent(new CustomEvent('imprimeur-shown'));
}

// What fails to load gives up its block's key, so that the next edit makes
// the block anew and the load is tried again: the file may exist by then.
// A video plays on after a failed track, or a failed source with another
// after it.  Such an error does not bubble, so it is caught on its way down.
// A video that cannot play gets a link to the address that the document gave
// it, which goes with its block at that next edit and which Emacs may visit.
// A source or a video names it, unless the video chose among its sources, when
// currentSrc tells.  What names none, or an address that DOMPurify would take
// from a document's own link, gets no link; DOMPurify judges by the last policy
// it used, and those of the document and of a drawing agree on a link's href.
main.addEventListener('error', ({ target }) => {
  if (target.matches('track, source:has(~ source)')) return;
  let block = target;
  while (block.parentNode !== main) block = block.parentNode;
  keys.delete(block);
  if (target.matches('video, video > source')) {
    offerLink(target.closest('video'), target.getAttribute('src') || target.currentSrc);
  }
}, true);

function offerLink(video, address) {
  if (offered.has(video.nextElementSibling) || !address
      || !DOMPurify.isValidAttribute('a', 'href', address)) return;
  const link = document.createElement('a');
  link.href = address;
  link.textContent = 'Open externally';
  link.lang = 'en';
  link.dir = 'ltr';
  offered.add(link);
  video.after(link);
}

// WebKit in an Emacs window can leave a video at NETWORK_NO_SOURCE with no error
// event, which shows a poster and a play disc that do nothing.  Such a video has
// the same link, and keeps its block: loading it again changes nothing.
function offerStuckVideos() {
  for (const video of main.querySelectorAll('video')) {
    if (video.networkState === HTMLMediaElement.NETWORK_NO_SOURCE) {
      offerLink(video, video.getAttribute('src') || video.currentSrc
                || video.querySelector(':scope > source')?.getAttribute('src'));
    }
  }
}

async function fetchDocument() {
  return (await fetch(new URL('doc', api), { cache: 'no-store' })).json();
}

// Fetch revisions until the latest announced is shown; revisions announced
// meanwhile are caught by the same loop, so one fetch runs at a time.  A change
// of skin holds them, and shows the one it waits for in the same task as its sheet.
// A module's hold does too, but for the revision it asked for.
async function update() {
  if (fetching || skin.newest) return;
  fetching = true;
  try {
    while (shown < wanted && !skin.newest && (!holding.held || shown < holding.asked)) {
      const doc = await fetchDocument();
      // A hold raised during the fetch counts, as this revision has not shown yet.
      if (doc.rev <= shown || (holding.held && shown >= holding.asked)) break;
      show(doc);
      await post({ type: 'ready', rev: doc.rev });
    }
  } finally {
    fetching = false;
  }
}

// The attributes of the options: those of the skin named on the root go, as a
// new skin's and a new value's come in the same task.
function setOptions() {
  const prefix = `data-${root.dataset.skin}-`;
  for (const { name } of [...root.attributes]) {
    if (name.startsWith(prefix)) root.removeAttribute(name);
  }
  for (const [name, value] of skin.attributes) root.setAttribute(name, value);
}

// The line at the top of the view, or null while the page shows no text.
function place() {
  if (shown === 0) return null;
  const measured = measure();
  return lineAt(pageMap(measured), measured.offset, measured.view);
}

// Once fonts have come, by DEADLINE, go back to LINE, which Emacs is to hear
// nothing of, and draw the diagrams again in the new look.
async function settle(line, deadline) {
  await Promise.race([document.fonts.ready, deadline]);
  if (line !== null) {
    const target = offsetOfLine(pageMap(measure()), line);
    moveItself(() => scrollToOffset(target));
  }
  draw();
}

function skinTimeout() {
  return new Promise((resolve) => { setTimeout(resolve, skinDeadline); });
}

// Add the sheets of NEXT beside the old ones, whose rules are scoped to the old
// name, so that nothing changes yet.  Return them once they have loaded or failed,
// or at DEADLINE, with the first that has not loaded, if any.
async function loadSheets(next, deadline) {
  const pending = new Set(next.stylesheets);
  const links = next.stylesheets.map((file) => {
    const link = document.createElement('link');
    link.rel = 'stylesheet';
    link.toggleAttribute('data-imprimeur-skin', true);
    link.href = new URL(`../skins/${next.name}/${next.generation}/${file}`, import.meta.url).href;
    return link;
  });
  const settled = links.map((link, index) => new Promise((resolve) => {
    link.addEventListener('load', () => {
      pending.delete(next.stylesheets[index]);
      resolve();
    });
    link.addEventListener('error', resolve);
  }));
  palette.before(...links);
  await Promise.race([Promise.all(settled), deadline]);
  return { links, failed: [...pending][0] };
}

// The document of the render that NEXT waits for, by the event stream that update()
// follows.  A render's error, DEADLINE or a newer skin ends the wait, with nothing.
async function renderedDocument(next, deadline) {
  if (!next.renders) return null;
  const rendered = () => skin.rendered >= next.generation;
  if (!rendered() && !skin.failed && next === skin.newest) {
    await Promise.race([deadline, new Promise((resolve) => { skin.wake = resolve; })]);
  }
  return rendered() ? fetchDocument() : null;
}

// Run MODULE, { file, defaults, keys } or nothing, of the skin NAME at GENERATION.  What
// it adds lasts until its signal aborts, which also takes its keys away and lets go of
// its hold.  A failure, at its import or in its mount, aborts that signal and says so,
// and the page goes on in the skin.  The context is all that a module has of the core:
// from the abort on, what it holds does nothing, so that a late timer changes nothing.
async function mountModule(name, generation, { file, defaults, keys }) {
  if (!file) return;
  const controller = new AbortController();
  const { signal } = controller;
  const handlers = new Map();
  skinModule.controller = controller;
  skinModule.handlers = handlers;
  signal.addEventListener('abort', () => {
    handlers.clear();
    holding.held = false;
    minitoc.update();
    update();
  });
  const context = {
    signal,
    option: (id) => root.getAttribute(`data-${name}-${id}`) ?? defaults[id],
    key(key, handler) {
      if (!keys.includes(key)) throw new Error(`The manifest of ${name} declares no key ${key}`);
      if (!signal.aborted) handlers.set(key, handler);
    },
    hold(flag) {
      if (signal.aborted) return;
      holding.held = flag;
      minitoc.update();
      update();
    },
    latest() {
      if (signal.aborted) return;
      holding.asked = wanted;
      update();
    },
    goToLine(line) {
      if (!signal.aborted) post({ type: 'goto', line, rev: shown });
    },
  };
  try {
    const module = await import(new URL(`../skins/${name}/${generation}/${file}`, import.meta.url).href);
    if (!signal.aborted) await module.default(context);
  } catch {
    if (signal.aborted) return;
    controller.abort();
    skinModule.failure = `The skin ${name} could not run ${file}`;
    say('error', skinModule.failure);
    skin.said = true;
  }
}

// Apply NEXT, an event of a skin, unless a newer one has come: its sheets, then its
// render, if it has one, then one task changes the sheets, the root and the document,
// so that no frame shows a sheet on another skin's markup in the normal path.  A
// sheet that fails keeps the old skin, and Emacs holds the new name: choosing again
// tries again.  Past the deadline or on a render's error, the sheet applies on the
// old markup, and the revision shows through update() when it comes.
async function applySkin(next) {
  if (next !== skin.newest) return;
  const line = place();
  const deadline = skinTimeout();
  const { links, failed } = await loadSheets(next, deadline);
  const doc = failed ? null : await renderedDocument(next, deadline);
  const kept = !failed && next === skin.newest;
  for (const link of document.querySelectorAll('link[data-imprimeur-skin]')) {
    if (links.includes(link) !== kept) link.remove();
  }
  if (failed && next === skin.newest) {
    say('error', `The skin ${next.title} could not load ${failed}`);
    skin.said = true;
  }
  if (!kept) return;
  skinModule.controller?.abort();
  skinModule.failure = '';
  setOptions();
  root.dataset.skin = next.name;
  root.dataset.imprimeurGeneration = next.generation;
  if (skin.said) say('notice', '');
  skin.said = false;
  mountModule(next.name, next.generation, next.module);
  if (doc?.rev > shown) {
    show(doc);
    post({ type: 'ready', rev: doc.rev });
  }
  await settle(line, deadline);
}

const events = new EventSource(new URL('events', api));
events.addEventListener('revision', (event) => {
  const { rev, skinGeneration } = JSON.parse(event.data);
  wanted = Math.max(wanted, rev);
  skin.rendered = Math.max(skin.rendered, skinGeneration);
  skin.wake();
  update();
  // Connected again, a page says so, as Emacs takes a page just connected to show
  // nothing yet.
  if (rev === shown) post({ type: 'ready', rev });
});
// Emacs's colours and fonts, custom properties that the skin reads, take
// the place of the last ones; nothing reloads.
events.addEventListener('palette', (event) => {
  const { css, appearance } = JSON.parse(event.data);
  palette.textContent = css;
  document.documentElement.dataset.appearance = appearance;
  draw();
});
// The skin to show: a page connecting again may know it already.
events.addEventListener('skin', (event) => {
  const next = JSON.parse(event.data);
  skin.attributes = next.attributes;
  if (next.generation <= (skin.newest?.generation ?? Number(root.dataset.imprimeurGeneration))) {
    if (!skin.newest) setOptions();
    return;
  }
  skin.newest = next;
  skin.failed = false;
  skin.wake();
  skin.turn = skin.turn.then(() => applySkin(next))
    .catch(() => say('error', `The skin ${next.title} could not be applied`))
    .finally(() => {
      if (skin.newest !== next) return;
      skin.newest = null;
      update();
    });
});
// A change of an option, which a change of skin under way takes with it.  Nothing
// renders; a new measure or face moves the text, so the place comes back.
events.addEventListener('option', (event) => {
  skin.attributes = JSON.parse(event.data).attributes;
  if (skin.newest) return;
  const line = place();
  setOptions();
  settle(line, skinTimeout());
});
// A failed render arrives as a message named error; a lost connection
// fires a plain event of the same name.
events.addEventListener('error', (event) => {
  if (event instanceof MessageEvent) {
    say('error', JSON.parse(event.data).message);
    skin.failed = true;
    skin.wake();
  } else if (events.readyState === EventSource.CLOSED) {
    say('ended', 'The connection to Emacs is lost.');
    document.dispatchEvent(new CustomEvent('imprimeur-ended', { detail: 'lost' }));
  }
});
events.addEventListener('close', () => {
  events.close();
  say('ended', 'The session has ended in Emacs.');
  document.dispatchEvent(new CustomEvent('imprimeur-ended', { detail: 'closed' }));
});

// Emacs's window start, to which the page moves unless it knows that move.
// The line of point, which says where the reader is, goes with it even when the
// window start has not moved.
events.addEventListener('scroll', (event) => {
  const { line, seq, point } = JSON.parse(event.data);
  // Emacs tells each point once, and a page that lets go of a hold must know the last.
  sync.point = point;
  if (holding.held) return;
  if (applies(sync.seq, seq, shown)) {
    sync.seq = seq;
    sync.line = line;
    const target = offsetOfLine(pageMap(measure()), line);
    moveItself(() => scrollToOffset(target));
  }
  minitoc.update();
});

// The source no longer follows: the page goes by its own place.
events.addEventListener('unfollow', () => {
  sync.point = null;
  minitoc.update();
});

// Emacs asks for the block of a line at the top of the page, marked for a moment.
// A line above the first block, or in a format without lines, has only its place.
events.addEventListener('jump', (event) => {
  const { line } = JSON.parse(event.data);
  const map = pageMap(measure());
  const point = map.findLast((candidate) => candidate.block && candidate.line <= line);
  const target = point ? point.offset : offsetOfLine(map, line);
  moveItself(() => scrollToOffset(target));
  if (!point) return;
  point.block.classList.add('imprimeur-flash');
  setTimeout(() => point.block.classList.remove('imprimeur-flash'), flashTime);
});

for (const type of ['wheel', 'keydown', 'touchstart', 'touchmove', 'pointerdown', 'pointermove']) {
  window.addEventListener(type, () => {
    sync.input = performance.now();
  }, { passive: true });
}

// The events of a table or of a block of code that scrolls by itself do not
// reach the page's window object.  A post put off keeps the last place of a burst, which may
// come after the time for an input is over.  Any scroll event ends the wait for
// the page's own move, which the reader may have overtaken: this one may be the
// only one that comes, and the reader may later come back to that very place.
window.addEventListener('scroll', () => {
  const decision = onScroll(sync, measure().offset, performance.now());
  sync.expected = null;
  minitoc.update();
  if (decision === 'post') report();
  else if (typeof decision === 'number' && sync.flush === null) {
    sync.flush = setTimeout(() => {
      sync.flush = null;
      report();
    }, decision);
  }
});

// A selection that holds a soft hyphen copies without it, in text and in rich text,
// so that italics and links still paste.  Any other copy is the engine's own.
document.addEventListener('copy', (event) => {
  const selection = document.getSelection();
  const text = selection.toString();
  if (!text.includes('\u00AD')) return;
  const holder = document.createElement('div');
  for (let index = 0; index < selection.rangeCount; index += 1) {
    holder.append(selection.getRangeAt(index).cloneContents());
  }
  event.clipboardData.setData('text/plain', text.replaceAll('\u00AD', ''));
  event.clipboardData.setData('text/html', holder.innerHTML.replaceAll('\u00AD', ''));
  event.preventDefault();
});

// Whether the first of the last clicks in a row was on a link.
let linkClicked = false;

// Every link followed, by click, middle click or keyboard, in HTML or in
// SVG, goes to Emacs; a fragment only scrolls this page.  A later click in a row
// follows nothing more, as a double-click means no more than one click.
function follow(event) {
  const link = event.target instanceof Element && event.target.closest('a, area');
  if (event.detail === 1) linkClicked = Boolean(link);
  if (!link) return;
  event.preventDefault();
  if (event.detail > 1 || (event.type === 'auxclick' && event.button !== 1)) return;
  const href = link.getAttribute('href') ?? link.getAttributeNS('http://www.w3.org/1999/xlink', 'href');
  if (!href) return;
  if (href.startsWith('#')) moveItself(() => document.getElementById(href.slice(1))?.scrollIntoView());
  else post({ type: 'open', url: new URL(href, document.baseURI).href });
}
document.addEventListener('click', follow, true);
document.addEventListener('auxclick', follow, true);

// Ask for point on the line where EVENT happened or else at the top of the view,
// as nearly as the map knows it.  A page without text has no line to ask for.
function askForLine(event) {
  if (shown === 0) return;
  // In vertical text the blocks of a band stand side by side, at one offset along the
  // page, and only the block under the pointer tells them apart.
  const beside = getComputedStyle(main).writingMode !== 'horizontal-tb'
    && event?.target.closest?.('#imprimeur-main > [data-line]');
  if (beside) {
    post({ type: 'goto', line: Math.max(1, Number(beside.getAttribute('data-line'))), rev: shown });
    return;
  }
  const measured = measure(event);
  post({ type: 'goto', line: lineAt(pageMap(measured), measured.offset, measured.view), rev: shown });
}

// A click already serves a link or the controls of a video, so that a double-click
// on one of them asks nothing; for a link, the first click tells, as it may have
// scrolled something else under the second.  A banner has no line either, nor a minitoc.
document.addEventListener('dblclick', (event) => {
  if (linkClicked || event.target.closest?.('#imprimeur-banner, .imprimeur-minitoc, video, audio, summary')) return;
  askForLine(event);
});

// What is left of a turn of the wheel with Control, and what that turn is: a step of the
// text scale, of all buffers with Alt or Meta too, as Emacs's own wheel has it.  One notch,
// however finely a device sends it, is one step.  The wheel moves nothing else meanwhile.
let wheelRest = 0;
function zoomByWheel(event) {
  if (!event.ctrlKey) return;
  event.preventDefault();
  const { steps, rest } = wheelSteps(wheelRest, event.wheelDeltaY);
  wheelRest = rest;
  for (let left = Math.abs(steps); left > 0; left -= 1) {
    post({ type: 'zoom', larger: steps > 0 ? 1 : 0, global: event.altKey || event.metaKey ? 1 : 0 });
  }
}

// What Emacs asks of a page held in an Emacs window, whose keys never reach it: to
// scroll by DELTA as the reader's wheel does, which Emacs is to hear of, and to ask
// for point on the line at the top of the view, and to take a key, by the one path of
// the keys of a page, answering whether something took it; to take the wheel with
// Control, which a browser keeps as its own zoom; and on each side of a zoom, to keep
// its place and go back to it, with what the zoom scrolls being no scroll of the reader's,
// even right after the wheel or a key.  A page that has stayed where a zoom left it keeps
// that zoom's line, or a run of zooms would creep by the pixel that each one rounds away.
// Nothing in a document runs a script.
globalThis.imprimeur = {
  scrollBy(delta) {
    sync.input = performance.now();
    scrollToOffset(measure().offset + delta);
  },
  postTop() {
    askForLine();
  },
  key(name) {
    const event = new KeyboardEvent('keydown', { key: name, bubbles: true, cancelable: true });
    document.activeElement.dispatchEvent(event);
    return event.defaultPrevented;
  },
  takeWheel() {
    window.addEventListener('wheel', zoomByWheel, { passive: false });
  },
  keepPlace() {
    sync.input = -Infinity;
    const measured = measure();
    if (sync.kept?.offset === measured.offset) return;
    sync.kept = shown === 0 ? null : { line: exactLine(pageMap(measured), measured.offset) };
  },
  backToPlace() {
    if (sync.kept === null) return;
    const target = offsetOfLine(pageMap(measure()), sync.kept.line);
    moveItself(() => scrollToOffset(target));
    sync.kept.offset = measure().offset;
  },
};

// The keys of the minitocs, then those that a skin's module took, whichever way a key
// comes: only Escape can be both, when no minitoc is open for it to close.  The case is
// exact, so that S never reaches a handler of s, and a key with a modifier stays the
// browser's.  A handler that returns false declines the key, and one that throws too.
document.addEventListener('keydown', (event) => {
  if (event.defaultPrevented || event.ctrlKey || event.altKey || event.metaKey) return;
  const handler = skinModule.handlers.get(event.key);
  if (minitoc.key(event.key) || (handler && handler() !== false)) event.preventDefault();
});

// A link or a file dropped on the page would navigate it.
document.addEventListener('dragover', (event) => event.preventDefault());
document.addEventListener('drop', (event) => event.preventDefault());

// The shell names the module of the skin it names, for this once.
mountModule(root.dataset.skin, root.dataset.imprimeurGeneration, JSON.parse(root.dataset.imprimeurModule));
delete root.dataset.imprimeurModule;
