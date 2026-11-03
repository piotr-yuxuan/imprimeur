;;; imprimeur-minitoc-test.el --- Tests of the page's minitocs, in headless Chromium  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements: docs/minitoc-rules.md, and plan 006.
;;
;; Acceptance 2: rendered with real pandoc, the page's model of each document of
;; tests/fixtures/minitoc equals the page view of its NAME.model.json, as that file
;; defines it: `narrowing' has none, and in `comment-noexport' an introduction that is
;; only a dropped subtree is none.  A heading in raw HTML is no heading of the outline.
;;
;; Acceptance 3: with the Emacs section across the 25% line, the pill reads
;; "Requirements" with `aria-current' on "Emacs"; with sync on and Emacs point in
;; "Pandoc", the pill marks "Pandoc" whatever the scroll, until sync goes off; buttons
;; stand exactly at run anchors; opening A then B leaves only B open; Esc closes it.  In
;; "This section" at depth 1, the list is the direct descendants of the section in view,
;; and changes when the reader scrolls into another; in "Document" at depth 2, it holds
;; every heading of levels 1 and 2; `+' and `-' change it, in place, with the reader's
;; place unmoved, by the rules' steps.
;;
;; Plan 006, "Decisions": titles reach the page as text; a revision keeps its blocks, as
;; the block diff never sees what the minitocs add, and a change of scope and an open
;; inline minitoc outlast it.  A key with nothing to do is declined, for a skin or Emacs.
;; A key takes the reader to a heading, and Emacs hears of it as of the wheel.

;;; Code:

(require 'ert)
(require 'seq)
(require 'json)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-minitoc-test-fixtures
  (expand-file-name "tests/fixtures/minitoc" repo-test-root)
  "The documents and models of the rules, written by hand from them.")

(defconst imprimeur-minitoc-test-model
  "(async () => {
  const script = document.querySelector('script[type=module]').src;
  const { readOutline } = await import(script.replace('runtime.mjs', 'minitoc-ui.mjs'));
  const root = document.documentElement;
  const title = document.getElementById('imprimeur-title').textContent;
  return JSON.stringify(readOutline(document.getElementById('imprimeur-main'), root.dataset.format, title).model);
})()"
  "What gives the model of the page shown, from the module that the page itself runs.")

(defun imprimeur-minitoc-test-parse (text)
  "Return the JSON of TEXT as a plist, every false and null one value of its own."
  (json-parse-string text :object-type 'plist :array-type 'list :null-object :null :false-object :false))

(defun imprimeur-minitoc-test-open (browser buffer)
  "Turn the page of BUFFER on, open it in BROWSER, and wait for its first revision."
  (with-current-buffer buffer (imprimeur-mode 1))
  (imprimeur-test-cdp-navigate browser (with-current-buffer buffer (imprimeur-url)))
  (imprimeur-test-cdp-wait browser "document.documentElement.dataset.revision >= 1"))

