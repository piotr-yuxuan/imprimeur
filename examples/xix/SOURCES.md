# Sources of the samples

| File | Holds | Source |
|---|---|---|
| `francais.org`, with `planche-coupe.svg` and `.webm` | The opening of *De la démocratie en Amérique*, then the sample's own chapters, which show every construct | Alexis de Tocqueville, 1835, tome I of the twelfth edition, as [Project Gutenberg, ebook 30513](https://www.gutenberg.org/cache/epub/30513/pg30513-images.html) gives it |
| `dickens.md`, with `plate-sort.svg` | The first chapter of *Bleak House*, in part; then the sample's own two chapters, on setting type, with one quotation | Charles Dickens, 1853; [Project Gutenberg, eBook 1023](https://www.gutenberg.org/ebooks/1023.txt.utf-8). The quotation is from Moxon, [ebook 78991](https://www.gutenberg.org/ebooks/78991.txt.utf-8) |

Everything else in each file says that it is the sample's own, and the drawings are under the
repository's licence.

## The check of the quotations

A program compared `dickens.md` with the plain texts below on 2026-11-03: the 13 paragraphs of
its first chapter, each whole, against eBook 1023, and the one quotation against ebook 78991, all
found. It fails on a changed word. They are Dickens's paragraphs, in his order, with some left out between
them; the one set as a block quotation stands alone in the text too. It keeps Project Gutenberg's
"Michaelmas term", in lower case, and its curly quotation marks. Each of his em dashes is written
U+2015, the horizontal bar, as this repository holds no em dash and `scripts/check-public` refuses
one, as `examples/minitel/SOURCES.md` does for the dashes of its French dialogue; that is the one
sign that differs from the text. A browser breaks a line at an em dash and not at this bar, so each
stays joined to its words. Neither was compared with a first edition.

```
27e002dee487817b00ba884f3d5ffd8dbb821f82353e914cdc22bf33c413ba16  pg1023.txt
3da21314b0d4a7247d618bbbba26e24a92082e9d86b67a5efdfea9c6019796f1  pg78991.txt
```

As Project Gutenberg's paragraph 1.E.1 asks of a copy:

This eBook is for the use of anyone anywhere in the United States and most other parts of
the world at no cost and with almost no restrictions whatsoever. You may copy it, give it
away or re-use it under the terms of the Project Gutenberg™ License included with this
eBook or online at [www.gutenberg.org](https://www.gutenberg.org/license). If you are not
located in the United States, you will have to check the laws of the country where you are
located before using this eBook.
