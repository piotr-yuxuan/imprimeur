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

// The session's routes: this module is served at .imprimeur/a/VERSION/js/.
const api = new URL('../../../', import.meta.url);
const main = document.getElementById('imprimeur-main');
const banner = document.getElementById('imprimeur-banner');
const heading = document.getElementById('imprimeur-title');
const palette = document.getElementById('imprimeur-palette');

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

// How long the page waits for Mermaid to draw one diagram, in milliseconds.
const drawingDeadline = 20000;

let shown = 0;
let wanted = 0;
let fetching = false;

// The key of each block in main, a top-level node: its sanitised HTML
// without the data-pos attributes, which an edit above it changes.  A
// block keeps the key it was shown with, whatever happened to it since,
// until something in it fails to load.
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

// Only the blocks that an edit touched are replaced.  DOMPurify builds the
// fragment in a document of its own, which loads nothing, so a block that
// is not shown fetches no picture and no video.
function show(doc) {
  const fragment = DOMPurify.sanitize(doc.html, policy);
  const blocks = [...fragment.childNodes];
  const bare = fragment.cloneNode(true);
  for (const element of bare.querySelectorAll('[data-pos]')) element.removeAttribute('data-pos');
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
    // Its elements, in document order, take the new block's data-pos.  What a
    // diagram holds is its drawing's on the page and its code's here; and
    // Mermaid removes what bears the id it draws under, so a block may have
    // lost elements since it was shown.
    const outside = '*:not(pre.mermaid *)';
    const sources = [block, ...block.querySelectorAll(outside)];
    const targets = [node, ...node.querySelectorAll(outside)];
    for (let at = 0; at < Math.min(sources.length, targets.length); at += 1) {
      const pos = sources[at].getAttribute('data-pos');
      if (pos === null) targets[at].removeAttribute('data-pos');
      else targets[at].setAttribute('data-pos', pos);
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
  draw();
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
  const address = target.getAttribute('src') || target.currentSrc;
  if (!address || !target.matches('video, video > source')
      || !DOMPurify.isValidAttribute('a', 'href', address)) return;
  const link = document.createElement('a');
  link.href = address;
  link.textContent = 'Open externally';
  target.closest('video').after(link);
}, true);

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
  wanted = Math.max(wanted, JSON.parse(event.data).rev);
  update();
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

// Every link followed, by click, middle click or keyboard, in HTML or in
// SVG, goes to Emacs; a fragment only scrolls this page.
function follow(event) {
  const link = event.target instanceof Element && event.target.closest('a, area');
  if (!link) return;
  event.preventDefault();
  if (event.type === 'auxclick' && event.button !== 1) return;
  const href = link.getAttribute('href') ?? link.getAttributeNS('http://www.w3.org/1999/xlink', 'href');
  if (!href) return;
  if (href.startsWith('#')) document.getElementById(href.slice(1))?.scrollIntoView();
  else post({ type: 'open', url: new URL(href, document.baseURI).href });
}
document.addEventListener('click', follow, true);
document.addEventListener('auxclick', follow, true);

// A link or a file dropped on the page would navigate it.
document.addEventListener('dragover', (event) => event.preventDefault());
document.addEventListener('drop', (event) => event.preventDefault());
