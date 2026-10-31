# How imprimeur works

imprimeur keeps a typeset page in step with a buffer by sending the whole
unsaved text to pandoc a moment after each change, and by serving the
result to a browser page from a small HTTP server inside Emacs, on
127.0.0.1 only. The page fetches each new version, sanitises it and shows
it; it never navigates by itself, and Emacs decides where every link may
lead. This page explains the pieces, follows one edit to the page, and
lists the defences against a hostile document.

## The pieces

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/architecture-dark.svg">
  <img alt="How imprimeur shows a buffer." src="images/architecture.svg">
</picture>

- **The session** belongs to the buffer: `imprimeur-mode` starts it and
  ending the mode, killing the buffer or leaving Emacs ends it. It survives
  a change of major mode when the new mode has a pandoc reader, such as
  `org-mode` after `org-mode`, and ends otherwise.
- **pandoc** reads the text on its standard input with the reader of
  `imprimeur-reader-alist`, through the Lua filter `imprimeur.lua`, and
  writes an HTML fragment followed by the document's title and language.
- **The server** is one per Emacs, started by the first session and
  stopped by the last. Each session has a random 128-bit token, the first
  segment of every path it serves: the page, its assets, the document as
  JSON, an event stream, and the pictures and videos under the document's
  root (its git repository, or else its directory).
- **The page** is the same for every session: a shell, a script and two
  stylesheets. It holds no document text until it fetches it.
- **The browser window** belongs to the session too. Its profile is
  created for it and deleted when it closes.

## From a keystroke to the page

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/edit-to-page-dark.svg">
  <img alt="From a keystroke to the page." src="images/edit-to-page.svg">
</picture>

A render starts when 0.3 s have passed since the last change
(`imprimeur-render-delay`), or 2 s since the first change not yet rendered
(`imprimeur-render-max-delay`), so that continuous typing still shows. One
render runs at a time per session: an edit made meanwhile waits for it to
end. Nothing renders while no page is connected, and a change of text
properties alone, such as fontification, renders nothing. A check every
second notices edits that ran no change hook, as some made through an
indirect buffer do.

pandoc gets 20 s and 64 MiB of output. When it fails, the page keeps the
last good version and shows pandoc's message above it, as text; the next
good render clears it.

## The defences

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="images/defences-dark.svg">
  <img alt="What stands between a hostile document and you." src="images/defences.svg">
</picture>

A document is untrusted unless Emacs's `trusted-content` accepts it. Three
kinds of attacker are in view: a hostile document, a web page that tries
to reach the server through DNS rebinding, and another user of the same
machine. Each layer stops what the one above let through:

- **pandoc's sandbox** stops a document from reading other files
  (`#+INCLUDE`) or the network. The Lua filter does no input or output,
  which `scripts/check-public` enforces, since the sandbox does not cover
  filters.
- **The filter** turns each remote image into a link naming its host, so
  that a tracking pixel fetches nothing, unless the document is trusted
  and `imprimeur-remote-images` allows it.
- **DOMPurify** removes scripts, event handlers, `javascript:` addresses,
  forms and inputs, styles, frames, image maps, the attributes `target`,
  `ping` and `download`, and ids that would shadow the page's own
  properties.
- **The Content Security Policy** of every response allows scripts and
  connections to the page's own origin only, pictures from it and from
  `data:` and `blob:`, and no frame, plugin, form or base address.
- **Links** never navigate the page: each click or middle click is
  cancelled and posted to Emacs, which opens web addresses with
  `browse-url`, documents and media under the root with
  `find-file-other-window`, and drops the rest.
- **The server** answers on 127.0.0.1 only, under the token, and requires
  a `Host` of `127.0.0.1` or `localhost` with its port, our `Origin` and
  JSON on a POST. It limits requests to 16 KiB of headers, 64 KiB of body,
  10 s to arrive and 32 connections. A file is served only when its true
  name, symbolic links resolved, lies under the root and its extension is
  a picture's, a video's or a sound's.
- **The window** starts on a file, readable by you only, inside its own
  profile, which leads to the page: the token appears in no process's
  command line, where any user could read it.

The tests check each layer: hostile Org and Markdown documents in a
headless Chromium, raw requests to the server, and the command lines of
every process while the window is open.

## Why a page in a browser

A browser renders what Emacs cannot: kerning and OpenType features,
hyphenation, justification, vertical text, video, MathML and SVG
diagrams. Serving the page over HTTP lets the same page run in Chromium
now and inside Emacs, in an xwidget, later, with the same code and the
same tests: everything the page tells Emacs is an HTTP POST, and
everything Emacs tells the page is an event on one stream.
