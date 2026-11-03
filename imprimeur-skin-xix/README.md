# imprimeur-skin-xix

The skin XIX of [imprimeur](../README.md#skins): a French book of the
XIX<sup>th</sup> century. Junicode with its ligatures, the title and a two-line
lettrine in vermilion, narrow spaces in French, code in Courier Prime, and paper
or candlelight as the Emacs theme's appearance says. `../examples/xix/` holds a
French sample and an English one.

## Fonts

The skin names fonts and ships none. `fonts.nix` lists them, and the page falls
back through its stacks on what is missing.

| Family           | Role                                                  | nixpkgs         | Licence  |
|------------------|-------------------------------------------------------|-----------------|----------|
| Junicode         | Text, titles and lettrine by default                  | `junicode`      | OFL-1.1  |
| Bodoni Moda      | Text face, small capitals under Theano Didot          | `bodoni-moda`   | OFL-1.1  |
| Theano Didot     | Text face, with no italic and no small capitals       | `theano`        | OFL-1.1  |
| Libertinus Serif | Text face, end of every stack, the narrow space       | `libertinus`    | OFL-1.1  |
| Libertinus Math  | Maths                                                 | `libertinus`    | OFL-1.1  |
| EB Garamond 12   | Text face                                             | `eb-garamond`   | OFL-1.1  |
| Courier Prime    | Code                                                  | `courier-prime` | OFL-1.1  |
| DejaVu Sans Mono | The arrows, Greek and box drawing that code may hold  | `dejavu_fonts`  | Bitstream Vera |

## Options

`M-g o` chooses one, and the echo area gives the entry to keep in
`imprimeur-skin-options`.

| Option      | Values                                                     | Default         |
|-------------|------------------------------------------------------------|-----------------|
| `text-face` | `junicode`, `bodoni-moda`, `theano`, `libertinus`, `eb-garamond` | `junicode` |
| `ligatures` | `none`, `common`, `discretionary`, `historical`            | `discretionary` |
| `measure`   | `24`, `24-5`, and so on by half a rem to `40`              | `30`            |

Junicode files its looped ct and st and its ties under its discretionary
ligatures, so the default shows them. Its historical set is medieval, and would
change 43% of the words of the French sample, so `historical` adds nothing
under Junicode, and adds the face's own elsewhere.

## Limits

Words break by the shared filter `hyphenate`, in French and English; a document
with no language counts as English, and any other language stays whole and ragged.
Tried in WebKit at scale 1 on a virtual display and in headless Chromium, not on a real
Wayland session or on a Mac, whose choice among Junicode's cuts is unseen.
