;;; imprimeur-skin-minitel-test.el --- Tests of the skin Minitel  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 026:
;;
;; "An 80-column frame, row 0, mosaic rules, a working key bar, every colour from Emacs by
;; default": the manifest's defaults and choices, by hand from the workbench's params.json:
;; palette (emacs by default, videotex, greys), columns (80, 40), keys (fixed, end, off).
;; `imprimeur-skin' at `auto' starts in Minitel once the package is installed.
;;
;; Acceptance 3: on real pandoc, row 0, the frame, the key bar and its keys work in Chromium;
;; a key is exact in case; DEL and q are the page's when it takes them, and answer false so
;; that Emacs runs its own when it declines them.  The per-view keymap's half is in
;; tests/imprimeur/imprimeur-xwidget-test.el, on stand-ins, and in `make smoke-xwidget'.
;; Acceptance 4: each option changes what it says, alone; the lowest contrast is at least
;; 4.5:1 on a light, a dark and a mid-grey theme, in each palette, and with the appearance
;; forced against the ground, as `imprimeur-appearance' may.
;;
;; Plan 003, "Minitel on the palette": each colour is the palette's, the background
;; --emacs-bg, the code panes' --emacs-code-bg, the foreground --emacs-fg, the muted text
;; --emacs-muted, links --emacs-link, and the code's keywords, strings, comments, constants,
;; functions and types --emacs-kw, -str, -com, -const, -fn and -type, and the background of
;; its alerts --emacs-warn, like its error colour, when the colour is past the floor of
;; lightness that the ground asks for; where the palette gives no colour, Minitel's own light
;; or dark one stands in, chosen by the palette's appearance whatever the reader prefers, or
;; by prefers-color-scheme before a palette arrives, and an alert takes the error colour.
;; Plan 003, acceptance 5, as Minitel completed has it: in an Org document as in a Markdown
;; one, h1 to h6, p, li, pre and code share one font list, the default face's family then
;; monospace; h3 to code share one size, and h1 and h2 twice it; the headings' colours are
;; --emacs-h1 to --emacs-h6 past the floor, the third level's as its band's background, and
;; a keyword's the keyword colour.
;;
;; Plan 008, whose rulings stand, "Minitel's bold and italic" and "Minitel leaves tokens
;; unread", with acceptance 2: with a theme whose keyword is bold and whose string is italic,
;; .kw and .st have those computed styles, in one family and one size, and a theme giving
;; neither leaves the look where only comments are italic.  Each of pandoc's token classes
;; that Minitel paints takes the colour, the weight and the slant of its own token of the
;; palette, a builtin's and a documentation comment's included, and without them the weight
;; and slant of the text around it, except comments and documentation, which are italic.
;;
;; The trial's report: q turns C to F, which holds what Emacs renders, and back to C shows
;; it; g at F shows the latest and stays at F; once the session has ended, F stays, whatever
;; is pressed or clicked, and g and e do nothing.  SOMMAIRE: digits, Backspace, a number that
;; matches nothing said so, Esc, and Enter on the entry that has the focus, into which the
;; screen moves it.  In each column of the bar, the chips end together.
;;
;; The tests load Minitel in a registry of their own, as the other tests see the plain page.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur-test-themes)
(require 'imprimeur)

(defconst imprimeur-skin-minitel-test-file
  (expand-file-name "imprimeur-skin-minitel/imprimeur-skin-minitel.el" repo-test-root)
  "The skin's main file.")

(defconst imprimeur-skin-minitel-test-srgb
  "const pen = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
const srgb = (colour) => {
  pen.clearRect(0, 0, 1, 1);
  pen.fillStyle = colour;
  pen.fillRect(0, 0, 1, 1);
  return [...pen.getImageData(0, 0, 1, 1).data].slice(0, 3);
};
const luminance = (colour) => {
  const [red, green, blue] = srgb(colour).map((value) => {
    const channel = value / 255;
    return channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
};
const contrast = (one, other) => {
  const [light, dark] = [luminance(one), luminance(other)].sort((a, b) => b - a);
  return (light + 0.05) / (dark + 0.05);
};
const token = (name) => {
  const probe = document.body.appendChild(document.createElement('span'));
  probe.style.color = `var(--imp-${name})`;
  const colour = getComputedStyle(probe).color;
  probe.remove();
  return colour;
};"
  "JavaScript giving a colour of any syntax in sRGB, the contrast of WCAG 2, and a token's colour.")

(defun imprimeur-skin-minitel-test-eval (browser body)
  "Return the value of the expression BODY in BROWSER's page, with the sRGB helpers."
  (imprimeur-test-cdp-eval browser (format "(() => { %s\nreturn %s; })()" imprimeur-skin-minitel-test-srgb body)))

(defun imprimeur-skin-minitel-test-near-p (one other)
  "Return non-nil when the colours ONE and OTHER, vectors of channels, differ by 2 at most.
Going through OKLCH and back may move a channel so far."
  (seq-every-p (lambda (pair) (<= (abs (- (car pair) (cdr pair))) 2))
               (cl-mapcar #'cons one other)))

(defun imprimeur-skin-minitel-test-key (browser key &optional text code modifiers)
  "Press KEY in BROWSER's page, a real key event: TEXT, its virtual key CODE and MODIFIERS."
  (dolist (type (if text '("keyDown" "keyUp") '("rawKeyDown" "keyUp")))
    (imprimeur-test-cdp-call browser "Input.dispatchKeyEvent"
                             `(:type ,type :key ,key
                                     ,@(and (equal type "keyDown") text (list :text text))
                                     ,@(and code (list :windowsVirtualKeyCode code))
                                     ,@(and modifiers (list :modifiers modifiers))))))

(defmacro imprimeur-skin-minitel-test-with (spec &rest body)
  "Run BODY with Minitel as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT, in
the selected Emacs window, in `imprimeur-mode'; BROWSER shows its page, at
1200 by 800, once the module has mounted and a revision shows."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'minitel)
              (imprimeur-skin-options nil)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (find-file-noselect (expand-file-name ,file root))))
         (load imprimeur-skin-minitel-test-file nil t)
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer ,buffer)
               (imprimeur-test-cdp-with-browser ,browser
                 (imprimeur-test-cdp-call ,browser "Emulation.setDeviceMetricsOverride"
                                          '(:width 1200 :height 800 :deviceScaleFactor 1 :mobile :false))
                 (imprimeur-mode 1)
                 (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
                 (imprimeur-test-wait-for
                  (lambda () (imprimeur-test-cdp-eval ,browser "document.documentElement.dataset.revision")))
                 (imprimeur-test-cdp-wait ,browser "document.getElementById('minitel-keys') !== null")
                 ,@body))
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defun imprimeur-skin-minitel-test-wait-revision (browser revision)
  "Wait until BROWSER's page shows REVISION or a later one."
  (imprimeur-test-cdp-wait browser (format "Number(document.documentElement.dataset.revision) >= %d" revision)))

(defun imprimeur-skin-minitel-test-session-revision (buffer revision)
  "Wait until the session of BUFFER has rendered REVISION."
  (imprimeur-test-wait-for
   (lambda () (= (imprimeur--session-revision (buffer-local-value 'imprimeur--session buffer)) revision))))

(defconst imprimeur-skin-minitel-test-inks
  "* Heading\n\nProse, ~code~ and a [[https://example.org/][link]].\n\n#+begin_src python\ndef f():  # Comment\n    return \"text\", 1\n#+end_src\n"
  "An Org document that holds Minitel's inks.")

(defun imprimeur-skin-minitel-test-lowest-contrast (browser)
  "Return the lowest contrast of the text of BROWSER's page on the ground it sits on.
Each element with text of its own, on its nearest ground that is painted."
  (imprimeur-skin-minitel-test-eval browser "(() => {
  const ground = (element) => {
    for (let at = element; at; at = at.parentElement) {
      const colour = getComputedStyle(at).backgroundColor;
      if (!/, 0\\)$|^transparent$/.test(colour)) return colour;
    }
    return getComputedStyle(document.documentElement).backgroundColor;
  };
  const texts = [...document.querySelectorAll('main *, #minitel-row0 *, #minitel-keys *')]
    .filter((element) => [...element.childNodes].some((node) => node.nodeType === 3 && node.textContent.trim()));
  return Math.min(...texts.map((element) => contrast(getComputedStyle(element).color, ground(element))));
})()"))

;;;; The package

(ert-deftest imprimeur-skin-minitel-registers-from-its-autoloads-alone ()
  ;; And `auto' then means it, while with no package it means the plain page.
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-minitel-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-minitel-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-minitel)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S auto=%s\" (and (imprimeur-skin-get \"minitel\") t) (imprimeur-skin-initial-name)))"))))
    (should (equal (car result) 0))
    (should (string-match-p "MARK\\(.\\|\n\\)*before=nil after=t auto=minitel\\'" (cdr result))))
  (let ((result (repo-test-emacs
                 (list "-L" (expand-file-name "imprimeur" repo-test-root)
                       "--eval" "(require 'imprimeur-skin)"
                       "--eval" "(princ (imprimeur-skin-initial-name))"))))
    (should (equal (car result) 0))
    (should (string-suffix-p "base" (cdr result)))))

(ert-deftest imprimeur-skin-minitel-keeps-the-owner-s-defaults-and-choices ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-minitel-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "minitel"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "Minitel"))
      (should (equal (plist-get manifest :module) "page.mjs"))
      (should (eq (plist-get manifest :auto) t))
      (should-not (plist-get manifest :filters))
      (should (equal (plist-get manifest :keys)
                     '("s" "p" "n" "?" "e" "g" "q" "0" "1" "2" "3" "4" "5" "6" "7" "8" "9"
                       "Enter" "Backspace" "Escape")))
      (pcase-dolist (`(,id ,default . ,choices)
                     '((palette "emacs" "emacs" "videotex" "greys")
                       (columns "80" "80" "40")
                       (keys "fixed" "fixed" "end" "off")))
        (ert-info ((symbol-name id))
          (should (equal (plist-get (alist-get id options) :default) default))
          (should (equal (mapcar #'car (plist-get (alist-get id options) :choices)) choices))))
      (should (equal (mapcar #'car options) '(palette columns keys))))))

(ert-deftest imprimeur-skin-minitel-is-chosen-by-the-configuration-of-its-readme ()
  (let* ((readme (with-temp-buffer
                   (insert-file-contents (expand-file-name "imprimeur-skin-minitel/README.md" repo-test-root))
                   (buffer-string)))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'minitel\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-minitel-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-minitel)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"minitel\" (imprimeur-skin-get \"minitel\") (imprimeur-skin-configured \"minitel\" (imprimeur-skin-get \"minitel\")) nil))"))))
    (should (equal (car result) 0))
    ;; Every option at its default, so the root stays bare.
    (should (string-suffix-p "minitel[]" (cdr result)))))

;;;; The screen

(ert-deftest imprimeur-skin-minitel-sets-row-0-the-frame-and-the-bar ()
  (imprimeur-skin-minitel-test-with
      (_buffer browser "doc.org"
               (concat "#+TITLE: A title\n\n* One\n\n" (apply #'concat (make-list 80 "Prose.\n\n"))
                       "-----\n\n* Two\n\n" (apply #'concat (make-list 80 "Prose.\n\n"))))
    (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.skin") "minitel"))
    (should (equal (imprimeur-test-cdp-eval browser "[...document.body.children].map((element) => element.localName).join()")
                   "div,header,div,main,div,nav"))
    ;; Eighty columns, in a frame stuck to the view, drawn over the page by no one's click.
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const ch = document.body.appendChild(document.createElement('span'));
  ch.style.cssText = 'position:absolute;inline-size:1ch';
  const cell = ch.getBoundingClientRect().width;
  ch.remove();
  const frame = getComputedStyle(document.body, '::before');
  return [Math.round(document.body.getBoundingClientRect().width / cell), frame.position, frame.pointerEvents, frame.borderTopWidth];
})()")
                   [84 "sticky" "none" "1px"]))
    ;; Row 0 says where the reader is, and the keys are the terminal's, in its order.
    (imprimeur-test-cdp-wait browser "document.querySelector('.minitel-pos').textContent !== ''")
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.minitel-letter').textContent") "C"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.minitel-pos').textContent") "0%"))
    (should (equal (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('#minitel-keys button > span')].map((name) => name.textContent)")
                   ["SOMMAIRE" "ANNULATION" "RETOUR" "RÉPÉTITION" "GUIDE" "CORRECTION" "SUITE" "ENVOI" "CONNEXION/FIN"]))
    ;; Separated sextants close the title, and rule a line.
    (dolist (selector '("#imprimeur-title" "main hr"))
      (ert-info (selector)
        (should (string-search "\U0001CE70" (imprimeur-test-cdp-eval
                                             browser (format "getComputedStyle(document.querySelector(%S), '%s').content"
                                                             selector (if (equal selector "main hr") "::before" "::after")))))))
    ;; They stay on the screen, and row 0 follows.
    (imprimeur-test-cdp-eval browser "window.scrollTo({ top: 1400, behavior: 'instant' })")
    (imprimeur-test-cdp-wait browser "document.querySelector('.minitel-crumb').textContent.includes('One')")
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const row = document.getElementById('minitel-row0').getBoundingClientRect();
  const bar = document.getElementById('minitel-keys').getBoundingClientRect();
  return [Math.round(row.top), Math.round(bar.bottom) === innerHeight, document.documentElement.scrollWidth === document.documentElement.clientWidth];
})()")
                   [0 t t]))
    (should (string-prefix-p "A title › " (imprimeur-test-cdp-eval browser "document.querySelector('.minitel-crumb').textContent")))
    (should-not (equal (imprimeur-test-cdp-eval browser "document.querySelector('.minitel-pos').textContent") "0%"))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-minitel-ends-its-chips-together ()
  (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" "First.\n")
    (imprimeur-test-cdp-call browser "Emulation.setDeviceMetricsOverride"
                             '(:width 800 :height 600 :deviceScaleFactor 1 :mobile :false))
    ;; The bar's two rows: SOMMAIRE over GUIDE, and so on.
    (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const right = [...document.querySelectorAll('#minitel-keys kbd')].map((chip) => Math.round(chip.getBoundingClientRect().right));
  return [0, 1, 2, 3].map((column) => right[column] === right[column + 4]);
})()")
                   [t t t t]))))

(ert-deftest imprimeur-skin-minitel-aligns-clear-of-row-0 ()
  ;; A block that Emacs brings to the top stands under row 0, and not behind it.
  (imprimeur-skin-minitel-test-with
      (buffer browser "doc.org" (concat "* One\n\n" (apply #'concat (make-list 80 "Prose.\n\n"))))
    (with-current-buffer buffer
      (goto-char (point-min))
      (forward-line 80)
      (imprimeur-jump))
    (imprimeur-test-cdp-wait browser "document.querySelector('.imprimeur-flash') !== null")
    (should (eq (imprimeur-test-cdp-eval browser "(() => {
  const under = document.querySelector('.imprimeur-flash').getBoundingClientRect().top;
  const row = document.getElementById('minitel-row0').getBoundingClientRect().bottom;
  return under >= row - 2 && under <= row + 2;
})()")
                t))))

;;;; The keys

(defconst imprimeur-skin-minitel-test-state
  "[document.querySelector('.minitel-letter').textContent, document.getElementById('minitel-row0').dataset.following,
    Number(document.documentElement.dataset.revision)]"
  "JavaScript giving what row 0 says: the letter, the state and the revision shown.")

(ert-deftest imprimeur-skin-minitel-holds-at-f-and-shows-at-c ()
  (imprimeur-skin-minitel-test-with (buffer browser "doc.org" "First.\n")
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-minitel-test-state) ["C" "on" 1]))
    (imprimeur-skin-minitel-test-key browser "q" "q")
    (imprimeur-test-cdp-wait browser "document.getElementById('minitel-row0').dataset.following === 'off'")
    (with-current-buffer buffer (goto-char (point-max)) (insert "\nSecond.\n"))
    (imprimeur-skin-minitel-test-session-revision buffer 2)
    (accept-process-output nil 0.5)
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-minitel-test-state) ["F" "off" 1]))
    ;; RÉPÉTITION at F shows the latest, and stays at F.
    (imprimeur-skin-minitel-test-key browser "g" "g")
    (imprimeur-skin-minitel-test-wait-revision browser 2)
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-minitel-test-state) ["F" "off" 2]))
    (with-current-buffer buffer (goto-char (point-max)) (insert "\nThird.\n"))
    (imprimeur-skin-minitel-test-session-revision buffer 3)
    ;; Back to C, what waited shows.
    (imprimeur-skin-minitel-test-key browser "q" "q")
    (imprimeur-skin-minitel-test-wait-revision browser 3)
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-minitel-test-state) ["C" "on" 3]))
    ;; And by a click on the letter, or on the key of the bar.
    (imprimeur-test-cdp-click browser "document.querySelector('.minitel-letter')")
    (imprimeur-test-cdp-wait browser "document.querySelector('.minitel-letter').textContent === 'F'")
    (imprimeur-test-cdp-click browser "document.querySelector('#minitel-keys button:last-child')")
    (imprimeur-test-cdp-wait browser "document.querySelector('.minitel-letter').textContent === 'C'")
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-minitel-makes-the-page-again-at-c ()
  (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" "First.\n")
    (imprimeur-test-cdp-eval browser "window.__kept = 'kept'")
    (imprimeur-skin-minitel-test-key browser "g" "g")
    (imprimeur-test-cdp-wait browser "window.__kept === undefined && document.getElementById('minitel-keys') !== null")))

(ert-deftest imprimeur-skin-minitel-stays-at-f-once-the-session-has-ended ()
  (imprimeur-skin-minitel-test-with (buffer browser "doc.org" "First.\n")
    (imprimeur-test-cdp-eval browser "window.__kept = 'kept'")
    (with-current-buffer buffer (imprimeur-mode -1))
    (imprimeur-test-cdp-wait browser "document.getElementById('minitel-row0').dataset.following === 'ended'")
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-minitel-test-state) ["F" "ended" 1]))
    (imprimeur-skin-minitel-test-key browser "q" "q")
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-minitel-test-state) ["F" "ended" 1]))
    (imprimeur-test-cdp-click browser "document.querySelector('.minitel-letter')")
    (accept-process-output nil 0.2)
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-minitel-test-state) ["F" "ended" 1]))
    (should-not (string-search "follows" (imprimeur-test-cdp-eval browser "document.querySelector('.minitel-letter').title")))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.minitel-letter').ariaDisabled") "true"))
    ;; What needs Emacs does nothing, and each declines, so q would then quit a view.
    (imprimeur-skin-minitel-test-key browser "g" "g")
    (imprimeur-skin-minitel-test-key browser "e" "e")
    (accept-process-output nil 0.5)
    (should (equal (imprimeur-test-cdp-eval browser "window.__kept") "kept"))
    (dolist (key '("q" "g" "e"))
      (ert-info (key)
        (should-not (imprimeur-test-cdp-eval browser (format "window.imprimeur.key(%S)" key)))))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-minitel-asks-nothing-of-a-session-that-has-ended ()
  ;; A revision waits at F when the session ends: F stays, and nothing fetches it from a
  ;; session that has gone.
  (imprimeur-skin-minitel-test-with (buffer browser "doc.org" "First.\n")
    (imprimeur-skin-minitel-test-key browser "q" "q")
    (imprimeur-test-cdp-wait browser "document.getElementById('minitel-row0').dataset.following === 'off'")
    (with-current-buffer buffer (goto-char (point-max)) (insert "\nSecond.\n"))
    (imprimeur-skin-minitel-test-session-revision buffer 2)
    (accept-process-output nil 0.3)
    (with-current-buffer buffer (imprimeur-mode -1))
    (imprimeur-test-cdp-wait browser "document.getElementById('minitel-row0').dataset.following === 'ended'")
    (accept-process-output nil 0.3)
    (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-minitel-test-state) ["F" "ended" 1]))
    (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))))

