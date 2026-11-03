# Sources of the samples

Both briefs are real texts, set as briefs by an essay that says so at its head. Neither author
wrote a memo: Jefferson wrote a letter and Bagehot a book.

| File | Holds | Source |
|---|---|---|
| `bagehot.org`, with `bagehot-reserve.svg` | Walter Bagehot's argument on the Bank of England's reserve in a panic, chapters I, II, VII and XII and Note D, with his figures as its tables and chart | *Lombard Street: A Description of the Money Market*, 1873; [Project Gutenberg, eBook 4359](https://www.gutenberg.org/ebooks/4359.txt.utf-8), whose transcription has misprints that the brief does not quote and which writes the pound as `L.` after a figure |
| `jefferson.md`, with `lewis-estimate.svg` and `lewis-somme.webm` | Jefferson's instructions to Meriwether Lewis of 20 June 1803, with Lewis's estimate of expenses as its table | *The Papers of Thomas Jefferson*, vol. 40, pp. 176 to 183, and vol. 39, pp. 342 and 343, on [Founders Online](https://founders.archives.gov/documents/Jefferson/01-40-02-0136-0005), read through the Internet Archive's captures of December 2024, as Founders Online refused the requests made for this essay |

Everything else in each file says that it is the essay's: the setting as a brief, the priorities,
owners and dates of its actions, the service titles, the linking prose, the program, the glossary,
the figure, the diagram and the film, which are under the repository's licence. Jefferson's
editors are named and said in the essay's own words, not quoted, but for the purveyor's table,
whose facts their note gives. Neither prose was compared with a first edition.

## The checks of the quotations

Each brief promises that what stands in quotation marks is quoted to the letter. A program checked
it on 2026-11-03: it took every double-quoted phrase and every paragraph of an Org quotation block,
outside code, front matter and keywords, and looked for each in the witnesses below, capitals and
punctuation included, folding only what changes no letter: composition, curly apostrophes, the
kinds of space, a note's figure, and a hyphen at a line's end. It fails on a changed word.

| Brief | Quotations | Not to the letter | The sums, recomputed |
|---|---|---|---|
| `bagehot.org` | 57 | 0 | The three liabilities of 1869 add to 27,235,000. The same program finds every other figure of the text and tables in eBook 4359, but for the three increases of the table of panics, which the essay subtracts and the caption says so. The chart's numbers were read against the tables by hand |
| `jefferson.md` | 29 | 0 | Lewis's 11 articles add to 2,500, and the purveyor's rows to 1,528 and 2,160.13 |

In `jefferson.md`, the titles of action are the letter's words too, by the same program with a first
capital. In `bagehot.org` they are the essay's, in modern English, as its note says. A witness holds
page furniture or an editor's words under its publisher's rights, so none is copied here. The plain
texts that the briefs were compared with, by SHA-256:

```
fb0f41f842b1c86820e9d92d6c800a55e107878d19680e47cb7173faa7c00eda  pg4359.txt
0e403e5729403ec670d3ac6005f946dbb5327b91d1813ce345aab9db1637f73c  Jefferson, the instructions
7cb6f86cf3cc4ff3fc2431651263129bc6eb2167ae01e52b870266577496d26b  Lewis, the estimate
```

Bagehot, Jefferson and Lewis are read as public domain. The drawings and film copy no printer's
ornament.

As Project Gutenberg's paragraph 1.E.1 asks of a copy:

This eBook is for the use of anyone anywhere in the United States and most other parts of
the world at no cost and with almost no restrictions whatsoever. You may copy it, give it
away or re-use it under the terms of the Project Gutenberg™ License included with this
eBook or online at [www.gutenberg.org](https://www.gutenberg.org/license). If you are not
located in the United States, you will have to check the laws of the country where you are
located before using this eBook.
