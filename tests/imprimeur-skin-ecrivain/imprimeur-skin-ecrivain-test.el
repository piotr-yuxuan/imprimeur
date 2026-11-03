;;; imprimeur-skin-ecrivain-test.el --- Tests of the skin Écrivain  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 024:
;;
;; "Cahier by default, in Playwrite FR Moderne with Trad one choice away, the letters exactly
;; on the Seyès ruling, pages or pageless by a toggle, pageless by default": the manifest's
;; options, by hand from docs/work/workbench/page/skins/ecrivain/params.json: variant
;; (cahier, carnet, notes, ardoise), hand (moderne, trad), ink (variante, bleu-noir, bleu,
;; noir, violet, sepia), sheet (pageless, pages).  "No font file is served."
;;
;; Acceptance 3: each option changes what it says, alone; the sheet toggle takes no reload;
;; no line is lost, doubled or cut at a leaf's end, and copying and search hold across one.
;; Acceptance 5: the filter is within 10, by luacheck.
;;
;; The grid, from the trial's statement of its design: an interline of 9 on a line of 36,
;; 8 on 32 under 600 CSS px, a size of a whole number of pixels over 0.519, 24 lines to a
;; leaf; Carnet and Notes on 28 with 32 lines, Ardoise on 32 with 27.  Every block of main
;; is a whole number of lines.  The sheet is a whole number of leaves, the last holds the
;; end of the text, and a leaf is a band of floats with no count that a hand could outrun.
;;
;; The filter, by the same statement: date and author in a block of their own; each kind of
;; frame seeded 0 to 7 from its section and its rank and never its text, a diagram not, and
;; neighbours of a kind differ; .ecrivain-snap around code, a table, a diagram, a figure's
;; content and a display formula; .ecrivain-long at 37 lines and 19 rows and not at 36 and
;; 18; .ecrivain-long-bloc at 1001 letters and not at 1000.
;;
;; That the letters sit on the ruling is by pixels, with the fonts: the script `align'
;; beside this file, by hand, as `make check' has neither.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-skin-ecrivain-test-file
  (expand-file-name "imprimeur-skin-ecrivain/imprimeur-skin-ecrivain.el" repo-test-root)
  "The skin's main file.")

(defconst imprimeur-skin-ecrivain-test-examples
  (expand-file-name "examples/ecrivain" repo-test-root)
  "The directory of the samples.")

(defun imprimeur-skin-ecrivain-test-read (file)
  "Return the text of FILE, a sample."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file imprimeur-skin-ecrivain-test-examples))
    (buffer-string)))

(defun imprimeur-skin-ecrivain-test-html (reader text)
  "Return the HTML that Écrivain's chain writes from TEXT in READER, on real pandoc."
  (let ((pandoc (imprimeur-test-require "pandoc"))
        (imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-ecrivain-test-file nil t)
    (with-temp-buffer
      (insert text)
      (should (equal (apply #'call-process-region (point-min) (point-max) pandoc t t nil
                            (imprimeur-render-arguments reader nil nil "python,bash"
                                                        (imprimeur-skin-get "ecrivain")))
                     0))
      (buffer-string))))

(defun imprimeur-skin-ecrivain-test-seeds (html)
  "Return the seeds that HTML holds, in order, as strings."
  (let ((start 0) seeds)
    (while (string-match "data-ecrivain-seed=\"\\([^\"]*\\)\"" html start)
      (setq start (match-end 0))
      (push (match-string 1 html) seeds))
    (nreverse seeds)))

(defun imprimeur-skin-ecrivain-test-count (html regexp)
  "Return how many times REGEXP matches in HTML."
  (let ((start 0) (count 0))
    (while (string-match regexp html start)
      (setq start (match-end 0) count (1+ count)))
    count))

(defmacro imprimeur-skin-ecrivain-test-with (spec &rest body)
  "Run BODY with Écrivain as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT [FILES]): BUFFER visits FILE, holding TEXT, in the
selected Emacs window, in `imprimeur-mode'; BROWSER shows its page at 800 by 1000 CSS
pixels.  FILES, an alist from a name to its text, are beside it."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text ,files) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'ecrivain)
              (imprimeur-skin-options nil)
              (imprimeur-appearance 'light)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (cons (cons ,file ,text) ,files)))
              (,buffer (find-file-noselect (expand-file-name ,file root))))
         (load imprimeur-skin-ecrivain-test-file nil t)
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer ,buffer)
               (imprimeur-test-cdp-with-browser ,browser
                 (imprimeur-skin-ecrivain-test-size ,browser 800)
                 (imprimeur-mode 1)
                 (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
                 (imprimeur-test-wait-for
                  (lambda () (imprimeur-test-cdp-eval
                              ,browser "!!(document.documentElement.dataset.revision && document.querySelector('.ecrivain-feuilles'))")))
                 ,@body))
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defun imprimeur-skin-ecrivain-test-size (browser width)
  "Give BROWSER's page WIDTH CSS pixels, and wait for it to lay out."
  (imprimeur-test-cdp-call browser "Emulation.setDeviceMetricsOverride"
                           `(:width ,width :height 1000 :deviceScaleFactor 1 :mobile :false))
  (imprimeur-test-cdp-wait browser (format "innerWidth === %d" width)))

