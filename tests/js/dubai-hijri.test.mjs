// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirements (plan 051, acceptance 6, and the README of imprimeur-skin-dubai): the
// masthead's day, 22 October 2024, the date of Dubai's Law No. 23 of 2024, which the law
// gives as 19 Rabi' al-Akhir 1446, is day 19 of ربيع الآخر, 1446, in the calendar
// islamic-umalqura.  So is 11 March 2024 the first of رمضان 1445, as the Umm al-Qura
// calendar and Saudi Arabia's announcement of that month give it, where the tabular
// calendar islamic-tbla, which WebKit takes a plain islamic for, is a day later; on the
// law's day the two agree.  The Umm al-Qura date stands beside the masthead's Gregorian
// date: in Arabic for a page whose language is Arabic, its primary subtag ar in any case,
// and in English for any other, as a document in any language but Arabic takes English
// labels; day first as the Gregorian date is; in the digits that date was typed in.  A day
// that the calendar does not hold, or no day, gives nothing.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hijriDate } from '../../imprimeur-skin-dubai/assets/page.mjs';

test('the Umm al-Qura date of a day is as its table says', () => {
  const law = '2024-10-22';
  const arabic = /^19 ربيع الآخر 1446(?!\d)/u;
  const arabicIndic = /^١٩ ربيع الآخر ١٤٤٦(?![٠-٩])/u;
  const english = /^19 [A-Z][^\d\u{0600}-\u{06FF}]* 1446(?!\d)/u;
  const englishIndic = /^١٩ [A-Z][^\d\u{0600}-\u{06FF}]* ١٤٤٦(?![٠-٩])/u;
  const none = /^$/;
  for (const [title, iso, shown, language, expected] of [
    ['an Arabic page', law, '22 أكتوبر 2024', 'ar', arabic],
    ['the first of Ramadan 1445', '2024-03-11', '11 مارس 2024', 'ar', /^1 رمضان 1445(?!\d)/u],
    ['an Arabic page with a region', law, '22 أكتوبر 2024', 'ar-AE', arabic],
    ['an Arabic page in capitals', law, '22 أكتوبر 2024', 'AR', arabic],
    ['a date typed in Arabic-Indic digits', law, '٢٢ أكتوبر ٢٠٢٤', 'ar', arabicIndic],
    ['an English page', law, '22 October 2024', 'en', english],
    ['a French page, in English', law, '22 October 2024', 'fr', english],
    ['a page of no language, in English', law, '22 October 2024', '', english],
    ['a language whose tag only begins with ar, in English', law, '22 October 2024', 'arc', english],
    ['an English page typed in Arabic-Indic digits', law, '٢٢ October ٢٠٢٤', 'en', englishIndic],
    ['a leap day', '2024-02-29', '29 فبراير 2024', 'ar', /^\d{1,2} \D+ 1445(?!\d)/u],
    ['the 29th of February of a common year', '2023-02-29', '29 فبراير 2023', 'ar', none],
    ['the 31st of February', '2024-02-31', '31 فبراير 2024', 'ar', none],
    ['a thirteenth month', '2024-13-01', '2024-13-01', 'ar', none],
    ['a time after the day', '2024-10-22T00:00', '22 أكتوبر 2024', 'ar', none],
    ['a day written otherwise', '22/10/2024', '22/10/2024', 'ar', none],
    ['an empty day', '', '', 'ar', none],
    ['no day', null, '', 'ar', none],
  ]) {
    assert.match(hijriDate(iso, shown, language), expected, title);
  }
});