(ert-deftest imprimeur-skin-minitel-answers-the-keys-of-sommaire ()
  (imprimeur-skin-minitel-test-with
      (_buffer browser "doc.org"
               (let ((prose (apply #'concat (make-list 60 "Prose.\n\n"))))
                 (concat "* One\n" prose "* Two\n" prose "* Three\n" prose)))
    (let ((screen "document.getElementById('minitel-screen')?.dataset.kind ?? null")
          (prompt "document.querySelector('.minitel-prompt')?.textContent ?? null")
          (focus "document.activeElement.textContent")
          (crumb "document.querySelector('.minitel-crumb').textContent"))
      (imprimeur-skin-minitel-test-key browser "s" "s")
      (should (equal (imprimeur-test-cdp-eval browser screen) "SOMMAIRE"))
      ;; The focus moves in, on the first entry.
      (should (equal (imprimeur-test-cdp-eval browser focus) "One"))
      (imprimeur-skin-minitel-test-key browser "1" "1")
      (imprimeur-skin-minitel-test-key browser "2" "2")
      (should (string-search "12" (imprimeur-test-cdp-eval browser prompt)))
      (imprimeur-skin-minitel-test-key browser "Backspace" nil 8)
      (should (string-search ": 1█" (imprimeur-test-cdp-eval browser prompt)))
      ;; A number that matches no entry is said so, and the screen stays.
      (imprimeur-skin-minitel-test-key browser "9" "9")
      (imprimeur-skin-minitel-test-key browser "Enter" "\r" 13)
      (should (string-search "19" (imprimeur-test-cdp-eval browser prompt)))
      (should (equal (imprimeur-test-cdp-eval browser screen) "SOMMAIRE"))
      (imprimeur-skin-minitel-test-key browser "Escape" nil 27)
      (should-not (imprimeur-test-cdp-eval browser screen))
      ;; The case is exact: S is no SOMMAIRE.
      (imprimeur-skin-minitel-test-key browser "S" "S" nil 8)
      (should-not (imprimeur-test-cdp-eval browser screen))
      ;; Enter on the entry that has the focus.
      (imprimeur-skin-minitel-test-key browser "s" "s")
      (imprimeur-skin-minitel-test-key browser "Tab" nil 9)
      (should (equal (imprimeur-test-cdp-eval browser focus) "Two"))
      (imprimeur-skin-minitel-test-key browser "Enter" "\r" 13)
      (imprimeur-test-cdp-wait browser (format "%s.includes('Two')" crumb) 5)
      (should-not (imprimeur-test-cdp-eval browser screen))
      ;; By number, as the prompt asks.
      (imprimeur-skin-minitel-test-key browser "s" "s")
      (imprimeur-skin-minitel-test-key browser "3" "3")
      (imprimeur-skin-minitel-test-key browser "Enter" "\r" 13)
      (imprimeur-test-cdp-wait browser (format "%s.includes('Three')" crumb) 5)
      ;; The same key closes it, and the bar opens it.
      (imprimeur-skin-minitel-test-key browser "s" "s")
      (imprimeur-skin-minitel-test-key browser "s" "s")
      (should-not (imprimeur-test-cdp-eval browser screen))
      (imprimeur-test-cdp-click browser "document.querySelector('#minitel-keys button')")
      (should (equal (imprimeur-test-cdp-eval browser screen) "SOMMAIRE"))
      (imprimeur-skin-minitel-test-key browser "Escape" nil 27))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-minitel-moves-by-headings-and-says-the-guide ()
  (imprimeur-skin-minitel-test-with
      (_buffer browser "doc.org"
               (let ((prose (apply #'concat (make-list 60 "Prose.\n\n"))))
                 (concat "* One\n" prose "* Two\n" prose "* Three\n" prose)))
    (let ((crumb "document.querySelector('.minitel-crumb').textContent"))
      (pcase-dolist (`(,key ,title) '(("n" "One") ("n" "Two") ("n" "Three") ("p" "Two")))
        (ert-info ((format "%s to %s" key title))
          (imprimeur-skin-minitel-test-key browser key key)
          (imprimeur-test-cdp-wait browser (format "%s.includes('%s')" crumb title) 5))))
    (imprimeur-skin-minitel-test-key browser "?" "?")
    (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('minitel-screen').dataset.kind") "GUIDE"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('#minitel-screen dt').length") 9))
    (should (string-search "Esc" (imprimeur-test-cdp-eval browser "document.getElementById('minitel-screen').textContent")))))

(ert-deftest imprimeur-skin-minitel-shares-its-keys-with-emacs ()
  ;; `imprimeur.key' is what the view asks: false gives the key its own command.
  (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" "* One\n\nProse.\n")
    (let ((press (lambda (key) (imprimeur-test-cdp-eval browser (format "window.imprimeur.key(%S)" key)))))
      ;; Nothing typed and no screen: DEL scrolls back, a digit is a prefix, Esc and RET
      ;; are Emacs's.
      (dolist (key '("Backspace" "1" "Escape" "Enter"))
        (ert-info (key) (should-not (funcall press key))))
      ;; On the screen, each is the page's.
      (should (eq (funcall press "s") t))
      (should (eq (funcall press "1") t))
      (should (eq (funcall press "Backspace") t))
      ;; And once it has rubbed out the digit, DEL is Emacs's again.
      (should-not (funcall press "Backspace"))
      (should (eq (funcall press "Escape") t))
      (should-not (funcall press "Escape"))
      ;; The terminal's own, always the page's while Emacs is there.
      (dolist (key '("p" "n" "?" "?" "q" "q"))
        (ert-info (key) (should (eq (funcall press key) t))))
      ;; Neither another case nor what the skin has not declared.
      (dolist (key '("Q" "S" "x"))
        (ert-info (key) (should-not (funcall press key)))))))

(ert-deftest imprimeur-skin-minitel-goes-to-the-source-under-row-0 ()
  (let ((messages nil))
    (imprimeur-skin-minitel-test-with
        (buffer browser "doc.org" (concat "* One\n\n" (apply #'concat (make-list 80 "Prose.\n\n"))))
      (cl-letf* ((original (symbol-function 'message))
                 ((symbol-function 'message)
                  (lambda (format-string &rest arguments)
                    (push (apply #'format format-string arguments) messages)
                    (apply original format-string arguments))))
        (imprimeur-test-cdp-eval browser "window.scrollTo({ top: 1000, behavior: 'instant' })")
        (let ((line (imprimeur-test-cdp-eval browser "(() => {
  const under = document.getElementById('minitel-row0').getBoundingClientRect().bottom + 22;
  return Number([...document.querySelectorAll('main > [data-line]')].find((block) => block.getBoundingClientRect().bottom > under).dataset.line);
})()")))
          (imprimeur-skin-minitel-test-key browser "e" "e")
          (imprimeur-test-wait-for (lambda () (= (with-current-buffer buffer (line-number-at-pos)) line)))
          (should-not (seq-find (lambda (message) (string-search "behind" message)) messages))
          ;; At F, behind the buffer, the echo area says so.
          (imprimeur-skin-minitel-test-key browser "q" "q")
          (with-current-buffer buffer (goto-char (point-max)) (insert "More.\n"))
          (imprimeur-skin-minitel-test-session-revision buffer 2)
          (imprimeur-skin-minitel-test-key browser "e" "e")
          (imprimeur-test-wait-for (lambda () (seq-find (lambda (message) (string-search "behind" message)) messages))))))))

(ert-deftest imprimeur-skin-minitel-leaves-nothing-after-a-swap ()
  (imprimeur-skin-minitel-test-with (buffer browser "doc.org" "First.\n")
    (with-current-buffer buffer (imprimeur-set-skin-option "palette" "greys"))
    (imprimeur-test-cdp-wait browser "document.documentElement.getAttribute('data-minitel-palette') === 'greys'")
    (imprimeur-skin-minitel-test-key browser "s" "s")
    (imprimeur-skin-minitel-test-key browser "q" "q")
    (with-current-buffer buffer (goto-char (point-max)) (insert "\nSecond.\n"))
    (imprimeur-skin-minitel-test-session-revision buffer 2)
    (accept-process-output nil 0.3)
    (with-current-buffer buffer (imprimeur-choose-skin "base"))
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.skin === 'base'")
    (should (equal (imprimeur-test-cdp-eval browser "[...document.body.children].map((element) => element.localName).join()")
                   "header,div,main,div"))
    (should-not (imprimeur-test-cdp-eval browser "document.documentElement.hasAttribute('data-minitel-palette')"))
    ;; F went with it: what waited shows, and its keys are gone.
    (imprimeur-skin-minitel-test-wait-revision browser 2)
    (should-not (imprimeur-test-cdp-eval browser "window.imprimeur.key('s')"))
    (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.body, '::before').content") "none"))
    (should-not (imprimeur-test-cdp-errors browser))))

;;;; The options

;; Plan 006: the page's minitocs stand beside Minitel's own SOMMAIRE, which stays as it
;; is, in a heading's text as in its keys.  Esc closes what the core opened, first, and
;; then Minitel's; the pill stands clear of row 0.
(ert-deftest imprimeur-skin-minitel-keeps-its-sommaire-beside-the-minitocs ()
  (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" "#+title: Doc\n\n* One\n** A\n** B\n* Two\n\nWords.\n")
    (let ((screen "document.getElementById('minitel-screen')?.dataset.kind ?? null")
          (popover "document.querySelector('.imprimeur-minitoc-popover').hidden")
          (press (lambda (key) (imprimeur-skin-minitel-test-key browser key key))))
      (should (eq (imprimeur-test-cdp-eval
                   browser "document.getElementById('minitel-row0').getBoundingClientRect().bottom
                            <= document.querySelector('.imprimeur-minitoc-pill').getBoundingClientRect().top")
                  t))
      (funcall press "s")
      (should (equal (imprimeur-test-cdp-eval browser screen) "SOMMAIRE"))
      (should (equal (imprimeur-test-cdp-eval
                      browser "[...document.querySelectorAll('#minitel-screen button')].filter((one) => one.textContent.includes('One')).length")
                     1))
      (funcall press "t")
      (should-not (imprimeur-test-cdp-eval browser popover))
      (should (equal (imprimeur-test-cdp-eval browser screen) "SOMMAIRE"))
      (imprimeur-skin-minitel-test-key browser "Escape")
      (should (eq (imprimeur-test-cdp-eval browser popover) t))
      (should (equal (imprimeur-test-cdp-eval browser screen) "SOMMAIRE"))
      (imprimeur-skin-minitel-test-key browser "Escape")
      (should-not (imprimeur-test-cdp-eval browser screen)))))

(defun imprimeur-skin-minitel-test-said (browser)
  "Return what each option decides of BROWSER's page, as an alist from the option.
The palette by the ground, the columns by how many cells the screen holds with its
margin, and the key bar by where it stands."
  (list (cons 'palette (imprimeur-test-cdp-eval browser "getComputedStyle(document.documentElement).backgroundColor"))
        (cons 'columns (imprimeur-test-cdp-eval browser "(() => {
  const ch = document.body.appendChild(document.createElement('span'));
  ch.style.cssText = 'position:absolute;inline-size:1ch';
  const cell = ch.getBoundingClientRect().width;
  ch.remove();
  return Math.round(document.body.getBoundingClientRect().width / cell);
})()"))
        (cons 'keys (imprimeur-test-cdp-eval browser "getComputedStyle(document.getElementById('minitel-keys')).display + ' ' + getComputedStyle(document.getElementById('minitel-keys')).position"))))

(defun imprimeur-skin-minitel-test-choose (buffer browser id value default)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it.
DEFAULT is its default, which the root does not hold."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-minitel-%s') === %s"
                   id (if (equal value default) "null" (format "%S" value)))))

(ert-deftest imprimeur-skin-minitel-changes-what-each-option-says-alone ()
  ;; A theme's own ground gives way to the palette's; the bar of 40 columns waits at the end
  ;; of the document, as the workbench's note says, as it no longer fits on two rows.
  (cl-letf (((symbol-function 'imprimeur-palette)
             (lambda (_buffer) (list :appearance "light" :css ":root {\n  --emacs-bg: #e0e0d0;\n  --emacs-bg-luminance: 0.7300;\n}\n"))))
    (imprimeur-skin-minitel-test-with (buffer browser "doc.org" "* One\n\nProse.\n")
      (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
      (let ((defaults (imprimeur-skin-minitel-test-said browser)))
        (should (equal defaults '((palette . "rgb(224, 224, 208)") (columns . 84) (keys . "block sticky"))))
        (pcase-dolist (`(,id ,value ,changes ,default)
                       '(("palette" "videotex" ((palette . "rgb(255, 255, 255)")) "emacs")
                         ("palette" "greys" ((palette . "rgb(244, 244, 242)")) "emacs")
                         ("columns" "40" ((columns . 44) (keys . "block static")) "80")
                         ("keys" "end" ((keys . "block static")) "fixed")
                         ("keys" "off" ((keys . "none sticky")) "fixed")))
          (ert-info ((format "%s %s" id value))
            (imprimeur-skin-minitel-test-choose buffer browser id value default)
            (let ((expected (copy-alist defaults)))
              (pcase-dolist (`(,property . ,said) changes)
                (setf (alist-get property expected) said))
              (should (equal (cl-sort (imprimeur-skin-minitel-test-said browser) #'string< :key (lambda (entry) (symbol-name (car entry))))
                             (cl-sort expected #'string< :key (lambda (entry) (symbol-name (car entry)))))))
            (imprimeur-skin-minitel-test-choose buffer browser id default default)
            (should (equal (imprimeur-skin-minitel-test-said browser) defaults))))
        ;; The keys answer, whichever way the bar stands.
        (imprimeur-skin-minitel-test-choose buffer browser "keys" "off" "fixed")
        (should (eq (imprimeur-test-cdp-eval browser "window.imprimeur.key('?')") t))
        (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('minitel-screen').dataset.kind") "GUIDE"))))))

(ert-deftest imprimeur-skin-minitel-greys-pictures-only-in-its-greys ()
  (imprimeur-skin-minitel-test-with (buffer browser "doc.md" "![](pic.png)\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('main img') !== null")
    (let ((filter "getComputedStyle(document.querySelector('main img')).filter"))
      (should-not (string-search "grayscale" (imprimeur-test-cdp-eval browser filter)))
      (imprimeur-skin-minitel-test-choose buffer browser "palette" "greys" "emacs")
      (should (string-search "grayscale" (imprimeur-test-cdp-eval browser filter))))))

;;;; The colours

(defconst imprimeur-skin-minitel-test-grounds
  '(("light" "#ffffff") ("light" "#f7f7f7") ("dark" "#1d1f21") ("dark" "#000000")
    ("dark" "#808080") ("light" "#777777") ("dark" "#8a8a8a"))
  "Grounds of a light, a dark and a mid-grey theme, each with its appearance.")

(ert-deftest imprimeur-skin-minitel-reads-on-a-light-a-dark-and-a-mid-grey-theme ()
  ;; Each palette, on each ground, with colours that the ground alone would not carry:
  ;; a night theme's by day, and a day theme's by night.
  (pcase-dolist (`(,appearance ,ground) imprimeur-skin-minitel-test-grounds)
    (let ((palette (list :appearance appearance
                         :css (format ":root {\n  --emacs-bg: %s;\n  --emacs-bg-luminance: %s;\n  --emacs-fg: #c5c8c6;\n  --emacs-muted: #969896;\n  --emacs-link: #eab700;\n  --emacs-kw: #718c00;\n  --emacs-str: #eab700;\n  --emacs-com: #8e908c;\n  --emacs-h1: #81a2be;\n  --emacs-h2: #f0c674;\n  --emacs-h3: #4d4d4c;\n  --emacs-code-bg: #222427;\n  --emacs-mode-line-bg: %s;\n  --emacs-mode-line-fg: #c5c8c6;\n}\n"
                                      ground (imprimeur-palette-luminance ground) ground))))
      (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
        (imprimeur-skin-minitel-test-with (buffer browser "doc.org" imprimeur-skin-minitel-test-inks)
          (imprimeur-test-cdp-wait browser (format "document.documentElement.dataset.appearance === '%s'" appearance))
          (pcase-dolist (`(,value . ,_) '(("emacs") ("videotex") ("greys")))
            (ert-info ((format "%s %s %s" appearance ground value))
              (imprimeur-skin-minitel-test-choose buffer browser "palette" value "emacs")
              ;; The bar comes first in row 0's own colours, which a theme's mode line may
              ;; leave unreadable: the floor binds what the page chooses, so its pair of
              ;; a theme's own is left out here and judged below.
              (should (>= (imprimeur-skin-minitel-test-eval browser "(() => {
  const ground = (element) => {
    for (let at = element; at; at = at.parentElement) {
      const colour = getComputedStyle(at).backgroundColor;
      if (!/, 0\\)$|^transparent$/.test(colour)) return colour;
    }
    return getComputedStyle(document.documentElement).backgroundColor;
  };
  const texts = [...document.querySelectorAll('main *')]
    .filter((element) => [...element.childNodes].some((node) => node.nodeType === 3 && node.textContent.trim()));
  return Math.min(...texts.map((element) => contrast(getComputedStyle(element).color, ground(element))));
})()")
                          4.5)))))))))

(ert-deftest imprimeur-skin-minitel-reads-its-bars-where-the-theme-gives-no-mode-line ()
  ;; With no mode line, or a pair that the theme makes readable, row 0 and the bar read too.
  (pcase-dolist (`(,appearance ,css)
                 '(("dark" ":root {\n  --emacs-bg: #808080;\n  --emacs-bg-luminance: 0.2159;\n  --emacs-fg: #c5c8c6;\n}\n")
                   ("light" ":root {\n  --emacs-bg: #ffffff;\n  --emacs-bg-luminance: 1.0000;\n  --emacs-fg: #4d4d4c;\n}\n")
                   ("dark" ":root {\n  --emacs-bg: #1d1f21;\n  --emacs-bg-luminance: 0.0135;\n  --emacs-fg: #c5c8c6;\n  --emacs-mode-line-bg: #444444;\n  --emacs-mode-line-fg: #ffffff;\n}\n")))
    (ert-info (css)
      (let ((palette (list :appearance appearance :css css)))
        (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
          (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" imprimeur-skin-minitel-test-inks)
            (imprimeur-test-cdp-wait browser (format "document.documentElement.dataset.appearance === '%s'" appearance))
            (imprimeur-test-cdp-wait browser "document.querySelector('.minitel-crumb').textContent !== ''")
            (should (>= (imprimeur-skin-minitel-test-lowest-contrast browser) 4.5))))))))

(ert-deftest imprimeur-skin-minitel-reads-when-the-appearance-belies-the-ground ()
  (pcase-dolist (`(,theme ,forced)
                 '((imprimeur-test-night light) (imprimeur-test-day dark)))
    (ert-info ((symbol-name theme))
      (enable-theme theme)
      (unwind-protect
          (let ((imprimeur-appearance forced))
            (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" imprimeur-skin-minitel-test-inks)
              (imprimeur-test-cdp-wait browser (format "document.documentElement.dataset.appearance === '%s'" forced))
              (imprimeur-test-cdp-wait browser "document.querySelector('.minitel-crumb').textContent !== ''")
              (should (>= (imprimeur-skin-minitel-test-lowest-contrast browser) 4.5))))
        (disable-theme theme)))))

(ert-deftest imprimeur-skin-minitel-takes-its-colours-from-the-palette ()
  ;; Each colour past the floor of a dark ground, so that each stays what it is.
  (let* ((css ":root {
  --emacs-bg: #000001; --emacs-bg-luminance: 0.0000; --emacs-fg: #f0f0f2; --emacs-muted: #f0f0f3; --emacs-link: #f0f0f4;
  --emacs-kw: #f0f0f5; --emacs-str: #f0f0f6; --emacs-com: #f0f0f7; --emacs-const: #f0f0f8;
  --emacs-fn: #f0f0f9; --emacs-type: #f0f0fa; --emacs-warn: #f0f0fb;
  --emacs-code-bg: #00000c;
}\n")
         (palette (list :appearance "dark" :css css))
         (pane "getComputedStyle(document.querySelector('main pre')).backgroundColor"))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" "* Heading\n#+begin_src python\n# TODO\n#+end_src\n")
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
        (should (imprimeur-skin-minitel-test-near-p
                 (imprimeur-skin-minitel-test-eval
                  browser "srgb(getComputedStyle(document.querySelector('main .al')).backgroundColor)")
                 [240 240 251]))
        (should (imprimeur-skin-minitel-test-near-p
                 (imprimeur-skin-minitel-test-eval browser (format "srgb(%s)" pane)) [0 0 12]))
        (cl-mapc (lambda (got wanted) (should (imprimeur-skin-minitel-test-near-p got wanted)))
                 (imprimeur-skin-minitel-test-eval
                  browser "['background', 'foreground', 'muted', 'link', 'code-background', 'keyword', 'string',
          'comment', 'constant', 'function', 'type', 'error'].map((name) => srgb(token(name)))")
                 '([0 0 1] [240 240 242] [240 240 243] [240 240 244] [0 0 12] [240 240 245] [240 240 246]
                   [240 240 247] [240 240 248] [240 240 249] [240 240 250] [240 240 251]))
        ;; Without a colour of its own, a pane still stands apart from the background.
        (setq palette (list :appearance "dark" :css (string-replace "  --emacs-code-bg: #00000c;\n" "" css)))
        (imprimeur-refresh-palette)
        (imprimeur-test-cdp-wait
         browser "getComputedStyle(document.documentElement).getPropertyValue('--emacs-code-bg') === ''")
        (should-not (equal (imprimeur-skin-minitel-test-eval browser (format "srgb(%s)" pane)) [0 0 1]))))))

(defun imprimeur-skin-minitel-test-family (file text headings)
  "Check that Minitel sets TEXT, held in FILE, in Emacs's family and colours.
TEXT holds headings of the six levels, a paragraph with inline code, a
list item and a block of Python.  HEADINGS is the vector of the colours
that the day theme gives those levels, with Org loaded, in the major
mode of FILE's buffer: each past the floor that white asks for, whose
lightness in OKLCH is the cube root of 1.05 / 6.5 - 0.05."
  (require 'org)
  (mapc #'enable-theme '(imprimeur-test-day imprimeur-test-mono))
  (unwind-protect
      (imprimeur-skin-minitel-test-with (_buffer browser file text)
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
        (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const selectors = ['h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'p', 'li', 'pre', 'code'];
  const styles = [...document.querySelectorAll(selectors.map((selector) => 'main ' + selector).join())]
    .map((element) => getComputedStyle(element));
  const unique = (values) => [...new Set(values)];
  const families = unique(styles.map((style) => style.fontFamily));
  const size = (selector) => parseFloat(getComputedStyle(document.querySelector('main ' + selector)).fontSize);
  return [selectors.filter((selector) => !document.querySelector('main ' + selector)),
          families.map((family) => family.split(',').map((name) => name.trim().replace(/^\"(.*)\"$/, '$1'))),
          unique(selectors.slice(2).map(size)).length,
          size('h1') / size('p'), size('h2') / size('p')];
})()")
                       (vector [] [["Imprimeur Test Mono" "monospace"]] 1 2 2)))
        (cl-mapc
         (lambda (got wanted) (should (imprimeur-skin-minitel-test-near-p got wanted)))
         (imprimeur-skin-minitel-test-eval browser "(() => {
  const heading = (selector) => getComputedStyle(document.querySelector('main ' + selector));
  return [heading('h1').color, heading('h2').color, heading('h3').backgroundColor, heading('h4').color,
          heading('h5').color, heading('h6').color, getComputedStyle(document.querySelector('main .kw')).color].map(srgb);
})()")
         (imprimeur-skin-minitel-test-eval
          browser (format "(() => {
  const floor = Math.cbrt(1.05 / 6.5 - 0.05);
  const probe = document.body.appendChild(document.createElement('span'));
  const colours = %s.map((colour) => {
    probe.style.color = `oklch(from ${colour} min(l, ${floor}) c h)`;
    return srgb(getComputedStyle(probe).color);
  });
  probe.remove();
  return colours;
})()" (json-serialize (vconcat headings ["#8959a8"])))))
        (should-not (imprimeur-test-cdp-errors browser)))
    (mapc #'disable-theme '(imprimeur-test-day imprimeur-test-mono))))

(ert-deftest imprimeur-skin-minitel-sets-org-in-the-emacs-family-and-colours ()
  ;; An Org buffer reads `org-level-N' first.
  (imprimeur-skin-minitel-test-family
   "doc.org" (concat "* One\n** Two\n*** Three\n**** Four\n***** Five\n"
                     "****** Six\nA paragraph with ~code~.\n\n- an item\n\n"
                     "#+begin_src python\ndef f():\n    return 1\n#+end_src\n")
   ["#c82821" "#c82822" "#c82823" "#c82824" "#c82825" "#c82826"]))

(ert-deftest imprimeur-skin-minitel-sets-markdown-in-the-emacs-family-and-colours ()
  (imprimeur-skin-minitel-test-family
   "doc.md" (concat "# One\n\n## Two\n\n### Three\n\n#### Four\n\n##### Five\n\n"
                    "###### Six\n\nA paragraph with `code`.\n\n- an item\n\n"
                    "```python\ndef f():\n    return 1\n```\n")
   ;; Any other buffer reads `org-level-N' last: markdown-mode's faces being no
   ;; faces here, `outline-N' gives these.
   ["#f58711" "#f58712" "#f58713" "#f58714" "#f58715" "#f58716"]))

(ert-deftest imprimeur-skin-minitel-falls-back-on-its-own-colours ()
  ;; A palette with no colour: its appearance alone chooses between Minitel's own, whose
  ;; background and foreground are these, and every other colour of text has a contrast of
  ;; 4.5:1 at least on the background.
  (let ((palette (list :appearance "light" :css ":root {\n}\n"))
        (light (vector "#f5f3ec" "#1c1c1a" t))
        (dark (vector "#121211" "#e6e4dc" t))
        (state "(() => {
  const root = document.documentElement;
  const hex = (colour) => '#' + srgb(colour).map((channel) => channel.toString(16).padStart(2, '0')).join('');
  const texts = ['muted', 'link', 'keyword', 'string', 'comment', 'constant', 'function', 'type', 'error'];
  return [root.dataset.appearance ?? null, getComputedStyle(root).getPropertyValue('--emacs-bg'),
          getComputedStyle(root).backgroundColor,
          [hex(token('background')), hex(token('foreground')),
           texts.every((name) => contrast(token(name), token('background')) >= 4.5)]];
})()")
        (prefer (lambda (browser scheme)
                  (imprimeur-test-cdp-call browser "Emulation.setEmulatedMedia"
                                           `(:features [(:name "prefers-color-scheme" :value ,scheme)])))))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-skin-minitel-test-with (buffer browser "doc.org" "* Heading\n#+begin_src python\n# TODO\n#+end_src\n")
        (funcall prefer browser "dark")
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
        (should (equal (imprimeur-skin-minitel-test-eval browser state)
                       (vector "light" "" "rgb(245, 243, 236)" light)))
        ;; With no warning colour, an alert takes Minitel's error colour.
        (should (eq (imprimeur-skin-minitel-test-eval
                     browser "srgb(getComputedStyle(document.querySelector('main .al')).backgroundColor).join() === srgb(token('error')).join()")
                    t))
        (setq palette (list :appearance "dark" :css ":root {\n}\n"))
        (imprimeur-refresh-palette)
        (funcall prefer browser "light")
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
        (should (equal (imprimeur-skin-minitel-test-eval browser state)
                       (vector "dark" "" "rgb(18, 18, 17)" dark)))
        ;; Before a palette arrives, the reader's preference chooses.
        (imprimeur-test-cdp-call browser "Network.setBlockedURLs" '(:urls ["*/.imprimeur/events"]))
        (imprimeur-test-cdp-navigate browser (imprimeur-url buffer))
        (imprimeur-test-wait-for
         (lambda () (seq-find (lambda (failure) (equal (plist-get failure :blockedReason) "inspector"))
                              (imprimeur-test-cdp-events-named browser "Network.loadingFailed"))))
        (should (equal (aref (imprimeur-skin-minitel-test-eval browser state) 2) "rgb(245, 243, 236)"))
        (funcall prefer browser "dark")
        (should (equal (aref (imprimeur-skin-minitel-test-eval browser state) 2) "rgb(18, 18, 17)"))))))

(ert-deftest imprimeur-skin-minitel-takes-bold-and-italic-from-the-theme ()
  ;; A keyword, a string and a comment, whose slant neither theme gives.
  (pcase-dolist (`(,theme ,expected)
                 '((imprimeur-test-bold-italic
                    [["700" "normal"] ["400" "italic"] ["400" "italic"]])
                   ;; Only comments are italic.
                   (imprimeur-test-plain-code
                    [["400" "normal"] ["400" "normal"] ["400" "italic"]])))
    (mapc #'enable-theme (list theme 'imprimeur-test-mono))
    (unwind-protect
        (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" "#+begin_src python
def f():
    # A comment.
    return \"a string\"
#+end_src
")
          (should (equal (imprimeur-test-cdp-eval browser "(() => {
  const styles = ['.kw', '.st', '.co']
    .map((selector) => getComputedStyle(document.querySelector('main ' + selector)));
  const all = [getComputedStyle(document.querySelector('main pre')), ...styles];
  return [styles.map((style) => [style.fontWeight, style.fontStyle]),
          [...new Set(all.map((style) => style.fontFamily))].length,
          [...new Set(all.map((style) => style.fontSize))].length];
})()")
                         (vector expected 1 1))))
      (mapc #'disable-theme (list theme 'imprimeur-test-mono)))))

(ert-deftest imprimeur-skin-minitel-reads-each-token-of-the-palette ()
  (let* (;; Each token, a number of its own, and pandoc's classes that Minitel gives it.
         (tokens '(("kw" 1 ("kw" "cf" "im"))
                   ("str" 2 ("st" "ch" "ss" "vs" "sc"))
                   ("com" 3 ("co" "cv" "an" "in"))
                   ("doc" 4 ("do"))
                   ("const" 5 ("dv" "bn" "fl" "cn"))
                   ("fn" 6 ("fu" "ex"))
                   ("builtin" 7 ("bu"))
                   ("type" 8 ("dt" "at"))
                   ("pre" 9 ("pp"))
                   ("var" 10 ("va"))
                   ("warn" 11 ("al" "er"))))
         (each-class (lambda (function)
                       (vconcat (seq-mapcat (lambda (token)
                                              (mapcar (lambda (class) (funcall function token class))
                                                      (nth 2 token)))
                                            tokens))))
         ;; Each token's colour, weight and style say its number; each colour is past the
         ;; floor of the dark ground.
         (palette (list :appearance "dark"
                        :css (concat ":root {\n  --emacs-bg: #000100;\n  --emacs-bg-luminance: 0.0000;\n"
                                     (mapconcat (lambda (token)
                                                  (format "  --emacs-%1$s: #f0f0%2$02x;
  --emacs-%1$s-weight: %3$d;\n  --emacs-%1$s-style: oblique %2$ddeg;\n"
                                                          (car token) (nth 1 token) (* 50 (nth 1 token))))
                                                tokens "")
                                     "}\n")))
         (from-palette (funcall each-class
                                (lambda (token class)
                                  (vector class
                                          (number-to-string (* 50 (nth 1 token)))
                                          (format "oblique %ddeg" (nth 1 token))))))
         ;; The weight and slant of the text around them, except comments and documentation,
         ;; which are italic.
         (from-minitel (funcall each-class
                                (lambda (token class)
                                  (vector class "700"
                                          (if (member (car token) '("com" "doc")) "italic" "oblique 20deg")))))
         (colours (funcall each-class
                           (lambda (token _class)
                             ;; An alert paints its text in the background.
                             (if (equal (car token) "warn") [0 1 0] (vector 240 240 (nth 1 token))))))
         (classes (json-serialize (funcall each-class (lambda (_token class) class))))
         (state "(() => {
  const spans = [...document.querySelectorAll('#token-probe > span')];
  const styles = spans.map((span) => getComputedStyle(span));
  return [spans.map((span, index) => [span.className, styles[index].fontWeight, styles[index].fontStyle]),
          [...new Set(styles.map((style) => style.fontFamily))].length,
          [...new Set(styles.map((style) => style.fontSize))].length];
})()"))
    (cl-letf (((symbol-function 'imprimeur-palette) (lambda (_buffer) palette)))
      (imprimeur-skin-minitel-test-with (_buffer browser "doc.org" "Text.\n")
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'dark'")
        ;; A block of code as pandoc writes one, holding a span of each class, in text that
        ;; has a weight and slant of its own, as the header of a table has.
        (imprimeur-test-cdp-eval browser (format "(() => {
  const code = document.body.appendChild(document.createElement('pre')).appendChild(document.createElement('code'));
  code.id = 'token-probe';
  code.className = 'sourceCode';
  code.style.fontWeight = '700';
  code.style.fontStyle = 'oblique 20deg';
  code.append(...%s.map((name) => {
    const span = document.createElement('span');
    span.className = name;
    return span;
  }));
})()" classes))
        (should (equal (imprimeur-test-cdp-eval browser state) (vector from-palette 1 1)))
        (cl-mapc (lambda (got wanted) (should (imprimeur-skin-minitel-test-near-p got wanted)))
                 (imprimeur-skin-minitel-test-eval
                  browser "[...document.querySelectorAll('#token-probe > span')].map((span) => srgb(getComputedStyle(span).color))")
                 colours)
        (setq palette (list :appearance "light" :css ":root {\n}\n"))
        (imprimeur-refresh-palette)
        (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
        (should (equal (imprimeur-test-cdp-eval browser state) (vector from-minitel 1 1)))))))

(ert-deftest imprimeur-skin-minitel-draws-its-diagrams-in-its-inks ()
  ;; Its inks are in oklch, which Mermaid's theme does not read, so a drawing that shows
  ;; them in rgb is the page's own: the text of a node reads on its ground.
  (imprimeur-test-require "mmdc")
  (imprimeur-skin-minitel-test-with (_buffer browser "doc.md" "```mermaid\nflowchart TD\n  A[Words] --> B\n```\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('main pre.mermaid > svg') !== null" 30)
    (should (>= (imprimeur-skin-minitel-test-eval browser "(() => {
  const label = document.querySelector('main pre.mermaid .nodeLabel, main pre.mermaid .node text');
  const shape = document.querySelector('main pre.mermaid .node rect, main pre.mermaid .node polygon');
  return contrast(getComputedStyle(label).fill || getComputedStyle(label).color, getComputedStyle(shape).fill);
})()")
                4.5))
    (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))))

;;;; The samples

(defun imprimeur-skin-minitel-test-sample (file language checks)
  "Check the page of the sample FILE, whose code is in LANGUAGE, and run CHECKS.
CHECKS is a function of the browser."
  (let ((text (with-temp-buffer
                (insert-file-contents (expand-file-name file (expand-file-name "examples/minitel" repo-test-root)))
                (buffer-string))))
    (imprimeur-skin-minitel-test-with (_buffer browser file text)
      (imprimeur-test-cdp-wait browser "document.querySelectorAll('main h2').length > 1")
      (imprimeur-test-cdp-wait browser "document.querySelector('.minitel-crumb').textContent !== ''")
      ;; The language in the border of a pane, no overflow, and everything reads.
      (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('main div.sourceCode'), '::before').content")
                     (format "%S" language)))
      (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.scrollWidth")
                     (imprimeur-test-cdp-eval browser "document.documentElement.clientWidth")))
      (should (>= (imprimeur-skin-minitel-test-lowest-contrast browser) 4.5))
      (funcall checks browser)
      (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown")))))

(ert-deftest imprimeur-skin-minitel-sets-robida-in-french ()
  (imprimeur-skin-minitel-test-sample
   "robida.org" "python"
   (lambda (browser)
     (imprimeur-skin-minitel-test-key browser "s" "s")
     (should (string-search "Votre choix" (imprimeur-test-cdp-eval browser "document.querySelector('.minitel-prompt').textContent")))
     (imprimeur-skin-minitel-test-key browser "Escape" nil 27)
     (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('main .warning'), '::before').content")
                    "\"ATTENTION\"")))))

(ert-deftest imprimeur-skin-minitel-sets-wells-in-english ()
  (imprimeur-skin-minitel-test-sample
   "wells.md" "elisp"
   (lambda (browser)
     (imprimeur-skin-minitel-test-key browser "s" "s")
     (should (string-search "Your choice" (imprimeur-test-cdp-eval browser "document.querySelector('.minitel-prompt').textContent")))
     (imprimeur-skin-minitel-test-key browser "Escape" nil 27)
     (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('main .important'), '::before').content")
                    "\"IMPORTANT\"")))))

;;; imprimeur-skin-minitel-test.el ends here