(defun imprimeur-skin-ecrivain-test-choose (buffer browser id value)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-ecrivain-%s') === %s"
                   id (if (equal value (plist-get (cdr (assq (intern id) (plist-get (imprimeur-skin-get "ecrivain") :options)))
                                                  :default))
                          "null"
                        (format "%S" value)))))

(defun imprimeur-skin-ecrivain-test-attributes (browser)
  "Return the names of the data-ecrivain attributes on the root of BROWSER's page."
  (append (imprimeur-test-cdp-eval
           browser "[...document.documentElement.attributes].map((a) => a.name).filter((n) => n.startsWith('data-ecrivain'))")
          nil))

(defun imprimeur-skin-ecrivain-test-settle (browser)
  "Wait until BROWSER's page has laid out all its diagrams and pictures."
  (imprimeur-test-cdp-wait
   browser "[...document.querySelectorAll('main pre.mermaid')].every((pre) => pre.querySelector('svg')) && [...document.images].every((image) => image.complete)"
   60)
  (imprimeur-test-cdp-eval browser "document.fonts.ready.then(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))))"))

(defconst imprimeur-skin-ecrivain-test-off-grid
  "(() => {
  const line = parseFloat(getComputedStyle(document.body).lineHeight);
  const top = document.body.getBoundingClientRect().top;
  return [...document.getElementById('imprimeur-main').children]
    .filter((block) => Math.abs((block.getBoundingClientRect().top - top) / line % 1) > 0.01
                       && Math.abs((block.getBoundingClientRect().top - top) / line % 1) < 0.99)
    .map((block) => block.tagName + '.' + block.className);
})()"
  "A script that names the blocks of main that do not start on a line of the paper.")

(defconst imprimeur-skin-ecrivain-test-gate
  "(() => {
  const root = document.documentElement;
  const body = document.body.getBoundingClientRect();
  const stack = document.querySelector('.ecrivain-feuilles');
  const line = parseFloat(getComputedStyle(document.body).lineHeight);
  const writing = parseFloat(getComputedStyle(root).getPropertyValue('--ecrivain-feuille-lignes')) * line;
  const period = writing + 3 * line;
  const main = document.getElementById('imprimeur-main');
  const last = [...main.children].filter((block) => block.getBoundingClientRect().height > 0).at(-1);
  const end = last.getBoundingClientRect().bottom - body.top;
  const leaves = (body.height + 2 * line) / period;
  const count = Math.round(leaves);
  const writingEnd = (count - 1) * period + writing;
  const problems = [];
  if (getComputedStyle(stack).display === 'none') problems.push('no leaves');
  if (Math.abs(leaves - count) > 1e-6) problems.push(`the sheet is ${leaves} leaves`);
  if (end > writingEnd + 0.5) problems.push(`the text ends past the last leaf by ${end - writingEnd}`);
  if (end <= writingEnd - writing + 0.5 && count > 1) problems.push('the last leaf is blank');
  if (stack.children.length <= count) problems.push(`${stack.children.length} leaves in the stack and ${count} show`);
  if (Math.round(root.scrollHeight) !== Math.round(body.height)) problems.push(`the page is ${root.scrollHeight} and the sheet ${body.height}`);
  if (root.scrollWidth > root.clientWidth) problems.push(`scroll width ${root.scrollWidth}`);
  const range = document.createRange();
  const walker = document.createTreeWalker(main, NodeFilter.SHOW_TEXT);
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (node.parentElement.closest('svg, .footnote-back') || !node.data.trim()) continue;
    for (let at = 0; at < node.length; at += 1) {
      range.setStart(node, at);
      range.setEnd(node, at + 1);
      const rect = range.getClientRects()[0];
      if (rect && rect.width > 0 && (rect.top + rect.height / 2 - body.top) % period > writing) {
        problems.push(`a letter of \"${node.data.slice(0, 30)}\" lies in a band`);
        break;
      }
    }
  }
  return problems;
})()"
  "A script that says what is wrong with the leaves of a page in pages, from its layout alone.
No letter lies in a band, which is where a line would be cut.")

