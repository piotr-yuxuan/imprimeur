// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// Minitel's row 0 and key bar.  Row 0 says where the reader is and whether the page
// follows Emacs, C or F as on the terminal; the bar holds the terminal's nine keys,
// each of which also answers to its key.  What the page shows is set as text: nothing
// of the document becomes markup here.

function element(tag, attributes, ...children) {
  const node = document.createElement(tag);
  Object.assign(node, attributes);
  node.append(...children);
  return node;
}

export default function mount({ signal, key, hold, latest, goToLine }) {
  const root = document.documentElement;
  const main = document.getElementById('imprimeur-main');
  const heading = document.getElementById('imprimeur-title');

  const say = (fr, en) => ((root.lang || '').startsWith('fr') ? fr : en);
  const headings = () => [...main.querySelectorAll('h1, h2, h3, h4, h5, h6')];

  const crumb = element('span', { className: 'minitel-crumb' });
  const position = element('span', { className: 'minitel-pos' });
  const letter = element('button', { className: 'minitel-letter', type: 'button' });
  const row0 = element('div', { id: 'minitel-row0' }, element('div', { className: 'minitel-band' }, crumb, position, letter));

  // Where a title counts as reached: just under row 0, where SUITE and RETOUR leave it.
  const line = () => row0.getBoundingClientRect().bottom + parseFloat(getComputedStyle(root).lineHeight) + 2;
  const reached = () => headings().filter((one) => one.getBoundingClientRect().top <= line()).at(-1);

  // Whether the page follows Emacs: on, off, or ended, once the session has, which no
  // key takes back.  The letter says it in the document's language, which comes with
  // its first revision.
  let following = 'on';

  function placeRow() {
    const name = heading.textContent || headings()[0]?.textContent || document.title;
    const section = reached()?.textContent;
    crumb.textContent = section && section !== name ? `${name} › ${section}` : name;
    const range = root.scrollHeight - innerHeight;
    position.textContent = `${range > 0 ? Math.round((scrollY / range) * 100) : 100}%`;
    letter.textContent = following === 'on' ? 'C' : 'F';
    letter.title = {
      on: say('La page suit Emacs', 'The page follows Emacs'),
      off: say('La page ne suit plus Emacs', 'The page no longer follows Emacs'),
      ended: say('La session est finie dans Emacs', 'The session has ended in Emacs'),
    }[following];
  }

  let placing = false;
  function schedule() {
    if (placing) return;
    placing = true;
    requestAnimationFrame(() => {
      placing = false;
      placeRow();
    });
  }

  // SOMMAIRE or GUIDE, over the page; only one at a time, and the same key closes it.
  let screen = null;
  let typed = '';
  let choices = [];
  let before = null;

  function closeScreen() {
    if (screen?.contains(document.activeElement)) before?.focus({ preventScroll: true });
    screen?.remove();
    screen = null;
    typed = '';
    choices = [];
  }

  // By the page's own line: WebKitGTK and Chromium differ on scroll-padding.
  function goTo(one) {
    closeScreen();
    scrollTo(0, one.getBoundingClientRect().top + scrollY - line() + 4);
  }

  function openScreen(kind, ...content) {
    const same = screen?.dataset.kind === kind;
    closeScreen();
    if (same) return false;
    screen = element('div', { id: 'minitel-screen', tabIndex: -1 }, element('p', { className: 'minitel-screen-title', textContent: kind }), ...content);
    screen.dataset.kind = kind;
    screen.addEventListener('dblclick', (event) => event.stopPropagation());
    document.body.append(screen);
    before = document.activeElement;
    (screen.querySelector('button') ?? screen).focus({ preventScroll: true });
    return true;
  }

  const prompt = element('p', { className: 'minitel-prompt' });
  const writePrompt = (remark = '') => {
    prompt.textContent = `${say('Votre choix : ', 'Your choice: ')}${typed}█ + ENVOI${remark}`;
  };

  const rub = () => {
    typed = typed.slice(0, -1);
    writePrompt();
  };

  // The one owner of the state: F holds the page where it is, and C shows what waited.
  function follow(state) {
    if (following === 'ended') return;
    following = state;
    row0.dataset.following = state;
    bar.dataset.following = state;
    hold(state === 'off');
    placeRow();
  }

  // A key that needs Emacs declines it once the session has ended, which gives it back
  // to Emacs in an Emacs window.  So q then quits the view, and in a browser does nothing.
  const toggle = () => {
    if (following === 'ended') return false;
    follow(following === 'on' ? 'off' : 'on');
    return true;
  };

  // In the order of the bar, which is the terminal's: two rows of four, then one apart.
  // Those marked live need Emacs.
  const keys = [
    {
      name: 'SOMMAIRE',
      key: 's',
      does: ['les titres, à choisir par leur numéro', 'the headings, chosen by number'],
      act() {
        const wanted = headings().filter((one) => one.matches('h1, h2, h3'));
        const list = element('ol', {}, ...wanted.map((one) => element(
          'li',
          { className: `minitel-level-${one.localName}` },
          element('button', { type: 'button', textContent: one.textContent, onclick: () => goTo(one) }),
        )));
        if (openScreen('SOMMAIRE', list, prompt)) {
          choices = wanted;
          writePrompt();
        }
      },
    },
    {
      name: 'ANNULATION',
      key: 'Escape',
      label: 'Esc',
      does: ['ferme l’écran, efface le choix', 'closes the screen, clears the choice'],
      act() {
        if (!screen) return false;
        closeScreen();
        return true;
      },
    },
    {
      name: 'RETOUR',
      key: 'p',
      does: ['le titre précédent', 'the previous heading'],
      act() {
        const one = headings().findLast((candidate) => candidate.getBoundingClientRect().top < line() - 6);
        if (one) goTo(one);
        else scrollTo(0, 0);
      },
    },
    {
      name: 'RÉPÉTITION',
      key: 'g',
      live: true,
      does: ['refait la page ; à F, la dernière révision, sans quitter F', 'makes the page again; at F, the latest revision, staying at F'],
      act() {
        if (following === 'ended') return false;
        if (following === 'on') location.reload();
        else latest();
        return true;
      },
    },
    {
      name: 'GUIDE',
      key: '?',
      does: ['cet écran', 'this screen'],
      act() {
        openScreen('GUIDE', element('dl', {}, ...keys.flatMap(({ name, key: pressed, label, does }) => [
          element('dt', {}, `${name} `, element('kbd', { textContent: label ?? pressed })),
          element('dd', { textContent: say(...does) }),
        ])));
      },
    },
    {
      name: 'CORRECTION',
      key: 'e',
      live: true,
      does: ['efface un chiffre du choix ; sinon, va à la source', 'rubs out a digit of the choice; otherwise goes to the source'],
      // The source's line of what stands under row 0.
      act() {
        if (typed) {
          rub();
          return true;
        }
        if (following === 'ended') return false;
        const here = [...main.querySelectorAll(':scope > [data-line]')].find((one) => one.getBoundingClientRect().bottom > line());
        goToLine(Math.max(1, Number(here?.dataset.line ?? 1)));
        return true;
      },
    },
    {
      name: 'SUITE',
      key: 'n',
      does: ['le titre suivant', 'the next heading'],
      act() {
        const one = headings().find((candidate) => candidate.getBoundingClientRect().top > line());
        if (one) goTo(one);
      },
    },
    {
      name: 'ENVOI',
      key: 'Enter',
      label: 'RET',
      does: ['valide le choix, ou l’entrée où l’on est', 'confirms the choice, or the entry the focus is on'],
      // Outside a choice, a link's or a button's own.
      act() {
        const choice = choices[Number(typed) - 1];
        if (typed && choice) goTo(choice);
        else if (typed) {
          const number = typed;
          typed = '';
          writePrompt(say(` (pas de titre ${number})`, ` (no heading ${number})`));
        } else if (screen?.contains(document.activeElement)) document.activeElement.click();
        else return false;
        return true;
      },
    },
    {
      name: 'CONNEXION/FIN',
      key: 'q',
      live: true,
      does: ['suivre Emacs, ou cesser : C ou F ; la session finie, F reste', 'follow Emacs, or stop: C or F; once the session has ended, F stays'],
      act: toggle,
    },
  ];

  const bar = element('nav', { id: 'minitel-keys', ariaLabel: 'Minitel' }, element('div', { className: 'minitel-band' }, ...keys.map(({ name, key: pressed, label, live, act }) => element(
    'button',
    { type: 'button', className: live ? 'minitel-live' : '', onclick: act },
    element('span', { textContent: name }),
    ' ',
    element('kbd', { textContent: label ?? pressed }),
  ))));

  letter.onclick = toggle;

  for (const one of keys) key(one.key, one.act);
  // A digit, or Backspace, means something only in a choice.
  for (const digit of '0123456789') {
    key(digit, () => {
      if (!choices.length) return false;
      typed += digit;
      writePrompt();
      return true;
    });
  }
  key('Backspace', () => {
    if (!typed) return false;
    rub();
    return true;
  });

  // A double-click here asks the source for no line.
  for (const part of [row0, bar]) part.addEventListener('dblclick', (event) => event.stopPropagation());

  document.body.prepend(row0);
  document.body.append(bar);
  addEventListener('scroll', schedule, { passive: true, signal });
  addEventListener('resize', schedule, { signal });
  document.addEventListener('imprimeur-shown', schedule, { signal });
  document.addEventListener('imprimeur-ended', () => {
    follow('ended');
    for (const live of [letter, ...bar.querySelectorAll('.minitel-live')]) live.ariaDisabled = 'true';
  }, { signal });
  signal.addEventListener('abort', () => {
    closeScreen();
    row0.remove();
    bar.remove();
  });
  follow('on');
}
