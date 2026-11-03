# Sources of the samples

Both briefs are real letters, set as briefs by an essay that says so at its head. No memo here
is invented.

| File | Holds | Source |
|---|---|---|
| `turgot.org`, with `turgot-depenses.svg` and `turgot-paroles.webm` | Turgot's letter to Louis XVI of 24 August 1774, on taking up the place of controller general, with his table of expenses for 1775 and Malesherbes's note on the draft | Eugène Daire, *Œuvres de Turgot*, Guillaumin, 1844, vol. II, pp. 165 to 169, as [fr.wikisource](https://fr.wikisource.org/wiki/%C5%92uvres_de_Turgot_(Daire,_1844)/Actes_du_Minist%C3%A8re_de_Turgot) gives it, and vol. I, Daire's notice. Gustave Schelle, *Œuvres de Turgot et documents le concernant*, vol. IV, nos. 150 and 172, in the Institut Coppet's reissue, archive.org item `turgot-oc-4_202606`, the text layer of `Turgot-OC4.pdf`, sha1 `28c5f1055ac076c79ca14a65044dd0ba275c70e2` |
| `jefferson.md`, with `lewis-estimate.svg` and `lewis-somme.webm` | Jefferson's instructions to Meriwether Lewis of 20 June 1803, with Lewis's estimate of expenses as its table | *The Papers of Thomas Jefferson*, vol. 40, pp. 176 to 183, and vol. 39, pp. 342 and 343, on [Founders Online](https://founders.archives.gov/documents/Jefferson/01-40-02-0136-0005), read through the Internet Archive's captures of December 2024, as Founders Online refused the requests made for this essay |

Everything else in each file says that it is the essay's: the setting as a brief, the priorities,
owners and dates of its actions, the service titles, the linking prose, the program, the glossary,
the figure, the diagram and the film, which are under the repository's licence. Jefferson's
editors are named and said in the essay's own words, not quoted, but for the purveyor's table,
whose facts their note gives. The witnesses disagree in places, which the briefs say where it
matters: *impôts* and *impositions*, and the sum of the deficit. Schelle's table of revenues does
not quite add up on that page. Schelle was read in a text layer, and not compared with the printed
edition or with Gallica; neither prose was compared with a first edition.

## The checks of the quotations

Each brief promises that what stands in quotation marks is quoted to the letter. A program checked
it on 2026-11-03: it took every guillemet, every double-quoted phrase and every paragraph of an Org
quotation block, outside code, front matter and keywords, and looked for each in the witnesses
below, capitals and punctuation included, folding only what changes no letter: composition, curly
apostrophes, the kinds of space, a note's figure, and a hyphen at a line's end.

| Brief | Quotations | Not to the letter | The sums, recomputed |
|---|---|---|---|
| `turgot.org` | 51 | 0 | The 21 articles of 1775 add to 234 962 756, and the three deficit lines and the four rows of the second table follow |
| `jefferson.md` | 29 | 0 | Lewis's 11 articles add to 2,500, and the purveyor's rows to 1,528 and 2,160.13 |

The titles of action are the letters' words too, by the same program with a first capital, and those
that the essay writes, such as *Les mots du temps* or *Bottom line*, say so in each brief's note. A
witness holds page furniture or an editor's words under its publisher's rights, so none is copied
here. The plain texts that the briefs were compared with, by SHA-256:

```
b4035b34daf9a5bfbf6137ba8593da610467450355c8ed4a8eb2d90588178ba8  Daire, Actes du ministère
d6bfed383d92382d1d895c05a2f3e599bbdcc001a5934b6d5edae8ff7ddfe1c5  Daire, notice
cb1b1f9d8b430d1d48eeaeac8becc160ee0040ebdc48acd4aaa21ee325785d78  Schelle, the letter
7e76a409c97a0eb99af575daf41fbe77c2c52ffaf771f42dfff25f753d782e6f  Schelle, the account
7e52a003ccd6437a46519f9484f4195ecfc5b1b3eafb3fb01aef7f3f1dcf42e2  Schelle, the table
b8045a5ef9abb862aa0cad8661c534ea403204242171eee83a0c2cddbf90efa3  Schelle, the whole text layer
0e403e5729403ec670d3ac6005f946dbb5327b91d1813ce345aab9db1637f73c  Jefferson, the instructions
7cb6f86cf3cc4ff3fc2431651263129bc6eb2167ae01e52b870266577496d26b  Lewis, the estimate
```

Turgot, Daire, Malesherbes, Jefferson, Lewis and Schelle's century-old edition are read as public
domain. The drawings and films copy no printer's ornament.
