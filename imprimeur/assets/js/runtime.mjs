// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The page's runtime.  It follows the session's event stream, fetches each
// new revision, sanitises it and shows it, and hands every link followed to
// Emacs, which decides where it may lead.  The document's markup reaches
// `main` only through DOMPurify; everything else on the page, banners and
// title included, is set as text.

import DOMPurify from '../vendor/dompurify/purify.es.mjs';
import { reuse } from './blocks.mjs';
import { fnv1a } from './hash.mjs';
import { firstLine, lineMap, parseLine } from './line-map.mjs';
import { applies, lineAt, offsetOfLine, onScroll } from './sync.mjs';

// The session's routes: this module is served at .imprimeur/a/VERSION/js/.
const api = new URL('../../../', import.meta.url);
const main = document.getElementById('imprimeur-main');
const banner = document.getElementById('imprimeur-banner');
const heading = document.getElementById('imprimeur-title');
const palette = document.getElementById('imprimeur-palette');

// What this page knows of scrolling: the last scroll of Emacs that it applied,
// by its number; the source's lines when the revision shown left Emacs; the line
// that Emacs last told it or heard from it; the time of the reader's last input
// and of the last post; where the page last moved itself, until the next scroll
// event; and the timer of a post to come.
const sync = { seq: 0, total: 0, line: null, input: -Infinity, posted: -Infinity, expected: null, flush: null };

// Beyond DOMPurify's defaults: elements that submit, take input, style the
// whole page or hold inert markup; image maps, whose areas are links; and
// attributes that open a new page, save a file or send a request.
const policy = {
  FORBID_TAGS: ['style', 'form', 'input', 'button', 'select', 'textarea', 'template', 'map', 'area'],
  FORBID_ATTR: ['download', 'target', 'ping'],
  RETURN_DOM_FRAGMENT: true,
};

// A diagram's drawing is SVG alone, with Mermaid's own style element, which
// scopes each rule to the drawing's id; a link stays in the page, like any
// other.
const drawingPolicy = {
  USE_PROFILES: { svg: true, svgFilters: true },
  FORBID_ATTR: ['download', 'target', 'ping'],
  RETURN_DOM_FRAGMENT: true,
};

// Mermaid's theme variables, each with the --imp-* colour of the skin that
// gives it: on a pane like a block of code, nodes and notes look like the
// page, and the slices of a pie like the tokens of code.
const themeColours = {
  background: 'code-background',
  primaryColor: 'background',
  secondaryColor: 'background',
  tertiaryColor: 'code-background',
  noteBkgColor: 'background',
  edgeLabelBackground: 'code-background',
  labelBackground: 'code-background',
  primaryTextColor: 'foreground',
  secondaryTextColor: 'foreground',
  tertiaryTextColor: 'foreground',
  noteTextColor: 'foreground',
  textColor: 'foreground',
  primaryBorderColor: 'rule',
  secondaryBorderColor: 'rule',
  tertiaryBorderColor: 'rule',
  noteBorderColor: 'rule',
  lineColor: 'muted',
  pie1: 'keyword',
  pie2: 'string',
  pie3: 'function',
  pie4: 'constant',
  pie5: 'type',
  pie6: 'comment',
};

// The drawings kept, about what typing in a few diagrams needs: an edit
// that goes back, or a palette that comes back, draws nothing.
const drawingsLimit = 64;

// How long a block stays marked once Emacs has asked for it, in milliseconds,
// as long as the animation in base.css.
const flashTime = 800;

// How long the page waits for Mermaid to draw one diagram, in milliseconds.
const drawingDeadline = 20000;

// How long a video has to leave NETWORK_NO_SOURCE once shown, in milliseconds,
// which a browser that can load it does at once.
const videoPatience = 1000;

let shown = 0;
let wanted = 0;
let fetching = false;

// What says where a block comes from in the source, which an edit above it
// changes, and which a block that stays takes from the new text.
const sourceAttributes = ['data-pos', 'data-line'];

// The key of each block in main, a top-level node: its sanitised HTML
// without the attributes above.  A block keeps the key it was shown with,
// whatever happened to it since, until something in it fails to load.
const keys = new WeakMap();

// Each diagram of main, a pre.mermaid, as first seen: its source, its code
// elements, and its key and SVG once drawn.  A block that stays keeps them.
const diagrams = new WeakMap();
let diagramsShown = [];
// By the hash of what they were drawn from, oldest first.
const drawings = new Map();
let drawCount = 0;
let drawQueue = Promise.resolve();
let mermaidLoaded;
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

