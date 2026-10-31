// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The page's runtime.  It follows the session's event stream, fetches each
// new revision, sanitises it and shows it, and hands every link followed to
// Emacs, which decides where it may lead.  The document's markup reaches
// `main` only through DOMPurify; everything else on the page, banners and
// title included, is set as text.

import DOMPurify from '../vendor/dompurify/purify.es.mjs';

// The session's routes: this module is served at .imprimeur/a/VERSION/js/.
const api = new URL('../../../', import.meta.url);
const main = document.getElementById('imprimeur-main');
const banner = document.getElementById('imprimeur-banner');
const heading = document.getElementById('imprimeur-title');

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

function show(doc) {
  main.replaceChildren(DOMPurify.sanitize(doc.html, policy));
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
