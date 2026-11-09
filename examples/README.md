# Examples

Documents to open in imprimeur, one set for each skin. Open one, type `M-x imprimeur-mode`, then
press `M-g s` and choose its skin. Each directory's `SOURCES.md` says where its text comes from.

| Skin | Open | What it holds |
|---|---|---|
| Minitel | [`minitel/robida.org`](minitel/robida.org), [`minitel/wells.md`](minitel/wells.md) | Robida's telephonoscope, in French; Wells's Babble Machines, in English |
| XIX | [`xix/dickens.md`](xix/dickens.md), [`xix/francais.org`](xix/francais.org) | The opening of *Bleak House*, in English; Tocqueville, in French |
| XVIII | [`xviii/johnson.md`](xviii/johnson.md), [`xviii/candide.org`](xviii/candide.org) | Johnson's Preface, in English; Voltaire, in French |
| XVII | [`xvii/milton.md`](xvii/milton.md), [`xvii/descartes.org`](xvii/descartes.org) | Milton, in English; Descartes, in French |
| Briefing | [`briefing/bagehot.org`](briefing/bagehot.org), [`briefing/jefferson.md`](briefing/jefferson.md) | A reserve policy from Bagehot's *Lombard Street* of 1873, in Org; Jefferson's instructions of 1803, in Markdown; both in English |
| Écrivain | [`ecrivain/carnet.org`](ecrivain/carnet.org), [`ecrivain/notebook.md`](ecrivain/notebook.md) | A notebook written to try the skin, in French and in English |
| Tianlu | [`tianlu/tinggui-xiaoji.org`](tianlu/tinggui-xiaoji.org), [`tianlu/bisheng-jiaoni-huozi.md`](tianlu/bisheng-jiaoni-huozi.md) | Two essays, in traditional and in simplified characters, which no reader of Chinese has checked |
| Yaqut | [`yaqut/sanaaniyya.org`](yaqut/sanaaniyya.org), [`yaqut/golestan.md`](yaqut/golestan.md) | Al-Hariri's *al-Maqama al-San'aniyya*, in Arabic, for `mamluk`; two stories of Sa'di's *Golestan*, in Persian, for `persian`; both from Wikisource, under CC BY-SA 4.0, which no reader of Arabic or Persian has checked |

[`showcase.org`](showcase.org) belongs to no skin: it says what imprimeur does, in English, for the
README's first picture and the gallery's first table. Its text is the repository's, under its
licence. [Its woodcut](../docs/images/printer-1568.png) is Jost Amman's of 1568, from
[Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Printer_in_1568-ce.png), public domain.

Under Tianlu the gallery shows [`tianlu/showcase.org`](tianlu/showcase.org) instead: the translation
of that document into traditional Chinese, which no reader of Chinese has checked.

A `.md` file needs `markdown-mode`, or an entry of its own in `imprimeur-reader-alist`. Each skin
shows its best with its [fonts](../docs/how-to/install-the-fonts.md).