(defconst imprimeur-skin-ecrivain-test-bridges
  "(() => {
  const line = parseFloat(getComputedStyle(document.body).lineHeight);
  const range = document.createRange();
  const walker = document.createTreeWalker(document.getElementById('imprimeur-main'), NodeFilter.SHOW_TEXT);
  const bridges = [];
  let previous = null;
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (node.parentElement.closest('svg, math, kbd, sup, sub, .task, .footnote-back, pre, table')) continue;
    for (let at = 0; at < node.length; at += 1) {
      if (/\\s/.test(node.data[at])) continue;
      range.setStart(node, at);
      range.setEnd(node, at + 1);
      const rect = range.getClientRects()[0];
      if (!rect) continue;
      const y = rect.top + rect.height / 2 + scrollY;
      const block = node.parentElement.closest('p, li, dd, dt, h1, h2, h3, h4, h5, h6');
      if (block && previous && previous.block === block && y - previous.y > 3 * line) {
        bridges.push({ node, at, before: previous.node, beforeAt: previous.at });
      }
      previous = { y, node, at, block };
    }
  }
  const selection = getSelection();
  const report = bridges.map((bridge) => {
    const pick = document.createRange();
    pick.setStart(bridge.before, Math.max(0, bridge.beforeAt - 14));
    pick.setEnd(bridge.node, Math.min(bridge.node.length, bridge.at + 14));
    selection.removeAllRanges();
    selection.addRange(pick);
    const copied = selection.toString();
    selection.removeAllRanges();
    scrollTo(0, 0);
    const phrase = copied.replace(/\\s+/g, ' ').trim();
    const found = window.find(phrase);
    const foundText = selection.toString().replace(/\\s+/g, ' ').trim();
    selection.removeAllRanges();
    return { text: copied, running: copied.replace(/\\s+/g, ' ') === pick.toString().replace(/\\s+/g, ' '),
             newlines: (copied.match(/\\n/g) || []).length, found, same: foundText === phrase };
  });
  scrollTo(0, 0);
  return report;
})()"
  "A script that, at each place where a block's text goes under a band, selects and searches.")

(defconst imprimeur-skin-ecrivain-test-text
  "(() => {
  const range = document.createRange();
  const walker = document.createTreeWalker(document.getElementById('imprimeur-main'), NodeFilter.SHOW_TEXT);
  let shown = '';
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (node.parentElement.closest('svg')) continue;
    for (let at = 0; at < node.length; at += 1) {
      range.setStart(node, at);
      range.setEnd(node, at + 1);
      if (!/\\s/.test(node.data[at]) && range.getClientRects().length === 1) shown += node.data[at];
    }
  }
  return shown;
})()"
  "A script that gives the letters of main that the layout gives one box: so none is lost or
doubled, by a rule that hides a line or a block that shows twice.")

(ert-deftest imprimeur-skin-ecrivain-registers-from-its-autoloads-alone ()
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-ecrivain-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-ecrivain-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-ecrivain)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S\" (and (imprimeur-skin-get \"ecrivain\") t)))"))))
    (should (equal (car result) 0))
    (should (string-match-p "MARK\\(.\\|\n\\)*before=nil after=t\\'" (cdr result)))))

