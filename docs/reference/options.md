# Options

Every user option of imprimeur and sommaire. Set them with `setopt`, `use-package`'s
`:custom`, or `M-x customize-group`. [The README's configuration](../../README.md#configuration)
shows them all at their defaults.

## imprimeur

| Option | Default | Choices and meaning |
|---|---|---|
| `imprimeur-target` | `auto` | Where a page opens. `auto`: in an Emacs window when the selected Emacs frame is graphic and this Emacs has xwidgets, otherwise in a desktop window of the browser. `xwidget`: in an Emacs window, refusing where that cannot run. `browser`: in a desktop window of the browser. |
| `imprimeur-display-buffer-action` | Right of the Emacs frame, half its width, dedicated | The `display-buffer` action that shows a page in an Emacs window. `((display-buffer-same-window))` takes the source's Emacs window, and quitting brings the source back. An entry of `display-buffer-alist` for the category `imprimeur` comes first. |
| `imprimeur-scroll-sync` | `both` | `both`: each follows the other. `to-preview`: the page follows the source alone. `nil`: neither, and `imprimeur-follow-mode` stays off in a new session until turned on by hand, when each follows the other. |
| `imprimeur-browser-program` | `"chromium"` | The Chromium, or a browser that takes its options, for a desktop window. Only Chromium is tested. |
| `imprimeur-pandoc-program` | `"pandoc"` | The pandoc 3 that renders documents. A wrapper is fine while its output stays a bare fragment. |
| `imprimeur-reader-alist` | See [formats](documents.md#formats) | How a buffer's pandoc reader is chosen: `(MATCHER . READER)`, where MATCHER is a major mode, or a regular expression on the file name. The first match wins. |
| `imprimeur-render-delay` | `0.3` | Seconds of quiet after a change before the page renders again. |
| `imprimeur-render-max-delay` | `2.0` | Seconds after which a render happens even while typing goes on. |
| `imprimeur-render-timeout` | `20` | Seconds after which a render is abandoned, and its error shown. |
| `imprimeur-remote-images` | `trusted` | Whether the page loads images from the network. `nil`: never. `trusted`: for documents that `trusted-content` accepts. `t`: always, which lets a document track that you read it. |
| `imprimeur-appearance` | `auto` | `auto`: the background mode of the Emacs frame that gives the page its colours. `light`, `dark`: force one, while the colours stay the theme's. A change shows at the next change of theme, or with `imprimeur-refresh-palette`. |
| `imprimeur-mermaid-script` | `nil` | `nil`: the copy beside the program `mmdc`, from mermaid-cli. An absolute file name, or one under `~`: that file, a classic script that sets the global `mermaid`. |
| `imprimeur-skin` | `auto` | The skin of a new page. `auto`: the skin registered with `:auto`, Minitel, if installed, otherwise the plain page. Another symbol names a registered skin; one that nothing registered means `auto`, and the echo area says so. |
| `imprimeur-skin-options` | `nil` | Values of skins' options to start from, by skin then by option, such as `((xix (measure . "28")))`. An entry of a registered skin that it does not register warns once and is ignored. |

Each skin's options, with their values, are in that skin's README:
[Tianlu](../../imprimeur-skin-tianlu/README.md#options),
[Minitel](../../imprimeur-skin-minitel/README.md#options),
[XIX](../../imprimeur-skin-xix/README.md#options),
[XVIII](../../imprimeur-skin-xviii/README.md#options),
[XVII](../../imprimeur-skin-xvii/README.md#options),
[Briefing](../../imprimeur-skin-briefing/README.md#options),
[Écrivain](../../imprimeur-skin-ecrivain/README.md#options),
[Dubai](../../imprimeur-skin-dubai/README.md#options) and
[Yaqut](../../imprimeur-skin-yaqut/README.md#options).

Mode hooks: `imprimeur-mode-hook`, `imprimeur-follow-mode-hook` and
`imprimeur-view-mode-hook`.

Emacs's own `trusted-content` says which documents are trusted: they may load remote
images under `trusted`, and pandoc then runs without its sandbox, so that `#+INCLUDE` works.

## sommaire

| Option | Default | Choices and meaning |
|---|---|---|
| `sommaire-header-line` | `t` | Non-nil: show the segment in the header line. Read when the mode starts. |
| `sommaire-heading-buttons` | `t` | Non-nil: the headings that have an inline minitoc carry a button. Read when the mode starts. |
| `sommaire-idle-delay` | `0.4` | Seconds of idle time after which the mode follows point. Read when the first buffer turns the mode on. |
| `sommaire-scope` | `(section . 1)` | What `M-g m` and the panel list: `(ROOT . DEPTH)`. ROOT is `document` or `section`, the section around point. DEPTH is how many levels below ROOT: a positive integer, or `all`. The panel's keys give a buffer its own value. |

Mode hook: `sommaire-mode-hook`.

| Face | What it marks |
|---|---|
| `sommaire-current` | The entry that holds point. |
| `sommaire-archived` | An archived heading in a list of entries. |
| `sommaire-button` | The button of a heading. |
| `sommaire-inline` | An inline minitoc's entries. |
