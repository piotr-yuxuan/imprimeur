// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// What a stylesheet cannot do for Dubai: the memo's Skim link, the Umm al-Qura date beside
// the masthead's, a test of the font's figures, details on paper, and a diagram's natural
// size.

// Each designed figure is about 0.73 as wide as the plain one in Inter, in both engines; a
// font with none stays at 1.
const designedFigures = 0.85;

// The calendar is always named in full: WebKit takes a plain islamic for islamic-tbla.
const calendar = 'islamic-umalqura';

// The Umm al-Qura date of ISO, a day written YYYY-MM-DD, to stand beside SHOWN, the
// masthead's Gregorian date of it: in Arabic for a page whose LANGUAGE is Arabic and in
// English otherwise, day first as SHOWN is, in Arabic-Indic digits when SHOWN was typed in
// them; empty for a day that the calendar does not hold, which its round trip shows, or for
// none.  A pure decision, judged by a table in tests/js.
export function hijriDate(iso, shown, language) {
  const parts = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  const date = parts && new Date(Date.UTC(parts[1], parts[2] - 1, parts[3]));
  if (!date?.toISOString().startsWith(iso)) return '';
  const locale = language.split('-')[0].toLowerCase() === 'ar' ? 'ar-AE' : 'en-GB';
  const digits = /[\u{0660}-\u{0669}]/u.test(shown) ? 'arab' : 'latn';
  return new Intl.DateTimeFormat(`${locale}-u-ca-${calendar}-nu-${digits}`,
    { timeZone: 'UTC', day: 'numeric', month: 'long', year: 'numeric' }).format(date);
}

export default function mount({ signal, option }) {
  const root = document.documentElement;
  const main = document.getElementById('imprimeur-main');

  // What a new render or a drawing brings, and the skim view's word on its link.  Writing
  // the same date again would be a mutation, and call this again.
  const follow = () => {
    for (const link of main.querySelectorAll('.dubai-skim')) {
      link.setAttribute('aria-pressed', String(option('skim') === 'on'));
    }
    for (const svg of main.querySelectorAll('pre.mermaid > svg')) {
      const width = svg.viewBox.baseVal?.width;
      if (width) svg.style.setProperty('--dubai-natural', `${width}px`);
    }
    // The Umm al-Qura date of the masthead's day, beside its Gregorian date.
    for (const time of main.querySelectorAll('time.dubai-hijri')) {
      const shown = time.parentElement.querySelector('.dubai-date')?.textContent ?? '';
      const text = hijriDate(time.getAttribute('datetime'), shown, root.lang);
      if (time.textContent !== text) time.textContent = text;
    }
  };
  const watcher = new MutationObserver(follow);
  watcher.observe(root, { attributes: true, attributeFilter: ['data-dubai-skim', 'lang'] });
  watcher.observe(main, { childList: true, subtree: true });
  follow();

  // The link flips this page, at once: the next option that Emacs sets speaks for the
  // session again, skim with it.
  document.addEventListener('click', (event) => {
    if (!(event.target instanceof Element && event.target.closest('.dubai-skim'))) return;
    if (option('skim') === 'on') root.removeAttribute('data-dubai-skim');
    else root.setAttribute('data-dubai-skim', 'on');
  }, { capture: true, signal });

  // On paper, nothing stays folded, and what the reader had open stays open after.
  let opened = [];
  window.addEventListener('beforeprint', () => {
    opened = [...main.querySelectorAll('details:not([open])')];
    for (const details of opened) details.open = true;
  }, { signal });
  window.addEventListener('afterprint', () => {
    for (const details of opened) details.open = false;
  }, { signal });

  signal.addEventListener('abort', () => {
    watcher.disconnect();
    root.classList.remove('dubai-plain-figures');
    for (const svg of main.querySelectorAll('pre.mermaid > svg')) svg.style.removeProperty('--dubai-natural');
    for (const time of main.querySelectorAll('time.dubai-hijri')) time.textContent = '';
  });

  document.fonts.ready.then(() => {
    if (signal.aborted) return;
    const span = document.body.appendChild(document.createElement('span'));
    span.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap;';
    const widthOf = (digit, position) => {
      span.textContent = digit;
      span.style.fontVariantPosition = position;
      return span.getBoundingClientRect().width;
    };
    const designed = [...'0123456789'].every((digit) => widthOf(digit, 'super') < widthOf(digit, 'normal') * designedFigures);
    span.remove();
    root.classList.toggle('dubai-plain-figures', !designed);
  });
}
