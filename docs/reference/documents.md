# What a document may hold

## Formats

The default `imprimeur-reader-alist`, first match first:

| Matches | pandoc's reader |
|---|---|
| `org-mode` | `org` |
| `markdown-mode`, and `gfm-mode` and `markdown-ts-mode` with it | `gfm+sourcepos` |
| `rst-mode` | `rst` |
| `mediawiki-mode` | `mediawiki` |
| `textile-mode` | `textile` |
| `.creole` | `creole` |
| `.pod` | `pod` |
| `.ipynb` | `ipynb` |
| `.csv` | `csv` |
| `.tsv` | `tsv` |

A Markdown file without `markdown-mode` takes an entry of its own, such as
`("\\.md\\'" . "gfm+sourcepos")`.

## Pictures, videos and sounds

They show when they lie under the document's root: its git repository, or else its directory.
Pictures, videos and sounds are served by their extension; a video can seek. Without a range
request, a file of 32 MiB or more is refused.

A remote image loads as `imprimeur-remote-images` says. Otherwise it is a link that names its
host, and nothing is fetched.

A video that cannot play gets a link, "Open externally". In Chromium a video plays and seeks.
In an Emacs window, WebKit plays through GStreamer, whose plugins must be in the environment
of that Emacs. [How it works](../explanation/how-it-works.md#videos) says how far that has gone.

## Diagrams

A Mermaid block, `#+begin_src mermaid` or a fence named `mermaid`, is drawn when the page has
a Mermaid script: the copy beside the program `mmdc`, or the file that
`imprimeur-mermaid-script` names. Without one, it stays as code. A source that does not parse
keeps its last drawing, with the message beneath. A drawing that takes more than 20 s shows
"This diagram took too long to draw." Whatever Mermaid puts in a `foreignObject` is lost, and
the page says so beneath the drawing.

## Tables

A table wider than the page scrolls by itself. An address or a piece of code in a cell breaks
anywhere; plain words do not. Cells are aligned to the top, and a header starts where its text
does unless the document aligns its column.

## Maths

Maths reaches the page as MathML:

| Source | In Org | In Markdown |
|---|---|---|
| `$x$`, `$$x$$` | maths | maths |
| `\(x\)`, `\[x\]` | maths | text |
| `` $`x`$ `` | | maths |
| a fence named `math` | `#+begin_src math`: maths | maths |
| `\begin{equation}`, `\begin{align}` | maths | text |

In Markdown, this is pandoc's reading of GitHub's dialect. A `\newcommand` on its own stays as
raw TeX in Org, with a warning from pandoc; a `#+begin_export latex` block is left out; and
`#+begin_math` is only a block around text. Tall brackets stretch only in a font made for
maths, which `base.css` names: Latin Modern Math, STIX Two Math, Libertinus Math, DejaVu Math
TeX Gyre.

## What a skin reads

[Briefing](../../imprimeur-skin-briefing/README.md#writing-for-it),
[Écrivain](../../imprimeur-skin-ecrivain/README.md#writing-for-it) and
[Tianlu](../../imprimeur-skin-tianlu/README.md#writing-for-it) each have conventions of their
own. A document's language decides what XIX, XVIII and XVII hyphenate: French and English,
where none counts as English; any other stays whole and ragged. No document chooses a skin or
an option.