(ert-deftest imprimeur-skin-ecrivain-keeps-the-owner-s-defaults-and-choices ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-ecrivain-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "ecrivain"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "Écrivain"))
      (should (plist-get manifest :smart))
      (should (equal (plist-get manifest :notes) 'section))
      (should (equal (plist-get manifest :module) "leaves.mjs"))
      (pcase-dolist (`(,id ,default . ,choices)
                     '((variant "cahier" "cahier" "carnet" "notes" "ardoise")
                       (hand "moderne" "moderne" "trad")
                       (ink "variante" "variante" "bleu-noir" "bleu" "noir" "violet" "sepia")
                       (sheet "pageless" "pageless" "pages")))
        (ert-info ((symbol-name id))
          (should (equal (plist-get (alist-get id options) :default) default))
          (should (equal (mapcar #'car (plist-get (alist-get id options) :choices)) choices))))
      (should (equal (mapcar #'car options) '(variant hand ink sheet))))))

(ert-deftest imprimeur-skin-ecrivain-serves-no-font ()
  (let ((sheet (with-temp-buffer
                 (insert-file-contents (expand-file-name "imprimeur-skin-ecrivain/assets/skin.css" repo-test-root))
                 (buffer-string))))
    (should-not (string-match-p "url([^\"d]\\|url(\"[^d]\\|woff2\\|font-variation-settings" sheet))
    ;; The one face it declares is the installed strut, for its range.
    (should (equal (imprimeur-skin-ecrivain-test-count sheet "@font-face") 1))
    (should (string-match-p "src: local(\"Ecrivain Espace\")" sheet)))
  (imprimeur-skin-ecrivain-test-with (_buffer browser "doc.md" "# T\n\nWords.\n")
    (should-not (seq-some (lambda (event)
                            (equal (plist-get (plist-get event :params) :type) "Font"))
                          (imprimeur-test-cdp-events-named browser "Network.requestWillBeSent")))))

(ert-deftest imprimeur-skin-ecrivain-writes-the-title-block ()
  (let ((html (imprimeur-skin-ecrivain-test-html
               "org" "#+TITLE: T\n#+AUTHOR: Quelqu'un\n#+DATE: Dimanche 1er novembre\n#+LANGUAGE: fr\n\nDes mots.\n")))
    (should (string-match-p "class=\"ecrivain-titre\"" html))
    (should (< (string-match "ecrivain-titre" html) (string-match "Des mots" html)))
    (should (string-match-p "class=\"ecrivain-date\"" html))
    (should (string-match-p "class=\"ecrivain-author\"" html))
    ;; What the filter writes, the sheet reads.
    (let ((sheet (with-temp-buffer
                   (insert-file-contents (expand-file-name "imprimeur-skin-ecrivain/assets/skin.css" repo-test-root))
                   (buffer-string))))
      (dolist (class '("titre" "date" "author" "snap" "suite" "long" "long-bloc"))
        (should (string-match-p (format "\\.ecrivain-%s\\b" class) sheet))))
    ;; French's raised letters reach the date, as `french' comes after the filter.
    (should (string-match-p "<sup>er</sup>" html)))
  (should-not (string-match-p "ecrivain-titre"
                              (imprimeur-skin-ecrivain-test-html "org" "#+TITLE: T\n\nDes mots.\n"))))

(ert-deftest imprimeur-skin-ecrivain-seeds-by-section-and-rank-and-never-by-text ()
  (let* ((document (lambda (word)
                     (format "# Un\n\n| %s |\n|---|\n| 1 |\n\n| b |\n|---|\n| 2 |\n\n```python\nprint('%s')\n```\n\n```mermaid\nflowchart TB\n  A --> B\n```\n\n# Deux\n\n> [!NOTE]\n> %s\n\n![%s](p.svg)\n" word word word word)))
         (seeds (imprimeur-skin-ecrivain-test-seeds
                 (imprimeur-skin-ecrivain-test-html "gfm+sourcepos+smart" (funcall document "mot")))))
    ;; Two tables, the code, the alert and the figure, and no seed for the diagram.
    (should (equal (length seeds) 5))
    (dolist (seed seeds)
      (should (string-match-p "\\`[0-7]\\'" seed)))
    (should-not (equal (nth 0 seeds) (nth 1 seeds)))
    ;; Typing inside the blocks draws no other strokes.
    (should (equal seeds (imprimeur-skin-ecrivain-test-seeds
                          (imprimeur-skin-ecrivain-test-html "gfm+sourcepos+smart" (funcall document "autre")))))
    ;; A table added to the first section leaves the second's as it was.
    (let ((more (imprimeur-skin-ecrivain-test-seeds
                 (imprimeur-skin-ecrivain-test-html
                  "gfm+sourcepos+smart"
                  (concat "# Un\n\n| c |\n|---|\n| 3 |\n\n"
                          (string-remove-prefix "# Un\n\n" (funcall document "mot")))))))
      (should (equal (last more 2) (last seeds 2))))))

(ert-deftest imprimeur-skin-ecrivain-sets-whole-blocks-on-the-grid ()
  (pcase-dolist (`(,text ,snaps)
                 '(("```python\nx = 1\n```\n" 1)
                   ("```\nplain\n```\n" 1)
                   ("```mermaid\nflowchart TB\n  A --> B\n```\n" 1)
                   ("| a |\n|---|\n| 1 |\n" 1)
                   ("![Une image.](p.svg)\n" 1)
                   ("Des mots $$x^2$$ encore.\n" 1)
                   ("Des mots sans formule.\n" 0)))
    (ert-info (text)
      (should (equal (imprimeur-skin-ecrivain-test-count
                      (imprimeur-skin-ecrivain-test-html "gfm+sourcepos+smart" text)
                      "class=\"ecrivain-snap\"")
                     snaps)))))

(ert-deftest imprimeur-skin-ecrivain-marks-what-a-leaf-cannot-hold ()
  (let ((code (lambda (lines)
                (format "```python\n%s\n```\n" (string-join (make-list lines "x = 1") "\n"))))
        (plain (lambda (lines)
                 (format "```\n%s\n```\n" (string-join (make-list lines "x") "\n"))))
        (rows (lambda (count)
                (format "| a |\n|---|\n%s\n" (string-join (make-list (1- count) "| 1 |") "\n"))))
        (quote (lambda (letters) (format "> %s\n" (make-string letters ?x))))
        (alert (lambda (letters) (format "> [!NOTE]\n> %s\n" (make-string letters ?x)))))
    (pcase-dolist (`(,make ,under ,over ,class)
                   `((,code 36 37 "ecrivain-long\"")
                     (,plain 36 37 "ecrivain-long\"")
                     (,rows 18 19 "ecrivain-long\"")
                     (,quote 1000 1001 "ecrivain-long-bloc")))
      (ert-info ((format "%s at %d and %d" class under over))
        (should-not (string-match-p class (imprimeur-skin-ecrivain-test-html
                                           "gfm+sourcepos+smart" (funcall make under))))
        (should (string-match-p class (imprimeur-skin-ecrivain-test-html
                                       "gfm+sourcepos+smart" (funcall make over))))))
    ;; An alert counts its title's word as well as its text.
    (should-not (string-match-p "ecrivain-long-bloc" (imprimeur-skin-ecrivain-test-html
                                                      "gfm+sourcepos+smart" (funcall alert 900))))
    (should (string-match-p "ecrivain-long-bloc" (imprimeur-skin-ecrivain-test-html
                                                  "gfm+sourcepos+smart" (funcall alert 1001))))))

(ert-deftest imprimeur-skin-ecrivain-keeps-a-paragraph-whole-around-a-formula ()
  (let ((html (imprimeur-skin-ecrivain-test-html "gfm+sourcepos+smart" "Avant $$x^2$$ après, et ainsi.\n")))
    (should (< (string-match "Avant" html) (string-match "ecrivain-snap" html)
               (string-match "ecrivain-suite" html) (string-match "après" html))))
  ;; An Org paragraph too, which has no wrapper.
  (let ((html (imprimeur-skin-ecrivain-test-html "org" "Avant\n\\[ x^2 \\]\naprès.\n")))
    (should (< (string-match "Avant" html) (string-match "ecrivain-snap" html)
               (string-match "ecrivain-suite" html) (string-match "après" html)))))

(ert-deftest imprimeur-skin-ecrivain-writes-the-same-bytes-twice ()
  ;; The page's block diff keeps a block whose markup is the same.
  (let ((text (imprimeur-skin-ecrivain-test-read "notebook.md")))
    (should (equal (imprimeur-skin-ecrivain-test-html "gfm+sourcepos+smart" text)
                   (imprimeur-skin-ecrivain-test-html "gfm+sourcepos+smart" text)))))

(ert-deftest imprimeur-skin-ecrivain-keeps-the-grid-by-default ()
  (imprimeur-skin-ecrivain-test-with (_buffer browser "doc.org" "#+TITLE: T\n\nDes mots.\n")
    (should-not (imprimeur-skin-ecrivain-test-attributes browser))
    (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('.ecrivain-feuilles')).display") "none"))
    (pcase-dolist (`(,width ,interline)
                   '((800 9) (420 8)))
      (ert-info ((format "at %d" width))
        (imprimeur-skin-ecrivain-test-size browser width)
        (imprimeur-test-cdp-wait browser (format "getComputedStyle(document.documentElement).getPropertyValue('--ecrivain-i').trim() === '%dpx'" interline))
        (should (equal (imprimeur-test-cdp-eval browser "parseFloat(getComputedStyle(document.body).lineHeight)") (* 4 interline)))
        (should (< (abs (- (imprimeur-test-cdp-eval browser "parseFloat(getComputedStyle(document.body).fontSize)")
                           (/ interline 0.519)))
                   0.01))))
    (should (string-prefix-p "\"Ecrivain Espace\", \"Ecrivain Cahier\""
                             (imprimeur-test-cdp-eval browser "getComputedStyle(document.body).fontFamily")))))

(defun imprimeur-skin-ecrivain-test-said (browser)
  "Return what each option decides of BROWSER's page, as an alist."
  (list (cons 'line (imprimeur-test-cdp-eval browser "parseFloat(getComputedStyle(document.body).lineHeight)"))
        (cons 'face (imprimeur-test-cdp-eval browser "getComputedStyle(document.body).fontFamily.split(', ')[1]"))
        (cons 'ink (imprimeur-test-cdp-eval browser "getComputedStyle(document.body).color"))
        (cons 'leaves (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('.ecrivain-feuilles')).display"))))

(ert-deftest imprimeur-skin-ecrivain-changes-what-each-option-says-alone ()
  (imprimeur-skin-ecrivain-test-with (buffer browser "doc.org" "#+TITLE: T\n\nDes mots.\n")
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.appearance === 'light'")
    (let ((defaults (imprimeur-skin-ecrivain-test-said browser)))
      (should (equal defaults '((line . 36) (face . "\"Ecrivain Cahier\"") (ink . "rgb(34, 48, 127)") (leaves . "none"))))
      (pcase-dolist (`(,id ,value ,default . ,says)
                     '(("hand" "trad" "moderne" (face . "\"Ecrivain Trad\""))
                       ("ink" "bleu-noir" "variante" (ink . "rgb(28, 42, 74)"))
                       ("ink" "bleu" "variante" (ink . "rgb(31, 63, 166)"))
                       ("ink" "noir" "variante" (ink . "rgb(15, 14, 12)"))
                       ("ink" "violet" "variante" (ink . "rgb(77, 42, 140)"))
                       ("ink" "sepia" "variante" (ink . "rgb(90, 58, 30)"))
                       ("sheet" "pages" "pageless" (leaves . "contents"))
                       ("variant" "carnet" "cahier" (line . 28) (face . "\"Ecrivain Carnet\"") (ink . "rgb(28, 42, 74)"))
                       ("variant" "notes" "cahier" (line . 28) (face . "\"Ecrivain Note\"") (ink . "rgb(38, 38, 44)"))
                       ("variant" "ardoise" "cahier" (line . 32) (face . "\"Ecrivain Ardoise\"") (ink . "rgb(238, 236, 226)"))))
        (ert-info ((format "%s %s" id value))
          (imprimeur-skin-ecrivain-test-choose buffer browser id value)
          (should (equal (imprimeur-skin-ecrivain-test-said browser)
                         (mapcar (lambda (entry) (or (assq (car entry) says) entry)) defaults)))
          (should (equal (imprimeur-skin-ecrivain-test-attributes browser) (list (concat "data-ecrivain-" id))))
          (imprimeur-skin-ecrivain-test-choose buffer browser id default)
          (should (equal (imprimeur-skin-ecrivain-test-said browser) defaults))))
      (should-not (imprimeur-skin-ecrivain-test-attributes browser)))))

(ert-deftest imprimeur-skin-ecrivain-toggles-the-sheet-with-no-reload ()
  (imprimeur-skin-ecrivain-test-with
      (buffer browser "doc.org" (concat "#+TITLE: T\n\n"
                                        (mapconcat (lambda (n) (format "Des mots, alinéa %d.\n\n" n))
                                                   (number-sequence 1 60))))
    (imprimeur-test-cdp-eval browser "window.__same = true; 'ok'")
    (let ((revision (imprimeur-test-cdp-eval browser "document.documentElement.dataset.revision"))
          (loads (length (imprimeur-test-cdp-events-named browser "Page.loadEventFired")))
          (requests (length (imprimeur-test-cdp-events-named browser "Network.requestWillBeSent")))
          (pageless (imprimeur-test-cdp-eval browser "document.documentElement.scrollHeight")))
      (imprimeur-skin-ecrivain-test-choose buffer browser "sheet" "pages")
      (imprimeur-test-cdp-wait browser (format "document.documentElement.scrollHeight !== %d" pageless))
      (should (eq (imprimeur-test-cdp-eval browser "window.__same") t))
      (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.revision") revision))
      (should (equal (length (imprimeur-test-cdp-events-named browser "Page.loadEventFired")) loads))
      (should-not (seq-some (lambda (event)
                              (string-match-p "/doc\\'" (or (plist-get (plist-get (plist-get event :params) :request) :url) "")))
                            (nthcdr requests (reverse (imprimeur-test-cdp-events-named browser "Network.requestWillBeSent")))))
      ;; The layout is final in the task that sets the attribute: no script waits behind it.
      (let ((same (imprimeur-test-cdp-eval browser "(async () => {
  const root = document.documentElement;
  root.removeAttribute('data-ecrivain-sheet');
  const before = root.scrollHeight;
  root.setAttribute('data-ecrivain-sheet', 'pages');
  const now = root.scrollHeight;
  for (let frame = 0; frame < 8; frame += 1) await new Promise((done) => requestAnimationFrame(done));
  return [now !== before, now === root.scrollHeight];
})()")))
        (should (equal (append same nil) '(t t))))
      (imprimeur-skin-ecrivain-test-choose buffer browser "sheet" "pageless")
      (imprimeur-test-cdp-wait browser (format "document.documentElement.scrollHeight === %d" pageless)))))

(ert-deftest imprimeur-skin-ecrivain-stays-pageless-in-a-narrow-view ()
  (imprimeur-skin-ecrivain-test-with (buffer browser "doc.org" "#+TITLE: T\n\nDes mots.\n")
    (imprimeur-skin-ecrivain-test-choose buffer browser "sheet" "pages")
    (should (equal (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('.ecrivain-feuilles')).display") "contents"))
    (imprimeur-skin-ecrivain-test-size browser 700)
    (imprimeur-test-cdp-wait browser "getComputedStyle(document.querySelector('.ecrivain-feuilles')).display === 'none'")))

(defun imprimeur-skin-ecrivain-test-sample (file)
  "Return the alist of FILE, a sample, and the files that it shows."
  (cons (imprimeur-skin-ecrivain-test-read file)
        (mapcar (lambda (name)
                  (cons name (with-temp-buffer
                               (set-buffer-multibyte nil)
                               (insert-file-contents-literally
                                (expand-file-name name imprimeur-skin-ecrivain-test-examples))
                               (buffer-string))))
                '("plume.svg"))))

(defun imprimeur-skin-ecrivain-test-sets-sample (file)
  "Check the sample FILE on the grid, and in leaves whole, under each hand and variant."
  (let ((sample (imprimeur-skin-ecrivain-test-sample file)))
    (imprimeur-skin-ecrivain-test-with (buffer browser file (car sample) (cdr sample))
      (imprimeur-skin-ecrivain-test-settle browser)
      (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-banner').hidden || document.getElementById('imprimeur-banner').textContent") t))
      (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.imprimeur-diagram-error').length") 0))
      (should-not (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown"))
      (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.scrollWidth")
                     (imprimeur-test-cdp-eval browser "document.documentElement.clientWidth")))
      (should (equal (append (imprimeur-test-cdp-eval browser imprimeur-skin-ecrivain-test-off-grid) nil) nil))
      (let ((words (imprimeur-test-cdp-eval browser imprimeur-skin-ecrivain-test-text)))
        (imprimeur-skin-ecrivain-test-choose buffer browser "sheet" "pages")
        (pcase-dolist (`(,id ,value ,default)
                       '(("hand" "moderne" "moderne") ("hand" "trad" "moderne")
                         ("variant" "carnet" "cahier") ("variant" "notes" "cahier") ("variant" "ardoise" "cahier")))
          (ert-info ((format "%s %s" id value))
            (imprimeur-skin-ecrivain-test-choose buffer browser id value)
            (imprimeur-skin-ecrivain-test-settle browser)
            (should (equal (append (imprimeur-test-cdp-eval browser imprimeur-skin-ecrivain-test-gate) nil) nil))
            (should (equal (imprimeur-test-cdp-eval browser imprimeur-skin-ecrivain-test-text) words))
            (imprimeur-skin-ecrivain-test-choose buffer browser id default)))))))

(ert-deftest imprimeur-skin-ecrivain-sets-the-french-sample ()
  (imprimeur-skin-ecrivain-test-sets-sample "carnet.org"))

(ert-deftest imprimeur-skin-ecrivain-sets-the-english-sample ()
  (imprimeur-skin-ecrivain-test-sets-sample "notebook.md"))

(ert-deftest imprimeur-skin-ecrivain-keeps-the-grid-at-a-narrow-width ()
  (let ((sample (imprimeur-skin-ecrivain-test-sample "carnet.org")))
    (imprimeur-skin-ecrivain-test-with (_buffer browser "carnet.org" (car sample) (cdr sample))
      (imprimeur-skin-ecrivain-test-size browser 420)
      (imprimeur-skin-ecrivain-test-settle browser)
      (should (equal (append (imprimeur-test-cdp-eval browser imprimeur-skin-ecrivain-test-off-grid) nil) nil))
      (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.scrollWidth")
                     (imprimeur-test-cdp-eval browser "document.documentElement.clientWidth"))))))

(ert-deftest imprimeur-skin-ecrivain-sees-a-block-off-the-grid-and-a-broken-leaf ()
  ;; Each check can fail: what these two readers report when a sheet breaks what they guard.
  (imprimeur-skin-ecrivain-test-with
      (buffer browser "doc.org" (concat "#+TITLE: T\n\n"
                                        (mapconcat (lambda (n) (format "Des mots, alinéa %d.\n\n" n))
                                                   (number-sequence 1 60))))
    (imprimeur-test-cdp-eval browser "(() => {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync('#imprimeur-main > p:nth-of-type(3), #imprimeur-main > [data-wrapper]:nth-of-type(3) { margin-block-start: 5px !important; }');
  document.adoptedStyleSheets = [sheet];
})()")
    (should (imprimeur-test-cdp-eval browser (concat imprimeur-skin-ecrivain-test-off-grid ".length > 0")))
    (imprimeur-test-cdp-eval browser "document.adoptedStyleSheets = []; 'ok'")
    (imprimeur-skin-ecrivain-test-choose buffer browser "sheet" "pages")
    (should (equal (append (imprimeur-test-cdp-eval browser imprimeur-skin-ecrivain-test-gate) nil) nil))
    (imprimeur-test-cdp-eval browser "(() => {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync(':root #imprimeur-main::after { content: none !important; }');
  document.adoptedStyleSheets = [sheet];
})()")
    (should (imprimeur-test-cdp-eval browser (concat imprimeur-skin-ecrivain-test-gate ".length > 0")))
    ;; With no bands, the text lies where they were: the gate says so of a letter.
    (imprimeur-test-cdp-eval browser "(() => {
  const sheet = new CSSStyleSheet();
  sheet.replaceSync('.ecrivain-feuilles b { display: none !important; }');
  document.adoptedStyleSheets = [sheet];
})()")
    (should (seq-some (lambda (problem) (string-match-p "lies in a band" problem))
                      (imprimeur-test-cdp-eval browser imprimeur-skin-ecrivain-test-gate)))))

(ert-deftest imprimeur-skin-ecrivain-runs-the-text-on-across-a-leaf-s-end ()
  (let ((sample (imprimeur-skin-ecrivain-test-sample "carnet.org")))
    (imprimeur-skin-ecrivain-test-with (buffer browser "carnet.org" (car sample) (cdr sample))
      (imprimeur-skin-ecrivain-test-settle browser)
      (imprimeur-skin-ecrivain-test-choose buffer browser "sheet" "pages")
      (imprimeur-skin-ecrivain-test-settle browser)
      (let ((bridges (append (imprimeur-test-cdp-eval browser imprimeur-skin-ecrivain-test-bridges) nil)))
        (should bridges)
        (dolist (bridge bridges)
          (ert-info ((plist-get bridge :text))
            (should (eq (plist-get bridge :running) t))
            (should (equal (plist-get bridge :newlines) 0))
            (should (eq (plist-get bridge :found) t))
            (should (eq (plist-get bridge :same) t))))))))

(ert-deftest imprimeur-skin-ecrivain-keeps-its-leaves-beside-main ()
  (imprimeur-skin-ecrivain-test-with (buffer browser "doc.org" "#+TITLE: T\n\nDes mots.\n")
    (should (eq (imprimeur-test-cdp-eval browser "document.body.firstElementChild.className === 'ecrivain-feuilles'") t))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.ecrivain-feuilles').textContent") ""))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.ecrivain-feuilles').getAttribute('aria-hidden')") "true"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('#imprimeur-main .ecrivain-feuilles').length") 0))
    ;; A longer text takes a longer supply, with no count for the sheet to outrun.
    (let ((before (imprimeur-test-cdp-eval browser "document.querySelector('.ecrivain-feuilles').children.length")))
      (with-current-buffer buffer
        (goto-char (point-max))
        (insert (mapconcat (lambda (n) (format "Encore des mots, alinéa %d.\n\n" n)) (number-sequence 1 200))))
      (imprimeur-test-cdp-wait browser (format "document.querySelector('.ecrivain-feuilles').children.length > %d" before) 30))
    (with-current-buffer buffer (imprimeur-choose-skin "minitel"))
    (imprimeur-test-cdp-wait browser "document.documentElement.dataset.skin === 'minitel'")
    (should-not (imprimeur-skin-ecrivain-test-attributes browser))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.ecrivain-feuilles').length") 0))))

(ert-deftest imprimeur-skin-ecrivain-numbers-and-indents-only-french ()
  (pcase-dolist (`(,language ,counted ,indented)
                 '(("fr" t t) ("en" nil nil)))
    (ert-info (language)
      (imprimeur-skin-ecrivain-test-with
          (_buffer browser "doc.md" (format "---\nlang: %s\n---\n\n# Un\n\nDes mots.\n\nD'autres.\n\n# Deux\n\nEt encore.\n" language))
        (imprimeur-test-cdp-wait browser "document.querySelector('#imprimeur-main > h1') !== null")
        (should (eq (imprimeur-test-cdp-eval browser "getComputedStyle(document.querySelector('#imprimeur-main > h1'), '::before').content !== 'none'")
                    counted))
        (should (eq (imprimeur-test-cdp-eval browser "parseFloat(getComputedStyle(document.querySelector('#imprimeur-main p')).textIndent) > 0")
                    indented))))))

(ert-deftest imprimeur-skin-ecrivain-takes-no-option-from-a-document ()
  (imprimeur-skin-ecrivain-test-with
      (_buffer browser "doc.md"
               (concat "---\ntitle: T\nsheet: pages\ndata-ecrivain-sheet: pages\n---\n\n"
                       "Words.\n\n<div data-ecrivain-sheet=\"pages\">Rien.</div>\n"))
    (imprimeur-test-cdp-wait browser "document.getElementById('imprimeur-main').textContent.includes('Rien')")
    (should-not (imprimeur-skin-ecrivain-test-attributes browser))))

(ert-deftest imprimeur-skin-ecrivain-is-chosen-by-the-configuration-of-its-readme ()
  (let* ((readme (with-temp-buffer
                   (insert-file-contents (expand-file-name "imprimeur-skin-ecrivain/README.md" repo-test-root))
                   (buffer-string)))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'ecrivain\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-ecrivain-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-ecrivain)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"ecrivain\" (imprimeur-skin-get \"ecrivain\") (imprimeur-skin-configured \"ecrivain\" (imprimeur-skin-get \"ecrivain\")) nil))"))))
    (should (equal (car result) 0))
    ;; Every option at its default, so the root stays bare.
    (should (string-suffix-p "ecrivain[]" (cdr result)))))

(ert-deftest imprimeur-skin-ecrivain-filter-stays-within-the-limit-of-complexity ()
  (let ((luacheck (imprimeur-test-require "luacheck")))
    (should (equal (call-process luacheck nil nil nil "--no-config" "--no-color"
                                 "--max-cyclomatic-complexity" "10" "--globals" "pandoc" "--"
                                 (expand-file-name "imprimeur-skin-ecrivain/assets/filter.lua" repo-test-root))
                   0))))

;;; imprimeur-skin-ecrivain-test.el ends here
