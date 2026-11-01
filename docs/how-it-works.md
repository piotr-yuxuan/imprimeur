# How imprimeur works

imprimeur keeps a typeset page in step with a buffer by sending the whole
unsaved text to pandoc a moment after each change, and by serving the
result to a browser page from a small HTTP server inside Emacs, on
127.0.0.1 only. The page fetches each new version, sanitises it and
replaces only the blocks that changed; it never navigates by itself, and
Emacs decides where every link may lead. This page explains the pieces,
follows one edit to the page, describes the colours, the diagrams and the
videos, and lists the defences against a hostile document.

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
  writes the document's title and language, then an HTML fragment.
- **The server** is one per Emacs, started by the first session and
  stopped by the last. Each session has a random 128-bit token, the first
  segment of every path it serves: the page, its assets, the document as
  JSON, an event stream, and the pictures and videos under the document's
  root (its git repository, or else its directory).
- **The page** is the same for every session: a shell, its scripts and two
  stylesheets, from a fixed list of assets. It holds no document text until
  it fetches it.
- **The browser's desktop window**, which your desktop manages as it does
  an Emacs frame, belongs to the session too. Its profile is created for it
  and deleted when it closes.

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

A change of Emacs theme runs no render: it takes the same event stream to
the page, as [the colours](#the-colours) explain.

## The block diff

An edit replaces only the blocks it touched, so that a video plays on, a
diagram is not drawn again and details the reader opened stay open. A block
is a top-level node of the sanitised fragment. Its key is its sanitised HTML
without the `data-pos` attributes, the source positions that the Markdown
reader adds, which an edit above it changes.

`imprimeur/assets/js/blocks.mjs` holds a pure function from the keys of the blocks
shown and of the new ones to, for each new block, the old block it reuses or
none: the common prefix, then the common suffix of what follows, then a
longest common subsequence of the middle. White space between blocks takes
no part in that subsequence: it costs nothing to make anew, and could
outvote a video that could stay. A middle of more than 2^20 pairs of blocks
reuses nothing.

The page keeps the key that each node was shown with, whatever has happened
to the node since, such as a diagram drawn in it. A reused node stays where
it is and takes the new block's `data-pos` attributes; new blocks go between
the nodes that stay. A block gives up its key when something in it fails to
load, so that the next edit makes it anew and the load is tried again: the
file may exist by then. A video in the same block as a broken picture
therefore restarts at each edit. A failed track, or a failed source with
another after it, costs nothing, as the video plays on.

Two limits remain. pandoc numbers code blocks (`id="doc-cb1"`) and footnotes
through the whole document, so adding one changes the keys of those after
it, and they are made anew. And the reader's place on the page is left to
the browser's scroll anchoring, which no test covers.

## The colours

The page takes its colours and fonts from the Emacs faces, read by
`imprimeur-palette.el` on a graphic Emacs frame showing the source buffer,
else on the selected Emacs frame, with their inheritance and inverse video.
Each becomes a CSS custom property on `:root`, from the first face of its
list that exists and gives a value:

| Property | Faces |
|---|---|
| `--emacs-bg`, `--emacs-fg` | `default` |
| `--emacs-muted` | `shadow` |
| `--emacs-link` | `org-link`, `markdown-link-face`, `link`, `button` |
| `--emacs-h1` to `--emacs-h6` | `org-level-N`, `markdown-header-face-N`, `outline-N` |
| `--emacs-region` | `region` |
| `--emacs-code-bg` | `org-block`, `markdown-code-face` |
| `--emacs-kw`, `-str`, `-com`, `-fn`, `-var`, `-type`, `-const`, `-builtin`, `-pre`, `-doc`, `-warn` | the keyword, string, comment, function name, variable name, type, constant, builtin, preprocessor, doc and warning `font-lock-*` faces, each also with `-weight` and `-style` |
| `--emacs-ansi-0` to `--emacs-ansi-7` | `ansi-color-black` to `ansi-color-white` |
| `--emacs-font-mono`, `--emacs-font-variable` | the family of `default`, of `variable-pitch` |

That order is the one of an Org buffer, whose major mode derives from
`org-mode`. In any other buffer, or a dead one, the faces named `org-*` come
last and the others keep their order: a Markdown buffer reads
`markdown-header-face-N`, `outline-N`, then `org-level-N`, so a page takes the
faces of its own mode, and a Markdown file keeps its colours when an Org file
happens to load Org. A change of major mode that keeps the session sends the
palette if that changes it.

A colour reaches the CSS only as `#rrggbb`, 16-bit channels being scaled by
rounding, and a font family only when it holds letters, digits, spaces,
dots, hyphens and underscores, and then quoted. A property whose face gives
nothing is left out, so that the skin's own value applies. Minitel reads the
colours of the page, its links, headings and code panes, of six tokens and
of `--emacs-warn`, and `--emacs-font-mono`; the rest wait for other skins.

The appearance, `light` or `dark`, is the Emacs frame's background mode
unless `imprimeur-appearance` forces one. It sets `data-appearance` on
`html`, which gives the page its colour scheme, and with it which of
Minitel's own colours stand in where a face gives none; before the first
palette, the reader's `prefers-color-scheme` does. Forcing an appearance
against the theme leaves Emacs's colours in place, so that code in Emacs's
colours may then be hard to read on a pane in Minitel's own, where the theme
gives panes no colour.

A switch of theme, such as auto-dark makes, disables and enables themes in a
row, each running a hook. The hooks, `enable-theme-functions` and
`disable-theme-functions`, only arm a timer of 50 ms, which reads the faces
once. A session remembers the palette its pages have, and sends the event
`palette` with `{css, appearance}` only when it differs; a page that
connects gets it first, before any revision. The page puts the CSS in
`<style id="imprimeur-palette">` with `textContent`, sets `data-appearance`
and gives its diagrams their new look. Nothing reloads. The hooks are added
with the first session and removed with the last, so that loading the
package adds none. A face changed without a theme, or a new
`imprimeur-appearance`, shows at the next switch or after
`M-x imprimeur-refresh-palette`.

## Mermaid diagrams

The filter leaves a Mermaid block its class, so that it reaches the page as
`pre.mermaid`. The page has a script to draw it with when
`imprimeur-mermaid-script` names one or, when that is nil, when the true name
of the program `mmdc` has the tree that nixpkgs and npm install beside it,
which holds `mermaid.min.js`. imprimeur never runs `mmdc`, and never fetches
a script from a CDN. A script that is found is served as the versioned asset
`mermaid.js`, and the shell says so with `data-mermaid`; without one a
diagram stays as code. The page loads the script with a `<script>` element at
the first `pre.mermaid` only, once for all the diagrams, and tries again at
the next edit when it could not be fetched.

Each diagram has a key, the FNV-1a hash (`imprimeur/assets/js/hash.mjs`) of its source
and of the page's look, its font family and the colours that it resolves from
the skin. A diagram whose key has not changed is not drawn again, and the page
keeps the last 64 drawings by key, so that an edit that goes back, or a
palette that comes back, draws nothing. A palette that changes that look
gives every diagram a new key, and so a new drawing, in place. One pass of
drawing runs at a time.

A source that does not parse keeps the previous drawing, with the message as
text beneath it; without a previous one, the code stays. An edit makes a new
node of a diagram it changes, so the page pairs them: when as many diagrams
went as came in one pass, each new one shows the drawing of the one gone at its
place in their order, until it has its own. An edit that changes one source, or
breaks several, so keeps their drawings. When the numbers differ, each new
diagram starts from its code. One limit remains: as many going as coming in
different places pair by order all the same, so a diagram deleted here and a
broken one added there shows the deleted drawing above its message.

A drawing keeps to SVG, as [the defences](#the-defences) require, so whatever
Mermaid puts in a `foreignObject` is lost, even with HTML labels off: a
journey's section titles, maths, the text of an event model or of a Venn set.
The page says so beneath such a drawing, unless a parse error has kept it and
shows its message instead.

## Videos

Pictures, videos and sounds under the root are served as they are. A media
answer carries `Accept-Ranges: bytes`, and a browser then asks for a video by
parts, which is what lets it seek. `imprimeur-server-parse-range` reads one
range: `bytes=A-B`, `bytes=A-` or the last N bytes, `bytes=-N`. The answer is
206 with `Content-Range`, holds at most 256 KiB, and only those bytes are read
from the disk. A reversed, multiple or unsatisfiable range gets 416 with
`Content-Range: bytes */SIZE`, and a unit other than bytes is ignored, as RFC
9110 asks; so is a Range on anything but a GET. Without a range, a file of
32 MiB or more is refused.

A `<video>` that cannot play gets a link right after it, "Open externally", to
the address that the document gave it. Like any link, it goes to Emacs, which
gives a web address to `browse-url` and visits a file when it lies under the
root and is a document, a media file that the server serves, or a video in a
container that the server does not serve, such as `mkv` or `avi`
(`imprimeur-server-unserved-video-extensions`). A media package such as
ready-player can then play it. A link that leads nowhere, to a missing file or
a container outside those lists, visits nothing, and Emacs says so in the echo
area.

The link goes with its block: the next edit makes the block anew, as for any
failed load, and the link is absent until the new video fails too. Where the
link wraps below the video, the text under it moves by a line at such an edit.
A video that names no address gets no link, nor one whose address DOMPurify
would take from a document's own link; a sound or a picture never gets one.

## Tables and maths

A table wider than the page scrolls by itself, and the page does not move
sideways. An address or a piece of code in a cell breaks anywhere, having no
spaces to wrap at; plain words do not, so a table of many long words scrolls.
Cells are aligned to the top, and a header starts where its text does unless
the document aligns its column.

Maths reaches the page as MathML, which the browser sets itself:

| Source | In Org | In Markdown |
|---|---|---|
| `$x$`, `$$x$$` | maths | maths |
| `\(x\)`, `\[x\]` | maths | text |
| `` $`x`$ `` | | maths |
| a fence named `math` | a block named `math`: maths | maths |
| `\begin{equation}`, `\begin{align}` | maths | text |

In Markdown, this is pandoc's reading of GitHub's dialect. A `\newcommand` on
its own stays as raw TeX in Org, with a warning from pandoc, and a
`#+begin_export latex` block is left out. Tall brackets only stretch in a font
made for maths, which `base.css` names: Latin Modern Math, STIX Two Math,
Libertinus Math, DejaVu Math TeX Gyre. With none of them installed, the browser
chooses, and a bracket may stay one line tall.

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
- **Mermaid** gets a diagram's source, which is untrusted too, under the
  page's settings: `securityLevel: 'strict'`, `theme: 'base'`, no HTML
  labels, and a `secure` list, Mermaid's own plus `theme`, `themeVariables`,
  `themeCSS`, `fontFamily`, `htmlLabels`, `flowchart`, `darkMode` and
  `dompurifyConfig`, so that neither a `%%{init}%%` directive nor front
  matter can change them. While it draws, Mermaid puts some of the document's
  HTML, such as maths, in the live page, where only its own sanitiser stops
  a meta refresh; hence `dompurifyConfig` in that list. What Mermaid returns
  goes through DOMPurify again, with its SVG profile, in a document that
  loads nothing. That drops all HTML, and keeps Mermaid's own `<style>`,
  which the policy below stops from loading anything from elsewhere.
- **The Content Security Policy** of every response allows scripts and
  connections to the page's own origin only, pictures from it and from
  `data:` and `blob:`, and no frame, plugin, form or base address.
- **Links** never navigate the page: each click or middle click is
  cancelled and posted to Emacs, which opens web addresses with
  `browse-url`, documents and media under the root with
  `find-file-other-window`, and drops the rest, saying so.
- **The server** answers on 127.0.0.1 only, under the token, and requires
  a `Host` of `127.0.0.1` or `localhost` with its port, our `Origin` and
  JSON on a POST. It limits requests to 16 KiB of headers, 64 KiB of body,
  10 s to arrive and 32 connections. An asset is served only from a fixed
  list. Any other file is served only when its true name, symbolic links
  resolved, lies under the root and its extension is a picture's, a video's
  or a sound's.
- **The desktop window** starts on a file, readable by you only, inside its
  own profile, which leads to the page: the token appears in no process's
  command line, where any user could read it.

The tests check each layer: hostile Org and Markdown documents and hostile
diagrams in a headless Chromium, raw requests to the server, and the command
lines of every process while the desktop window is open.

## Why a page in a browser

A browser renders what Emacs cannot: kerning and OpenType features,
hyphenation, justification, vertical text, video, MathML and SVG
diagrams. Serving the page over HTTP lets the same page run in Chromium
now and inside Emacs, in an xwidget, later, with the same code and the
same tests: everything the page tells Emacs is an HTTP POST, and Emacs
announces each new version, palette or failure on one event stream, after
which the page fetches what it needs.

Today the viewer is Chromium's own desktop window, beside the Emacs frame.
The aim is one Emacs frame holding two Emacs windows, panes of that frame:
one showing the source buffer and the other the page.
