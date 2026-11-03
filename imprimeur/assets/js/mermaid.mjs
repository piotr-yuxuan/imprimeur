// SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later
//
// The page's diagrams.  Each pre.mermaid of main gets a drawing of the page's
// look, from the Mermaid script, loaded at the first diagram only.

import DOMPurify from '../vendor/dompurify/purify.es.mjs';
import { fnv1a } from './hash.mjs';

const main = document.getElementById('imprimeur-main');

// A diagram's drawing is SVG alone, with Mermaid's own style element, which
// scopes each rule to the drawing's id; a link stays in the page, like any
// other.
const drawingPolicy = {
  USE_PROFILES: { svg: true, svgFilters: true },
  FORBID_ATTR: ['download', 'target', 'ping'],
  RETURN_DOM_FRAGMENT: true,
};

// Mermaid's theme variables, each with the --imp-* colour of the skin that
// gives it: on a pane like a block of code, nodes and notes look like the
// page, and the slices of a pie like the tokens of code.
const themeColours = {
  background: 'code-background',
  primaryColor: 'background',
  secondaryColor: 'background',
  tertiaryColor: 'code-background',
  noteBkgColor: 'background',
  edgeLabelBackground: 'code-background',
  labelBackground: 'code-background',
  primaryTextColor: 'foreground',
  secondaryTextColor: 'foreground',
  tertiaryTextColor: 'foreground',
  noteTextColor: 'foreground',
  textColor: 'foreground',
  primaryBorderColor: 'rule',
  secondaryBorderColor: 'rule',
  tertiaryBorderColor: 'rule',
  noteBorderColor: 'rule',
  lineColor: 'muted',
  pie1: 'keyword',
  pie2: 'string',
  pie3: 'function',
  pie4: 'constant',
  pie5: 'type',
  pie6: 'comment',
};

// The drawings kept, about what typing in a few diagrams needs: an edit
// that goes back, or a palette that comes back, draws nothing.
const drawingsLimit = 64;

// How long the page waits for Mermaid to draw one diagram, in milliseconds.
const drawingDeadline = 20000;

// Each diagram of main, a pre.mermaid, as first seen: its source, its code
// elements, and its key and SVG once drawn.  A block that stays keeps them.
const diagrams = new WeakMap();
let diagramsShown = [];
// By the hash of what they were drawn from, oldest first.
const drawings = new Map();
let drawCount = 0;
let drawQueue = Promise.resolve();
let mermaidLoaded;

// Show the diagram of PRE: its last drawing or else its code, and beneath
// them the text MESSAGE, if any.
function showDiagram(pre, message) {
  const { svg, code } = diagrams.get(pre);
  pre.replaceChildren(...(svg ? [svg] : code));
  if (message) {
    const note = pre.appendChild(document.createElement('div'));
    note.className = 'imprimeur-diagram-error';
    note.textContent = message;
  }
}

// Return the element of a diagram's SVG, from TEXT, which Mermaid made of
// what the document holds, with a note for the reader: Mermaid keeps some
// labels in a foreignObject, which holds HTML and so goes, leaving a drawing
// that only looks whole.  TEXT is untrusted, and is parsed in a document that
// loads nothing.  Throw when nothing of it is SVG.
function sanitiseDrawing(text) {
  const svg = DOMPurify.sanitize(text, drawingPolicy).querySelector('svg');
  if (!svg) throw new Error('This diagram has no drawing that the page can show.');
  const lost = DOMPurify.removed.some(({ element }) => element?.localName === 'foreignObject');
  return { svg, note: lost ? 'Some labels of this diagram cannot be shown: the page draws SVG text alone.' : '' };
}

// Give each diagram of main the drawing of the page's current look.  One
// pass runs at a time, in a queue that each call joins; a diagram's failure
// is its own, and a pass's shows beneath every diagram.  Mermaid is loaded at
// the first diagram only, and again at the next call if it could not be
// fetched.  A script that ran and set no global is not run again: an asset's
// address gives the same file for as long as the page lives.
export function draw() {
  if (!document.documentElement.hasAttribute('data-mermaid')) return;
  // An edit makes a new node of a diagram it changes.  When as many diagrams
  // went as came, each new one shows the drawing of the one gone at its place
  // in their order, until it has its own, or for good if that fails; otherwise
  // each starts from its code.  So one deleted and another added elsewhere pair.
  const gone = diagramsShown.filter((pre) => !pre.isConnected).map((pre) => diagrams.get(pre).svg);
  diagramsShown = [...main.querySelectorAll('pre.mermaid')];
  const fresh = diagramsShown.filter((pre) => !diagrams.has(pre));
  const previous = gone.length === fresh.length ? gone : [];
  fresh.forEach((pre, index) => {
    diagrams.set(pre, { source: pre.textContent, code: [...pre.childNodes], svg: previous[index] });
    showDiagram(pre);
  });
  drawQueue = drawQueue.then(async () => {
    if (diagramsShown.length === 0) return;
    const mermaid = await (mermaidLoaded ??= new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = new URL('../mermaid.js', import.meta.url);
      script.onload = () => {
        if (globalThis.mermaid) resolve(globalThis.mermaid);
        else {
          script.remove();
          reject(new Error('The Mermaid script sets no global mermaid.'));
        }
      };
      script.onerror = () => {
        script.remove();
        mermaidLoaded = undefined;
        reject(new Error('The Mermaid script did not load.'));
      };
      document.head.append(script);
    }));
    // Mermaid's theme takes colours alone, so each --imp-* is resolved here.
    const probe = document.body.appendChild(document.createElement('span'));
    const look = {
      fontFamily: getComputedStyle(main).fontFamily,
      themeVariables: {
        darkMode: document.documentElement.dataset.appearance === 'dark',
        dropShadow: 'none',
        ...Object.fromEntries(Object.entries(themeColours).map(([name, token]) => {
          probe.style.color = `var(--imp-${token})`;
          return [name, getComputedStyle(probe).color];
        })),
      },
    };
    probe.remove();
    mermaid.initialize({
      ...look,
      startOnLoad: false,
      securityLevel: 'strict',
      suppressErrorRendering: true,
      theme: 'base',
      htmlLabels: false,
      flowchart: { htmlLabels: false },
      // Mermaid's sanitiser is what keeps a meta refresh out of the live page,
      // where it puts maths while drawing, so no document may loosen it.
      secure: [...mermaid.mermaidAPI.defaultConfig.secure, 'theme', 'themeVariables', 'themeCSS',
               'fontFamily', 'htmlLabels', 'flowchart', 'darkMode', 'dompurifyConfig'],
    });
    for (const pre of diagramsShown) {
      const diagram = diagrams.get(pre);
      const key = fnv1a(JSON.stringify([diagram.source, look]));
      if (diagram.key === key) continue;
      diagram.key = key;
      try {
        if (!drawings.has(key)) {
          drawCount += 1;
          const { svg } = await Promise.race([
            mermaid.render(`imprimeur-diagram-${drawCount}`, diagram.source),
            new Promise((resolve, reject) => {
              setTimeout(reject, drawingDeadline, new Error('This diagram took too long to draw.'));
            }),
          ]);
          drawings.set(key, sanitiseDrawing(svg));
          if (drawings.size > drawingsLimit) drawings.delete(drawings.keys().next().value);
        }
        const drawing = drawings.get(key);
        diagram.svg = drawing.svg.cloneNode(true);
        showDiagram(pre, drawing.note);
      } catch (error) {
        showDiagram(pre, error.message);
      }
    }
  }).catch((error) => {
    console.error(error);
    for (const pre of diagramsShown) showDiagram(pre, error.message);
  });
}
