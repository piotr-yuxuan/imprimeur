# Troubleshoot by symptom

Find what you see, then do what the row says.

| What you see | Why | What to do |
|---|---|---|
| "No pandoc program pandoc" | pandoc is not on Emacs's path | Install pandoc 3, or set `imprimeur-pandoc-program`. |
| "No browser program chromium" | No Chromium, where a page needs a desktop window | Install it, or set `imprimeur-browser-program`. |
| "No pandoc reader for this buffer" | Neither the major mode nor the file name matches, as for a `.md` file without `markdown-mode` | Install `markdown-mode`, or add an entry to `imprimeur-reader-alist`. |
| "This Emacs frame or build has no xwidgets" | `imprimeur-target` is `xwidget`, on a text terminal or a build without them | Set `imprimeur-target` to `auto` or `browser`. |
| "No imprimeur session in this buffer" | The mode is off here | Type `M-x imprimeur-mode`. |
| The mode line says "not answering", with an offer of `imprimeur-browse` | The page died twice within a minute of showing your text | Kill the page's buffer and type `M-x imprimeur-show` to try again, or type `M-x imprimeur-browse`. |
| A blank page in an Emacs window, while a browser shows the same buffer | Emacs cannot tell that a WebKit process has died while another page is connected | Close the browser's desktop window: the page then loads again. |
| The page shows an old version under a message | pandoc failed, or took too long | Read pandoc's message, fix the document or raise `imprimeur-render-timeout`. The next good render clears it. |
| "The connection to Emacs is lost." | Emacs ended or the session's server stopped | Type `M-x imprimeur-mode` again in the buffer. |
| "The session has ended in Emacs." | The mode was turned off | Close the desktop window, or turn the mode on again. |
| "The page is behind the buffer: this place may have moved" | A double-click named a line of a revision older than the buffer | Double-click again once the page shows your text. |
| "The page's link leads to no web address" | The target is missing, or lies outside the document's root | Correct the link. |
| A picture shows as a link that names a host | The document is not trusted, so remote images do not load | List it in `trusted-content`, or set `imprimeur-remote-images`. |
| A diagram stays as code | The page has no Mermaid script | Install mermaid-cli, or set `imprimeur-mermaid-script`. |
| A video stays on a still picture, with "Open externally" | WebKit has no GStreamer plugins, or starts no media in an Emacs window | Follow the link, or type `M-x imprimeur-browse`. |
| A bracket in maths stays one line tall | No maths font | Install Libertinus Math or DejaVu Math TeX Gyre. |
| The page's faces are not the skin's | Its fonts are not installed | [Install them](install-the-fonts.md). |
| Écrivain's letters leave the ruling | Ecrivain Espace is missing | Build its `fonts.nix`. |
| Tianlu's grid breaks in Chromium under `siku` or `kai` | The Kai 4.0 shares its names with the 5.1 | Run `fc-list : file postscriptname \| grep TW-MOE-Std-Kai`, and remove any file but the 5.1. |
| "The skin NAME could not load" | A sheet of the skin failed to load | Choose it again by `M-g s`. |
| "The skin NAME is refused", in `*Warnings*` | Its manifest breaks [the skin API](../reference/skin-api.md) | Read the reason, and correct the manifest. |
| "No skin NAME is registered" | `imprimeur-skin` names a skin that is not installed | Install it, or correct the name. |
| "This heading is folded", from sommaire | A folded heading opens no minitoc, and a jump stops at the fold | Unfold it with Org's or outline's commands. |
| "The headings have changed", from sommaire | The list was older than the buffer | Choose again. |
| sommaire says that a buffer is too large | It reads at most 1,000,000 accessible characters | Narrow to less. |
| Emacs crashes with the page in an Emacs window | Xwidgets are experimental in Emacs | Set `imprimeur-target` to `browser`, and [try xwidgets first](../../README.md#try-xwidgets-first). |