// The page along its block axis.  This function and scrollToOffset alone know
// that axis to be vertical, so that a vertical skin has only them to replace.
// `offset` is where the view starts, or where EVENT happened if given, `view` how
// long it is and `height` how long the page is; `points` has each block that knows
// its line, as far along as it is.
function measure(event) {
  const start = window.scrollY;
  return {
    offset: start + (event ? event.clientY : 0),
    view: window.innerHeight,
    height: document.documentElement.scrollHeight,
    get points() {
      return [...main.querySelectorAll(':scope > [data-line]')].map((block) => ({
        line: Number(block.getAttribute('data-line')),
        offset: block.getBoundingClientRect().top + start,
        block,
      }));
    },
  };
}

function scrollToOffset(offset) {
  window.scrollTo({ top: offset, behavior: 'instant' });
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

// Tell Emacs the line at the top of the view, if it does not know it.
function report() {
  const measured = measure();
  const line = lineAt(pageMap(measured), measured.offset, measured.view);
  sync.posted = performance.now();
  if (line === sync.line) return;
  sync.line = line;
  post({ type: 'scroll', line, seq: sync.seq });
}

// Show the diagram of PRE: its last drawing or else its code, and beneath
// them the text MESSAGE, if any.
function showDiagram(pre, message) {
  const { svg, code } = diagrams.get(pre);
  pre.replaceChildren(...(svg ? [svg] : code));
  if (message) {
    const note = pre.appendChild(document.createElement('div'));
    note.className = 'imprimeur-diagram-error';
    note.textContent = message;
  }
}

// Return the element of a diagram's SVG, from TEXT, which Mermaid made of
// what the document holds, with a note for the reader: Mermaid keeps some
// labels in a foreignObject, which holds HTML and so goes, leaving a drawing
// that only looks whole.  TEXT is untrusted, and is parsed in a document that
// loads nothing.  Throw when nothing of it is SVG.
function sanitiseDrawing(text) {
  const svg = DOMPurify.sanitize(text, drawingPolicy).querySelector('svg');
  if (!svg) throw new Error('This diagram has no drawing that the page can show.');
  const lost = DOMPurify.removed.some(({ element }) => element?.localName === 'foreignObject');
  return { svg, note: lost ? 'Some labels of this diagram cannot be shown: the page draws SVG text alone.' : '' };
}

// Give each diagram of main the drawing of the page's current look.  One
// pass runs at a time, in a queue that each call joins; a diagram's failure
// is its own, and a pass's shows beneath every diagram.  Mermaid is loaded at
// the first diagram only, and again at the next call if it could not be
// fetched.  A script that ran and set no global is not run again: an asset's
// address gives the same file for as long as the page lives.
function draw() {
  if (!document.documentElement.hasAttribute('data-mermaid')) return;
  // An edit makes a new node of a diagram it changes.  When as many diagrams
  // went as came, each new one shows the drawing of the one gone at its place
  // in their order, until it has its own, or for good if that fails; otherwise
  // each starts from its code.  So one deleted and another added elsewhere pair.
  const gone = diagramsShown.filter((pre) => !pre.isConnected).map((pre) => diagrams.get(pre).svg);
  diagramsShown = [...main.querySelectorAll('pre.mermaid')];
  const fresh = diagramsShown.filter((pre) => !diagrams.has(pre));
  const previous = gone.length === fresh.length ? gone : [];
  fresh.forEach((pre, index) => {
    diagrams.set(pre, { source: pre.textContent, code: [...pre.childNodes], svg: previous[index] });
    showDiagram(pre);
  });
  drawQueue = drawQueue.then(async () => {
    if (diagramsShown.length === 0) return;
    const mermaid = await (mermaidLoaded ??= new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = new URL('../mermaid.js', import.meta.url);
      script.onload = () => {
        if (globalThis.mermaid) resolve(globalThis.mermaid);
        else {
          script.remove();
          reject(new Error('The Mermaid script sets no global mermaid.'));
        }
      };
      script.onerror = () => {
        script.remove();
        mermaidLoaded = undefined;
        reject(new Error('The Mermaid script did not load.'));
      };
      document.head.append(script);
    }));
    // Mermaid's theme takes colours alone, so each --imp-* is resolved here.
    const probe = document.body.appendChild(document.createElement('span'));
    const look = {
      fontFamily: getComputedStyle(main).fontFamily,
      themeVariables: {
        darkMode: document.documentElement.dataset.appearance === 'dark',
        dropShadow: 'none',
        ...Object.fromEntries(Object.entries(themeColours).map(([name, token]) => {
          probe.style.color = `var(--imp-${token})`;
          return [name, getComputedStyle(probe).color];
        })),
      },
    };
    probe.remove();
    mermaid.initialize({
      ...look,
      startOnLoad: false,
      securityLevel: 'strict',
      suppressErrorRendering: true,
      theme: 'base',
      htmlLabels: false,
      flowchart: { htmlLabels: false },
      // Mermaid's sanitiser is what keeps a meta refresh out of the live page,
      // where it puts maths while drawing, so no document may loosen it.
      secure: [...mermaid.mermaidAPI.defaultConfig.secure, 'theme', 'themeVariables', 'themeCSS',
               'fontFamily', 'htmlLabels', 'flowchart', 'darkMode', 'dompurifyConfig'],
    });
    for (const pre of diagramsShown) {
      const diagram = diagrams.get(pre);
      const key = fnv1a(JSON.stringify([diagram.source, look]));
      if (diagram.key === key) continue;
      diagram.key = key;
      try {
        if (!drawings.has(key)) {
          drawCount += 1;
          const { svg } = await Promise.race([
            mermaid.render(`imprimeur-diagram-${drawCount}`, diagram.source),
            new Promise((resolve, reject) => {
              setTimeout(reject, drawingDeadline, new Error('This diagram took too long to draw.'));
            }),
          ]);
          drawings.set(key, sanitiseDrawing(svg));
          if (drawings.size > drawingsLimit) drawings.delete(drawings.keys().next().value);
        }
        const drawing = drawings.get(key);
        diagram.svg = drawing.svg.cloneNode(true);
        showDiagram(pre, drawing.note);
      } catch (error) {
        showDiagram(pre, error.message);
      }
    }
  }).catch((error) => {
    console.error(error);
    for (const pre of diagramsShown) showDiagram(pre, error.message);
  });
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
  document.documentElement.dataset.format = doc.format;
  document.documentElement.dataset.revision = doc.rev;
  if (doc.error) say('error', doc.error);
  else say('notice', doc.warnings);
  shown = doc.rev;
  sync.total = doc.total;
  // A line that the page knows means another place in this text.
  sync.line = null;
  draw();
  clearTimeout(videoCheck);
  videoCheck = setTimeout(offerStuckVideos, videoPatience);
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

