// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// What a stylesheet cannot do for Yaqut: the colophon's date in the Hijri calendar that the
// option calendar names, which a filter cannot write, as it has no Intl; and the height in
// lines of the triangle that sets the colophon's words, which only a layout can tell.

// The option's values as Intl names their calendars.  A plain islamic is islamic-tbla in
// WebKit, so each is named in full.
const calendars = { umalqura: 'islamic-umalqura', civil: 'islamic-civil' };

// The most lines a colophon's triangle may take: words beyond it run on below.
const maxLines = 40;

// ISO, a date written YYYY-MM-DD, as { day, month, year } in CALENDAR, a value of the option,
// in Arabic with Arabic-Indic digits; or null when ISO is no date of the Gregorian calendar,
// or when this engine cannot reckon in that calendar.
export function hijriDate(iso, calendar) {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso ?? '');
  if (!match || !calendars[calendar]) return null;
  const [year, month, day] = match.slice(1).map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  const format = new Intl.DateTimeFormat(`ar-u-ca-${calendars[calendar]}-nu-arab`,
    { timeZone: 'UTC', day: 'numeric', month: 'long', year: 'numeric' });
  if (format.resolvedOptions().calendar !== calendars[calendar]) return null;
  const parts = Object.fromEntries(format.formatToParts(date).map(({ type, value }) => [type, value]));
  return { day: parts.day, month: parts.month, year: parts.year };
}

export default function mount({ signal, option }) {
  const root = document.documentElement;
  const main = document.getElementById('imprimeur-main');

  // Each date in the calendar in force, its year after the year sign.  A date already in that
  // calendar is left alone, and one that is no date keeps the words the filter wrote.
  const date = () => {
    const calendar = option('calendar');
    for (const time of main.querySelectorAll('time.yaqut-hijri')) {
      const parts = time.dataset.yaqutCalendar === calendar ? null : hijriDate(time.getAttribute('datetime'), calendar);
      if (!parts) continue;
      const year = document.createElement('span');
      year.className = 'yaqut-year';
      year.textContent = `\u0601${parts.year}`;
      time.replaceChildren(`${parts.day} ${parts.month} `, year);
      time.dataset.yaqutCalendar = calendar;
    }
  };

  // The fewest lines whose triangle holds the words: the sheet floats two shapes that many lines
  // tall beside them, which take a share of each line that grows towards the apex.  The block
  // then ends with its last line, as the shapes may reach below it.
  const shape = () => {
    for (const text of main.querySelectorAll('.yaqut-colophon-text')) {
      const words = document.createRange();
      words.selectNodeContents(text.lastChild ?? text);
      const line = parseFloat(getComputedStyle(text).lineHeight);
      const top = text.getBoundingClientRect().top;
      let lines = 1;
      text.style.removeProperty('--yaqut-colophon-height');
      text.style.setProperty('--yaqut-colophon-lines', lines);
      while (lines < maxLines && words.getBoundingClientRect().bottom > top + lines * line + 1) {
        lines += 1;
        text.style.setProperty('--yaqut-colophon-lines', lines);
      }
      text.style.setProperty('--yaqut-colophon-height', `${Math.ceil(words.getBoundingClientRect().bottom - top)}px`);
    }
  };

  const lay = () => {
    date();
    shape();
  };

  const watcher = new MutationObserver(lay);
  signal.addEventListener('abort', () => {
    watcher.disconnect();
    for (const time of main.querySelectorAll('time.yaqut-hijri')) {
      time.textContent = time.getAttribute('datetime');
      delete time.dataset.yaqutCalendar;
    }
    for (const text of main.querySelectorAll('.yaqut-colophon-text')) {
      text.style.removeProperty('--yaqut-colophon-lines');
      text.style.removeProperty('--yaqut-colophon-height');
    }
  });
  watcher.observe(root, {
    attributes: true,
    attributeFilter: ['data-yaqut-preset', 'data-yaqut-title', 'data-yaqut-notes', 'data-yaqut-calendar', 'lang'],
  });
  document.addEventListener('imprimeur-shown', lay, { signal });
  window.addEventListener('resize', shape, { signal });
  document.fonts.ready.then(() => {
    if (!signal.aborted) shape();
  });
  lay();
}
