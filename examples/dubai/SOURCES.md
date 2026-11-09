# Sources of the samples

Both briefs are real texts: two laws of the Emirate of Dubai, set as briefs by an editor who says so
at the head of each. **No reader of Arabic has checked them:** not the transcription, nor the
editor's Arabic, nor the skin's labels. Read the official text before relying on either.

| File | Holds | Source |
|---|---|---|
| `budget-2025-2027.org` | Law No. (23) of 2024, which approves the general budget cycle of the Government of Dubai for the fiscal years 2025 to 2027 and the general budget for 2025, set as a brief: all seven articles and the signature | [The Dubai Legislation Portal](https://dlp.dubai.gov.ae/Legislation%20Ar%20Reference/2024/%D9%82%D8%A7%D9%86%D9%88%D9%86%20%D8%B1%D9%82%D9%85%20%2823%29%20%D9%84%D8%B3%D9%86%D8%A9%202024%20%D8%A8%D8%A7%D8%B9%D8%AA%D9%85%D8%A7%D8%AF%20%D8%AF%D9%88%D8%B1%D8%A9%20%D8%A7%D9%84%D9%85%D9%88%D8%A7%D8%B2%D9%86%D8%A9%20%D9%84%D9%84%D8%B3%D9%86%D9%88%D8%A7%D8%AA%20%D8%A7%D9%84%D9%85%D8%A7%D9%84%D9%8A%D8%A9%202025%20-%202027.html), its HTML page |
| `budget-2026-2028.md` | Law No. (15) of 2025, for the cycle 2026 to 2028 and the budget for 2026, beside the law above: the figures of articles 2 and 3 as two comparison tables, the three clauses of article 4 that changed, and articles 6 and 7 | [The Dubai Legislation Portal](https://dlp.dubai.gov.ae/Legislation%20Ar%20Reference/2025/%D9%82%D8%A7%D9%86%D9%88%D9%86%20%D8%B1%D9%82%D9%85%20%2815%29%20%D9%84%D8%B3%D9%86%D8%A9%202025%20%D8%A8%D8%B4%D8%A3%D9%86%20%D8%A7%D8%B9%D8%AA%D9%85%D8%A7%D8%AF%20%D8%AF%D9%88%D8%B1%D8%A9%20%D8%A7%D9%84%D9%85%D9%88%D8%A7%D8%B2%D9%86%D8%A9%20%D8%A7%D9%84%D8%B9%D8%A7%D9%85%D8%A9%20%D9%84%D8%AD%D9%83%D9%88%D9%85%D8%A9%20%D8%AF%D8%A8%D9%8A%202026%20%E2%80%93%202028.html), its HTML page |

The number of the second law was confirmed on the portal itself, on 2026-11-09: its search for
دورة الموازنة lists Law No. (15) of 2025 among the budget laws, after Law No. (23) of 2024.

Everything else in each file is the editor's, and says so in Arabic where it stands: the title and
subtitle, the status, the bottom line, the notes, the headings above the law's own, the tables and
their differences, the drawing of the cycle, the statuses, priorities, owners and tags of the action
titles, and the last action of the Markdown brief. It is under the repository's licence. The dates
of the mastheads are the laws' own dates of issue.

## Rights

Federal Decree-Law No. 38 of 2021 on Copyrights and Neighbouring Rights, article 3(2), excludes from
protection "Official documents, regardless of their original language, or the language transmitted
to them, such as texts of laws", in the English translation that Lexis Middle East published and
[Abu Dhabi's Department of Economic Development](https://added.gov.ae/ipu/-/media/Files/Batch-3/copyright.pdf)
serves. The laws are quoted under that article. Neither file uses an emblem, a flag or Dubai Font.

## What differs from the official text

- The portal writes an en dash, U+2013, between the two years of a cycle. This repository admits no
  U+2013, so the briefs write a hyphen there, as the portal's file name of the first law does.
- Each lettered clause of the portal begins with a zero-width non-joiner, U+200C, before its letter,
  which the briefs leave out.
- The numbered clauses of article 4 are lists, and the signature's lines are broken where the
  portal breaks them. The headings of the four parts of article 4 lose their final colon.
- The date of Law No. 15 of 2025 is quoted from neither file: the portal's line ends in a stray
  `>>`.

## The checks of the quotations

A program compared, on 2026-11-09, every line of each brief that holds Arabic with the text of the
portal's pages, after the changes above. Every line of the law's that a brief quotes is there to the
letter, diacritics and tatweels included; the lines that are not are the editor's, listed above.

| Brief | Lines quoted | Not to the letter |
|---|---|---|
| `budget-2025-2027.org` | 40 | 0 |
| `budget-2026-2028.md` | 8 | 0 |

Each figure of the comparison tables stands in its law's text as written there, and each difference
was computed again. Law No. 23 of 2024 gives its own dual date, 22 October 2024, corresponding to 19
Rabi' al-Akhir 1446; the skin's option `hijri` computes the second from the first, and its tests
take this pair as their vector. Law No. 15 of 2025 gives 17 November 2025, corresponding to 26
Jumada al-Ula 1447, which the same calendar gives too.

The pages that the briefs were compared with, as the portal served them on 2026-11-09, by SHA-256:

```
ee3ab9b9a9318c0a8ce940c29d7cefd5be0da3d2db913babde8655405f8ed9ed  Law No. (23) of 2024, HTML
bc5438ce60d11ae8ede8411ab0f0da49d59e684a274c16f69ca3a4233e9ad3d8  Law No. (15) of 2025, HTML
```