(defun imprimeur-minitoc-test-page-view (name node)
  "Return NODE, of the fixture NAME, as a page sees it: see \"The page view\"."
  (let ((children (mapcar (lambda (child) (imprimeur-minitoc-test-page-view name child))
                          (plist-get node :children)))
        (node (copy-sequence node)))
    (plist-put node :children children)
    (when (and (equal name "comment-noexport") (memq (plist-get node :id) '(0 6)))
      (plist-put node :intro :false))
    node))

(ert-deftest imprimeur-minitoc-the-page-reads-the-model-of-each-fixture ()
  (imprimeur-test-require "pandoc")
  (let ((imprimeur-browser-program imprimeur-test-fake-browser)
        (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
        (documents (seq-remove (lambda (file) (string-prefix-p "narrowing." file))
                               (directory-files imprimeur-minitoc-test-fixtures nil "\\.\\(?:org\\|md\\)\\'"))))
    (should (> (length documents) 20))
    (imprimeur-test-cdp-with-browser browser
      (dolist (file documents)
        (ert-info (file)
          (let* ((text (with-temp-buffer
                         (insert-file-contents (expand-file-name file imprimeur-minitoc-test-fixtures))
                         (buffer-string)))
                 (root (repo-test-git-tree (list (cons file text))))
                 (buffer (find-file-noselect (expand-file-name file root)))
                 (name (file-name-sans-extension file))
                 (model (with-temp-buffer
                          (insert-file-contents (expand-file-name (concat name ".model.json")
                                                                  imprimeur-minitoc-test-fixtures))
                          (imprimeur-minitoc-test-parse (buffer-string)))))
            (unwind-protect
                (progn
                  (imprimeur-minitoc-test-open browser buffer)
                  (should (equal (plist-get (imprimeur-minitoc-test-parse
                                             (imprimeur-test-cdp-eval browser imprimeur-minitoc-test-model))
                                            :root)
                                 (imprimeur-minitoc-test-page-view name (plist-get model :root)))))
              (kill-buffer buffer))))))))

(defun imprimeur-minitoc-test-paragraphs (name)
  "Return enough paragraphs named NAME to take more than a view of the page."
  (mapconcat (lambda (number) (format "%s, paragraph %d, with some words in it.\n\n" name number))
             (number-sequence 1 30) ""))

(defun imprimeur-minitoc-test-document ()
  "Return an Org document with sections long enough to scroll through."
  (concat "#+title: A document\n\n"
          "* Installation\n** Requirements\n*** Emacs\n" (imprimeur-minitoc-test-paragraphs "Emacs")
          "*** Pandoc\n" (imprimeur-minitoc-test-paragraphs "Pandoc")
          "** Nix\n" (imprimeur-minitoc-test-paragraphs "Nix")
          "* Usage\n** Live preview\n" (imprimeur-minitoc-test-paragraphs "Preview")
          "** Skins\n" (imprimeur-minitoc-test-paragraphs "Skins")))

(defmacro imprimeur-minitoc-test-with (spec &rest body)
  "Run BODY with the page of a document open.
SPEC is (BUFFER BROWSER SYNC [FILE TEXT]): BUFFER visits FILE, by default an Org file of
`imprimeur-minitoc-test-document', and BROWSER shows its page, which follows
Emacs if SYNC is non-nil."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,sync ,file ,text) spec))
    `(let* ((imprimeur-browser-program imprimeur-test-fake-browser)
            (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
            (imprimeur-scroll-sync ,sync)
            (file ,(or file "doc.org"))
            (root (repo-test-git-tree (list (cons file ,(or text '(imprimeur-minitoc-test-document))))))
            (,buffer (find-file-noselect (expand-file-name file root))))
       (unwind-protect
           (imprimeur-test-cdp-with-browser ,browser
             (imprimeur-minitoc-test-open ,browser ,buffer)
             ,@body)
         (with-current-buffer ,buffer (set-buffer-modified-p nil))
         (kill-buffer ,buffer)))))

(defun imprimeur-minitoc-test-press (browser key &optional text)
  "Press KEY in BROWSER's page, a real key event, of TEXT if it has any."
  (dolist (type (if text '("keyDown" "keyUp") '("rawKeyDown" "keyUp")))
    (imprimeur-test-cdp-call browser "Input.dispatchKeyEvent"
                             `(:type ,type :key ,key ,@(and (equal type "keyDown") text (list :text text))))))

(defun imprimeur-minitoc-test-across (browser title share)
  "Scroll BROWSER's page, as no reader would, so that the heading TITLE stands at SHARE of the view."
  (imprimeur-test-cdp-eval
   browser
   (format "(() => {
  const heading = [...document.querySelectorAll('main :is(h1, h2, h3)')].find((one) => one.textContent === %S);
  window.scrollTo({ top: heading.getBoundingClientRect().top + scrollY - innerHeight * %s, behavior: 'instant' });
})()" title share)))

(defun imprimeur-minitoc-test-pill (browser)
  "Return what BROWSER's pill says: its section, and what it marks as current."
  (imprimeur-test-cdp-eval
   browser "(() => {
  const pill = document.querySelector('.imprimeur-minitoc-pill');
  return [pill.querySelector('.imprimeur-minitoc-section').textContent,
          pill.querySelector('[aria-current]')?.textContent ?? null];
})()"))

(defun imprimeur-minitoc-test-rows (browser)
  "Return the titles that BROWSER's popover lists, and the one with `aria-current'."
  (imprimeur-test-cdp-eval
   browser "(() => {
  const rows = [...document.querySelectorAll('.imprimeur-minitoc-popover li button')];
  return [rows.map((row) => row.textContent),
          rows.find((row) => row.hasAttribute('aria-current'))?.textContent ?? null];
})()"))

(defun imprimeur-minitoc-test-wait-pill (browser section current)
  "Wait until BROWSER's pill reads SECTION with CURRENT marked."
  (imprimeur-test-wait-for
   (lambda () (equal (imprimeur-minitoc-test-pill browser) (vector section current)))))

(ert-deftest imprimeur-minitoc-the-pill-goes-by-the-line-at-a-quarter-of-the-view ()
  (imprimeur-test-require "pandoc")
  (imprimeur-minitoc-test-with (_buffer browser nil)
    (imprimeur-minitoc-test-across browser "Emacs" "0.2")
    (imprimeur-minitoc-test-wait-pill browser "Requirements" "Emacs")
    (should (equal (imprimeur-minitoc-test-rows browser) [["Emacs" "Pandoc"] "Emacs"]))
    ;; Below that line, the next heading is not yet the active one; above it, it is.
    (imprimeur-minitoc-test-across browser "Pandoc" "0.3")
    (imprimeur-minitoc-test-wait-pill browser "Requirements" "Emacs")
    (imprimeur-minitoc-test-across browser "Pandoc" "0.2")
    (imprimeur-minitoc-test-wait-pill browser "Requirements" "Pandoc")
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-minitoc-the-pill-follows-point-while-sync-is-on ()
  (imprimeur-test-require "pandoc")
  (imprimeur-minitoc-test-with (buffer browser 'both)
    (with-current-buffer buffer
      (goto-char (point-min))
      (search-forward "Pandoc, paragraph 3")
      (imprimeur-sync--window-moved))
    (imprimeur-minitoc-test-wait-pill browser "Requirements" "Pandoc")
    ;; Whatever the scroll: a scroll that no input caused tells Emacs nothing.
    (imprimeur-minitoc-test-across browser "Live preview" "0.1")
    (accept-process-output nil 0.2)
    (should (equal (imprimeur-minitoc-test-pill browser) ["Requirements" "Pandoc"]))
    ;; Point alone moves, and it moves the pill.
    (with-current-buffer buffer
      (search-backward "Emacs, paragraph 3")
      (imprimeur-sync--window-moved))
    (imprimeur-minitoc-test-wait-pill browser "Requirements" "Emacs")
    ;; With sync off, the page has its own place.
    (imprimeur-minitoc-test-across browser "Live preview" "0.1")
    (with-current-buffer buffer (imprimeur-follow-mode -1))
    (imprimeur-minitoc-test-wait-pill browser "Usage" "Live preview")))

(ert-deftest imprimeur-minitoc-buttons-stand-at-run-anchors-with-one-open ()
  (imprimeur-test-require "pandoc")
  (imprimeur-minitoc-test-with (_buffer browser nil)
    (let ((buttoned "[...document.querySelectorAll('main :is(h1, h2, h3):has(> .imprimeur-minitoc-button)')].map((one) => one.textContent)")
          (click "document.querySelector('[id=\"doc-%s\"] > button').click()")
          (inline "[...document.querySelectorAll('main nav button')].map((one) => one.textContent)")
          (expanded "[...document.querySelectorAll('main [aria-expanded=true]')].map((one) => one.parentNode.textContent)"))
      ;; Requirements is a merged heading, and the others have too few children.
      (should (equal (imprimeur-test-cdp-eval browser buttoned) ["Installation" "Usage"]))
      ;; R3: the button says how many entries, and its words are no text of the heading's.
      (should (equal (imprimeur-test-cdp-eval
                      browser "getComputedStyle(document.querySelector('[id=\"doc-installation\"] > button'), '::after').content")
                     "\"▸ 2\""))
      (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('doc-installation').textContent") "Installation"))
      ;; Opening A shows its entries, with the merged heading's children, after its heading.
      (imprimeur-test-cdp-eval browser (format click "installation"))
      (should (equal (imprimeur-test-cdp-eval browser inline) ["Requirements" "Emacs" "Pandoc" "Nix"]))
      (should (eq (imprimeur-test-cdp-eval browser "document.getElementById('doc-installation').nextElementSibling.localName === 'nav'") t))
      (should (equal (imprimeur-test-cdp-eval browser expanded) ["Installation"]))
      ;; Opening B then leaves only B open.
      (imprimeur-test-cdp-eval browser (format click "usage"))
      (should (equal (imprimeur-test-cdp-eval browser inline) ["Live preview" "Skins"]))
      (should (equal (imprimeur-test-cdp-eval browser expanded) ["Usage"]))
      ;; Esc closes it, and then has nothing to do.
      (imprimeur-minitoc-test-press browser "Escape")
      (should (equal (imprimeur-test-cdp-eval browser inline) []))
      (should (equal (imprimeur-test-cdp-eval browser expanded) []))
      (should-not (imprimeur-test-cdp-eval browser "window.imprimeur.key('Escape')"))
      (should-not (imprimeur-test-cdp-errors browser)))))

(ert-deftest imprimeur-minitoc-the-popover-lists-the-scope-in-place ()
  (imprimeur-test-require "pandoc")
  (imprimeur-minitoc-test-with (_buffer browser nil)
    (let ((place "window.scrollY")
          (hidden "document.querySelector('.imprimeur-minitoc-popover').hidden")
          (expanded "document.querySelector('.imprimeur-minitoc-pill').getAttribute('aria-expanded')")
          (depth "document.querySelector('.imprimeur-minitoc-depth').textContent")
          (choose "[...document.querySelectorAll('.imprimeur-minitoc-scope button')].find((one) => one.textContent === %S).click()"))
      (imprimeur-minitoc-test-across browser "Emacs" "0.2")
      (imprimeur-minitoc-test-wait-pill browser "Requirements" "Emacs")
      ;; Closed, `+' and `-' are not the popover's, and in an Emacs window they zoom.
      (should-not (imprimeur-test-cdp-eval browser "window.imprimeur.key('+')"))
      (should (eq (imprimeur-test-cdp-eval browser hidden) t))
      (imprimeur-minitoc-test-press browser "t" "t")
      (should-not (imprimeur-test-cdp-eval browser hidden))
      (should (equal (imprimeur-test-cdp-eval browser expanded) "true"))
      (let ((before (imprimeur-test-cdp-eval browser place)))
        ;; This section at depth 1: the direct descendants of the section in view.
        (should (equal (imprimeur-minitoc-test-rows browser) [["Emacs" "Pandoc"] "Emacs"]))
        ;; A step as the rules say: Requirements goes no deeper than one level.
        (imprimeur-minitoc-test-press browser "+" "+")
        (should (string-search "all" (imprimeur-test-cdp-eval browser depth)))
        (imprimeur-minitoc-test-press browser "-" "-")
        (should (string-search "1" (imprimeur-test-cdp-eval browser depth)))
        ;; The document at depth 2: every heading of levels 1 and 2.
        (imprimeur-test-cdp-eval browser (format choose "Document"))
        (imprimeur-minitoc-test-press browser "+" "+")
        (should (equal (imprimeur-minitoc-test-rows browser)
                       [["Installation" "Requirements" "Nix" "Usage" "Live preview" "Skins"] "Requirements"]))
        (imprimeur-minitoc-test-press browser "-" "-")
        (should (equal (imprimeur-minitoc-test-rows browser) [["Installation" "Usage"] "Installation"]))
        (should (equal (imprimeur-test-cdp-eval browser place) before)))
      ;; It follows the reader's place, and scrolling into another changes the list.
      (imprimeur-test-cdp-eval browser (format choose "This section"))
      (should (equal (imprimeur-minitoc-test-rows browser) [["Emacs" "Pandoc"] "Emacs"]))
      (imprimeur-minitoc-test-across browser "Skins" "0.2")
      (imprimeur-test-wait-for
       (lambda () (equal (imprimeur-minitoc-test-rows browser) [["Live preview" "Skins"] "Skins"])))
      ;; Esc closes it, before anything else.
      (imprimeur-minitoc-test-press browser "Escape")
      (should (eq (imprimeur-test-cdp-eval browser hidden) t))
      (should (equal (imprimeur-test-cdp-eval browser expanded) "false"))
      (should-not (imprimeur-test-cdp-errors browser)))))

(ert-deftest imprimeur-minitoc-keys-take-the-reader-to-a-heading ()
  (imprimeur-test-require "pandoc")
  (imprimeur-minitoc-test-with (_buffer browser nil)
    (let ((at-top "(() => {
  const inset = 2;
  return [...document.querySelectorAll('main :is(h1, h2, h3)')].filter((one) => one.getBoundingClientRect().top <= inset).at(-1).textContent;
})()"))
      (imprimeur-minitoc-test-across browser "Emacs" "0")
      ;; Step by step, even with no point moving in Emacs.
      (imprimeur-minitoc-test-press browser "]" "]")
      (should (equal (imprimeur-test-cdp-eval browser at-top) "Pandoc"))
      ;; No entry further on, so the key is left for whoever has it.
      (should-not (imprimeur-test-cdp-eval browser "window.imprimeur.key(']')"))
      (imprimeur-minitoc-test-press browser "[" "[")
      (should (equal (imprimeur-test-cdp-eval browser at-top) "Emacs"))
      (should-not (imprimeur-test-cdp-eval browser "window.imprimeur.key('[')"))
      (imprimeur-minitoc-test-press browser "u" "u")
      (should (equal (imprimeur-test-cdp-eval browser at-top) "Requirements"))
      (imprimeur-minitoc-test-press browser "u" "u")
      (should (equal (imprimeur-test-cdp-eval browser at-top) "Installation"))
      (imprimeur-minitoc-test-press browser "u" "u")
      (should (equal (imprimeur-test-cdp-eval browser "window.scrollY") 0))
      (should-not (imprimeur-test-cdp-eval browser "window.imprimeur.key('u')"))
      ;; An entry of the popover goes there and closes it.
      (imprimeur-minitoc-test-press browser "t" "t")
      (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('.imprimeur-minitoc-popover li button')].find((one) => one.textContent === 'Pandoc').click()")
      (should (equal (imprimeur-test-cdp-eval browser at-top) "Pandoc"))
      (should (eq (imprimeur-test-cdp-eval browser "document.querySelector('.imprimeur-minitoc-popover').hidden") t)))))

(ert-deftest imprimeur-minitoc-a-move-reaches-emacs-as-the-wheel-does ()
  (imprimeur-test-require "pandoc")
  (imprimeur-minitoc-test-with (buffer browser 'both)
    (let ((session (buffer-local-value 'imprimeur--session buffer))
          (posted nil))
      (should session)
      (cl-letf* ((original (symbol-function 'imprimeur-sync-page-scrolled))
                 ((symbol-function 'imprimeur-sync-page-scrolled)
                  (lambda (line seq)
                    (push line posted)
                    (funcall original line seq))))
        (imprimeur-minitoc-test-press browser "t" "t")
        (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('.imprimeur-minitoc-popover li button')].find((one) => one.textContent === 'Usage').click()")
        (imprimeur-test-wait-for (lambda () posted))
        (should (= (car posted) (with-current-buffer buffer
                                  (save-excursion
                                    (goto-char (point-min))
                                    (search-forward "* Usage")
                                    (line-number-at-pos)))))))))

(ert-deftest imprimeur-minitoc-a-title-is-text ()
  (imprimeur-test-require "pandoc")
  (imprimeur-minitoc-test-with (_buffer browser nil "doc.md"
                                        "## One <img src=x onerror=\"window.ran=1\"> *two*\n\n## <b>Three</b> &amp; four\n")
    (imprimeur-test-cdp-eval browser "document.querySelector('.imprimeur-minitoc-popover').hidden = false")
    (should (equal (imprimeur-minitoc-test-rows browser) [["One two" "Three & four"] "Three & four"]))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('#imprimeur-minitoc img, #imprimeur-minitoc b, #imprimeur-minitoc em').length") 0))
    (should-not (imprimeur-test-cdp-eval browser "window.ran"))))

(ert-deftest imprimeur-minitoc-a-page-with-no-heading-has-no-pill ()
  (imprimeur-test-require "pandoc")
  (imprimeur-minitoc-test-with (_buffer browser nil "doc.md" "Words alone.\n")
    (should (eq (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-minitoc').hidden") t))
    (should (eq (imprimeur-test-cdp-eval browser "getComputedStyle(document.getElementById('imprimeur-minitoc')).display === 'none'") t))
    (should-not (imprimeur-test-cdp-eval browser "window.imprimeur.key('t')"))))

(ert-deftest imprimeur-minitoc-a-revision-leaves-the-blocks-to-the-diff ()
  (imprimeur-test-require "pandoc")
  (dolist (format '("org" "md"))
    (ert-info (format)
      (imprimeur-minitoc-test-with (buffer browser nil (concat "doc." format)
                                           (if (equal format "org")
                                               "* A\n** B\n** C\n\nWords.\n\n* D\n** E\n** F\n"
                                             "# A\n\n## B\n\n## C\n\nWords.\n\n# D\n\n## E\n\n## F\n"))
        (let ((anchor "doc-a"))
          (imprimeur-test-cdp-eval
           browser (format "(() => {
  const heading = document.getElementById(%S);
  heading.kept = 'kept';
  heading.querySelector('button').click();
  document.querySelector('.imprimeur-minitoc-scope button').click();
})()" anchor))
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert "\nMore words.\n"))
          (imprimeur-test-cdp-wait browser "document.documentElement.dataset.revision >= 2")
          ;; The diff kept the heading, which has one button still, and its minitoc is open.
          (should (equal (imprimeur-test-cdp-eval browser (format "document.getElementById(%S).kept" anchor)) "kept"))
          (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('main button[data-count]').length") 2))
          (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('main nav').length") 1))
          (should (equal (imprimeur-test-cdp-eval browser (format "document.getElementById(%S).nextElementSibling.localName" anchor)) "nav"))
          ;; The scope that the reader chose holds.
          (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.imprimeur-minitoc-scope button').ariaPressed") "true"))
          (should-not (imprimeur-test-cdp-errors browser)))))))

(provide 'imprimeur-minitoc-test)

;;; imprimeur-minitoc-test.el ends here