// Fetch revisions until the latest announced is shown; revisions announced
// meanwhile are caught by the same loop, so one fetch runs at a time.
async function update() {
  if (fetching) return;
  fetching = true;
  try {
    while (shown < wanted) {
      const doc = await (await fetch(new URL('doc', api), { cache: 'no-store' })).json();
      if (doc.rev <= shown) break;
      show(doc);
      await post({ type: 'ready', rev: doc.rev });
    }
  } finally {
    fetching = false;
  }
}

const events = new EventSource(new URL('events', api));
events.addEventListener('revision', (event) => {
  const { rev } = JSON.parse(event.data);
  wanted = Math.max(wanted, rev);
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
// A failed render arrives as a message named error; a lost connection
// fires a plain event of the same name.
events.addEventListener('error', (event) => {
  if (event instanceof MessageEvent) say('error', JSON.parse(event.data).message);
  else if (events.readyState === EventSource.CLOSED) say('ended', 'The connection to Emacs is lost.');
});
events.addEventListener('close', () => {
  events.close();
  say('ended', 'The session has ended in Emacs.');
});

// Emacs's window start, to which the page moves unless it knows that move.
// The line of point and the source's lines as of now go with it, for later plans.
events.addEventListener('scroll', (event) => {
  const { line, seq } = JSON.parse(event.data);
  if (!applies(sync.seq, seq, shown)) return;
  sync.seq = seq;
  sync.line = line;
  const target = offsetOfLine(pageMap(measure()), line);
  moveItself(() => scrollToOffset(target));
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
  if (decision === 'post') report();
  else if (typeof decision === 'number' && sync.flush === null) {
    sync.flush = setTimeout(() => {
      sync.flush = null;
      report();
    }, decision);
  }
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

// A double-click asks for point on the line there, as nearly as the map knows it.
// A click already serves a link or the controls of a video, so that a double-click
// on one of them asks nothing; for a link, the first click tells, as it may have
// scrolled something else under the second.  A page without text, or a banner, has
// no line to ask for.
document.addEventListener('dblclick', (event) => {
  if (shown === 0 || linkClicked
      || event.target.closest?.('#imprimeur-banner, video, audio, summary')) return;
  const measured = measure(event);
  post({ type: 'goto', line: lineAt(pageMap(measured), measured.offset, measured.view) });
});

// A link or a file dropped on the page would navigate it.
document.addEventListener('dragover', (event) => event.preventDefault());
document.addEventListener('drop', (event) => event.preventDefault());
