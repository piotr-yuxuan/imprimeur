// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The page's runtime.  It follows the session's event stream, fetches each
// new revision, sanitises it and shows it, and hands every link followed to
// Emacs, which decides where it may lead.  The document's markup reaches
// `main` only through DOMPurify; everything else on the page, banners and
// title included, is set as text.

import DOMPurify from '../vendor/dompurify/purify.es.mjs';
import { reuse } from './blocks.mjs';

// The session's routes: this module is served at .imprimeur/a/VERSION/js/.
const api = new URL('../../../', import.meta.url);
const main = document.getElementById('imprimeur-main');
const banner = document.getElementById('imprimeur-banner');
const heading = document.getElementById('imprimeur-title');
const palette = document.getElementById('imprimeur-palette');

// Beyond DOMPurify's defaults: elements that submit, take input, style the
// whole page or hold inert markup; image maps, whose areas are links; and
// attributes that open a window, save a file or send a request.
const policy = {
  FORBID_TAGS: ['style', 'form', 'input', 'button', 'select', 'textarea', 'template', 'map', 'area'],
  FORBID_ATTR: ['download', 'target', 'ping'],
  RETURN_DOM_FRAGMENT: true,
};

let shown = 0;
let wanted = 0;
let fetching = false;

// The key of each block in main, a top-level node: its sanitised HTML
// without the data-pos attributes, which an edit above it changes.  A
// block keeps the key it was shown with, whatever happened to it since.
const keys = new WeakMap();

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
    // Its elements, in document order, take the new block's data-pos; one
    // transformed since it was shown may hold more or fewer of them.
    const sources = [block, ...block.querySelectorAll('*')];
    const targets = [node, ...node.querySelectorAll('*')];
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
}

// What fails to load gives up its block's key, so that the next edit makes
// the block anew and the load is tried again: the file may exist by then.
// A video plays on after a failed track, or a failed source with another
// after it.  Such an error does not bubble, so it is caught on its way down.
main.addEventListener('error', ({ target }) => {
  if (target.matches('track, source:has(~ source)')) return;
  let block = target;
  while (block.parentNode !== main) block = block.parentNode;
  keys.delete(block);
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
