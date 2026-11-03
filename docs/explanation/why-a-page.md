# Why a page rather than the buffer

Emacs already shows Org and Markdown with some of their look. imprimeur shows a page instead
because of what a browser's engine sets and Emacs's redisplay does not: kerning and OpenType
features, hyphenation, justification, vertical text, video, MathML and SVG diagrams. The skins
rest on these. XVII's long s is a font feature, XIX's lettrine and Tianlu's columns are
stylesheets, and a diagram is SVG.

## One page, two viewers

Serving the page over HTTP lets the same page run in Chromium and in WebKit inside Emacs, with
the same code. Everything the page tells Emacs is an HTTP POST, and Emacs announces each new
version, palette, scroll or failure on one event stream, after which the page fetches what it
needs. So the page does not know where it is shown, and the two viewers cannot drift.

The aim is one Emacs frame holding two Emacs windows, one showing the source buffer and the
other the page, as you then stay in Emacs. Chromium's desktop window stays as the fallback, where
no xwidget can run or a video must play.

## What it gives up

**An experimental part of Emacs.** Xwidgets stay experimental: Emacs's own `etc/NEWS.29` says so of
a video in an xwidget, known to crash Emacs on some systems, and a crash takes unsaved text with
it. That is why [the README](../../README.md#try-xwidgets-first) asks you to try them in a separate
Emacs first, and why `imprimeur-target` can keep them out.

**A check by machine in one engine.** Nothing in `make check` opens a desktop window, so its tests
drive headless Chromium alone, and WebKit has only `make smoke-xwidget`.

**A second copy of your text.** The page does not edit. Editing stays in the buffer, and what the
page offers is to take you back to it, at the right line.

**A boundary to defend.** A web page runs what it is given, and a document may come from anyone,
so a page brings [defences](how-it-works.md#the-defences) that a buffer does not need.

## What it does not replace

The buffer stays the document. For where you are in a long buffer without any of this, there is
[sommaire](how-it-works.md#sommaire), which works in the buffer itself and needs no browser.
