// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Requirement (plan 052, "Colophon"): the skin Yaqut writes a document's date, YYYY-MM-DD, in the
// Hijri calendar that its option calendar names, umalqura or civil, as day, month and year in
// Arabic with Arabic-Indic digits; what is no date of the Gregorian calendar, or no calendar of
// the option, gives nothing.  22 October 2024 is 19 Rabi' al-Thani 1446 by Umm al-Qura, the date
// that Dubai Law No. 23 of 2024 prints beside it, as plan 051 read it.  The civil dates are the
// arithmetic of the tabular calendar from its epoch, Friday 16 July 622 (Julian), with the leap
// years where 11 y + 14 mod 30 < 11, after Reingold and Dershowitz, computed by hand apart:
// 18 Rabi' al-Thani 1446, and 28 Jumada al-Ula 1448 for 9 November 2026.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { hijriDate } from '../../imprimeur-skin-yaqut/assets/page.mjs';

const arabic = /^[\u0600-\u06ff ]+$/;

for (const [iso, calendar, day, year] of [
  ['2024-10-22', 'umalqura', '١٩', '١٤٤٦'],
  ['2024-10-22', 'civil', '١٨', '١٤٤٦'],
  ['2026-11-09', 'civil', '٢٨', '١٤٤٨'],
]) {
  test(`${iso} by ${calendar}`, () => {
    const date = hijriDate(iso, calendar);
    assert.equal(date.day, day);
    assert.equal(date.year, year);
    assert.match(date.month, arabic);
  });
}

test('both calendars name the same month of 22 October 2024', () => {
  assert.equal(hijriDate('2024-10-22', 'umalqura').month, hijriDate('2024-10-22', 'civil').month);
});

for (const [iso, calendar] of [
  ['2024-02-30', 'umalqura'],
  ['2023-02-29', 'umalqura'],
  ['2024-13-01', 'umalqura'],
  ['0050-01-01', 'umalqura'],
  ['2024-1-22', 'umalqura'],
  [' 2024-10-22', 'umalqura'],
  ['2024-10-22T00:00', 'umalqura'],
  ['', 'umalqura'],
  [null, 'umalqura'],
  ['2024-10-22', 'gregory'],
  ['2024-10-22', 'islamic'],
  ['2024-10-22', undefined],
]) {
  test(`${JSON.stringify(iso)} by ${calendar} is no date`, () => {
    assert.equal(hijriDate(iso, calendar), null);
  });
}
