;;; imprimeur-skin-xix-test.el --- Tests of the skin XIX  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 019:
;;
;; "A reader installs one package, presses M-g s, chooses XIX": the package's
;; autoloads register the skin once imprimeur-skin loads, with nothing printed,
;; and the skin stays out while nothing loads imprimeur-skin.
;;
;; Acceptance 4: with XIX chosen, on real pandoc in Chromium, an Org and a gfm French
;; document each show the vermilion title, on paper and in candlelight, and a
;; two-line lettrine in vermilion with the plain capital, whose true letter copies
;; and is found; U+202F stands inside « »; each block keeps its line in an anchored
;; Org document, and the source and the page follow each other's scrolling.
;;
;; Acceptance 5: each option's every value changes what it says, and a value at
;; its default leaves the root bare; a filter never receives an option from a document.
;;
;; "XIX's defaults are the owner's" (docs of the skin's README): Junicode first, its
;; ligatures, a measure of 30, and each choice the hand-written lists below hold.
;;
;; Acceptance 8: the README's configuration for XIX, loaded in a scratch Emacs,
;; chooses the skin.
;;
;; Plan 020: a plain French Markdown note, a title, a paragraph and a lower heading,
;; takes a lettrine on its first paragraph, with no empty block of the title page.
;; `historical', which draws as the default under Junicode, says so in its label.
;;
;; Plan 021, acceptance 3: a word breaks by a soft hyphen, a selection of its paragraph
;; copies with no U+00AD, and search finds the broken word.
;;
;; Plan 027: `text-face' also offers Bodoni Moda at its optical sizes, Playfair, Playfair
;; Display and Old Standard; each stands first in its stack, with the optical cuts by the
;; size of what they draw, and a face that is not installed falls back quietly.  That each
;; draws in its face takes the fonts of fonts.nix, which `make check' does not build.
;;
;; The tests register XIX in a registry of their own, as the other tests see the plain page
;; alone without XIX on the load path (acceptance 2).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-skin-xix-test-file
  (expand-file-name "imprimeur-skin-xix/imprimeur-skin-xix.el" repo-test-root)
  "The skin's main file.")

(defconst imprimeur-skin-xix-test-vermilion '((light . "rgb(163, 42, 31)") (dark . "rgb(224, 122, 85)"))
  "The owner's vermilion, on paper and in candlelight.")

(defconst imprimeur-skin-xix-test-faces
  '(("bodoni-moda" . "Bodoni Moda") ("bodoni-moda-optical" . "XIX Bodoni 20")
    ("playfair" . "Playfair") ("playfair-display" . "Playfair Display")
    ("old-standard" . "Old Standard") ("theano" . "Theano Didot")
    ("libertinus" . "Libertinus Serif") ("eb-garamond" . "EB Garamond 12"))
  "The text faces away from the default, with the family each must put first.")

(defconst imprimeur-skin-xix-test-measures
  '("24" "24-5" "25" "25-5" "26" "26-5" "27" "27-5" "28" "28-5" "29" "29-5" "30" "30-5" "31" "31-5" "32"
    "32-5" "33" "33-5" "34" "34-5" "35" "35-5" "36" "36-5" "37" "37-5" "38" "38-5" "39" "39-5" "40")
  "The measures, by hand: from 24 to 40 by a half.")

(defconst imprimeur-skin-xix-test-org
  (concat "#+TITLE: Essai\n#+AUTHOR: Un auteur\n#+LANGUAGE: fr\n\n"
          "* Première\n\nÀ la première ligne, « bien » dit-il; le mot suit.\n\nUn second alinéa.\n\n"
          "* Seconde\n\nQuand la queue descend.\n")
  "A French document in Org, with chapters and a lettrine on an accented capital.")

(defconst imprimeur-skin-xix-test-gfm
  (concat "---\ntitle: Essai\nauthor: Un auteur\nlang: fr\n---\n\n"
          "# Première\n\nÀ la première ligne, « bien » dit-il; le mot suit.\n\nUn second alinéa.\n\n"
          "# Seconde\n\nQuand la queue descend.\n")
  "The same document in GitHub Markdown.")

(defmacro imprimeur-skin-xix-test-with (spec &rest body)
  "Run BODY with XIX as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT, in
the selected Emacs window, in `imprimeur-mode'; BROWSER shows its page."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'xix)
              (imprimeur-skin-options nil)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (find-file-noselect (expand-file-name ,file root))))
         (load imprimeur-skin-xix-test-file nil t)
         (unwind-protect
             (save-window-excursion
               (switch-to-buffer ,buffer)
               (imprimeur-test-cdp-with-browser ,browser
                 (imprimeur-mode 1)
                 (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
                 (imprimeur-test-wait-for
                  (lambda () (imprimeur-test-cdp-eval ,browser "document.documentElement.dataset.revision")))
                 ,@body))
           (with-current-buffer ,buffer (set-buffer-modified-p nil))
           (kill-buffer ,buffer))))))

(defun imprimeur-skin-xix-test-attributes (browser)
  "Return the names of the data-xix attributes on the root of BROWSER's page."
  (append (imprimeur-test-cdp-eval
           browser "[...document.documentElement.attributes].map((a) => a.name).filter((n) => n.startsWith('data-xix'))")
          nil))

(defun imprimeur-skin-xix-test-style (browser selector property &optional pseudo)
  "Return the computed PROPERTY of SELECTOR's PSEUDO in BROWSER's page."
  (imprimeur-test-cdp-eval
   browser (format "getComputedStyle(document.querySelector(%S), %s)[%S]"
                   selector (if pseudo (format "%S" pseudo) "null") property)))

(defun imprimeur-skin-xix-test-choose (buffer browser id value)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-xix-%s') === %s"
                   id (if (equal value (plist-get (cdr (assq (intern id) (plist-get (imprimeur-skin-get "xix") :options)))
                                                  :default))
                          "null"
                        (format "%S" value)))))

(ert-deftest imprimeur-skin-xix-registers-from-its-autoloads-alone ()
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-xix-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-xix-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-xix)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S \" (and (imprimeur-skin-get \"xix\") t)))"))))
    (should (equal (car result) 0))
    (let ((printed (substring (cdr result) (+ (string-search "MARK" (cdr result)) 5))))
      (should (equal printed "before=nil after=t ")))))

(ert-deftest imprimeur-skin-xix-keeps-the-owner-s-defaults-and-choices ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-xix-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "xix"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "XIX"))
      (should (plist-get manifest :smart))
      (should (eq (plist-get manifest :notes) 'section))
      (should (equal (mapcar #'car options) '(text-face ligatures measure)))
      (should (equal (plist-get (alist-get 'text-face options) :default) "junicode"))
      (should (equal (plist-get (alist-get 'ligatures options) :default) "discretionary"))
      (should (equal (plist-get (alist-get 'measure options) :default) "30"))
      (should (equal (mapcar #'car (plist-get (alist-get 'text-face options) :choices))
                     (cons "junicode" (mapcar #'car imprimeur-skin-xix-test-faces))))
      (should (equal (mapcar #'car (plist-get (alist-get 'ligatures options) :choices))
                     '("none" "common" "discretionary" "historical")))
      (let ((label (cdr (assoc "historical" (plist-get (alist-get 'ligatures options) :choices)))))
        (should (string-search "default" label))
        (should (string-search "Junicode" label)))
      (should (equal (mapcar #'car (plist-get (alist-get 'measure options) :choices))
                     imprimeur-skin-xix-test-measures)))))

(defun imprimeur-skin-xix-test-french (file text)
  "Check the French page of FILE, holding TEXT."
  (imprimeur-skin-xix-test-with (buffer browser file text)
    (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.skin") "xix"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    ;; The title, and the author after it.
    (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-title').textContent") "Essai"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xix-author').textContent") "Un auteur"))
    ;; The plain capital, the true letter, and what the rest of the page says of it.
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xix-capitale').dataset.capitale") "A"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xix-lettre').textContent") "À"))
    (should (equal (imprimeur-skin-xix-test-style browser ".xix-lettrine > p" "initialLetter" "::first-letter") "2"))
    (should (string-prefix-p "À la première" (plist-get (imprimeur-test-cdp-copy browser ".xix-lettrine > p") :text)))
    (imprimeur-test-cdp-eval browser "getSelection().removeAllRanges()")
    (should (eq (imprimeur-test-cdp-eval browser "window.find('À la première')") t))
    ;; One lettrine by chapter, with the class of a capital with a tail.
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xix-lettrine').length") 2))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xix-queue').length") 1))
    ;; The narrow spaces, in the text as a reader's copy holds it.
    (should (imprimeur-test-cdp-eval
             browser "document.getElementById('imprimeur-main').textContent.includes('«\u202Fbien\u202F»')"))
    (should (imprimeur-test-cdp-eval
             browser "document.getElementById('imprimeur-main').textContent.includes('dit-il\u202F;')"))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-xix-sets-a-french-org-document ()
  (imprimeur-skin-xix-test-french "doc.org" imprimeur-skin-xix-test-org))

(ert-deftest imprimeur-skin-xix-sets-a-french-markdown-document ()
  (imprimeur-skin-xix-test-french "doc.md" imprimeur-skin-xix-test-gfm))

(ert-deftest imprimeur-skin-xix-opens-a-plain-note-with-a-lettrine ()
  (imprimeur-skin-xix-test-with (_buffer browser "doc.md" "# Titre\n\nÀ la ligne.\n\nPuis.\n\n## Sec\n\nLa suite.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-title').textContent") "Titre"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xix-lettrine').length") 1))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xix-lettrine > p').textContent")
                   "À la ligne."))
    (should (eq (imprimeur-test-cdp-eval browser "document.querySelector('.xix-titre') !== null") t))))

(ert-deftest imprimeur-skin-xix-gives-no-lettrine-to-a-note-that-opens-otherwise ()
  (dolist (text '("# Titre\n" "# Titre\n\n> Cité.\n\nLa suite.\n"))
    (ert-info (text)
      (imprimeur-skin-xix-test-with (_buffer browser "doc.md" text)
        (imprimeur-test-cdp-wait browser "document.getElementById('imprimeur-title').textContent === 'Titre'")
        (should (eq (imprimeur-test-cdp-eval browser "document.querySelector('.xix-lettrine') === null") t))
        (should (eq (imprimeur-test-cdp-eval browser "document.querySelector('.xix-titre') !== null") t))))))

(ert-deftest imprimeur-skin-xix-hyphenates-and-copies-the-word-whole ()
  (imprimeur-skin-xix-test-with
      (_buffer browser "doc.org" "#+TITLE: Essai\n#+LANGUAGE: fr\n\n* Un\n\nLa typographie du livre.\n\nUne bibliothèque.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    (should (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-main').textContent.includes('ty\u00ADpo\u00ADgra\u00ADphie')"))
    (let ((copied (imprimeur-test-cdp-copy browser ".xix-lettrine > p")))
      (should (eq (plist-get copied :taken) t))
      (should (equal (plist-get copied :text) "La typographie du livre."))
      (should-not (string-search "\u00AD" (plist-get copied :html))))
    (imprimeur-test-cdp-eval browser "getSelection().removeAllRanges()")
    (should (eq (imprimeur-test-cdp-eval browser "window.find('typographie')") t))
    (should (eq (imprimeur-test-cdp-eval browser "window.find('bibliothèque')") t))))

(ert-deftest imprimeur-skin-xix-rags-a-language-with-no-patterns ()
  (pcase-dolist (`(,language . ,align) '(("fr" . "justify") ("en" . "justify") ("de" . "start")))
    (ert-info (language)
      (imprimeur-skin-xix-test-with
          (_buffer browser "doc.md" (format "---\ntitle: Essai\nlang: %s\n---\n\nEin Wort.\n\nEin anderes.\n" language))
        (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
        (should (equal (imprimeur-skin-xix-test-style browser "main > :last-child p, main > p:last-child" "textAlign") align))))))

(ert-deftest imprimeur-skin-xix-paints-the-title-and-lettrine-in-vermilion ()
  (pcase-dolist (`(,appearance . ,colour) imprimeur-skin-xix-test-vermilion)
    (ert-info ((symbol-name appearance))
      (let ((imprimeur-appearance appearance))
        (imprimeur-skin-xix-test-with (_buffer browser "doc.org" imprimeur-skin-xix-test-org)
          (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
          (imprimeur-test-wait-for
           (lambda () (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.appearance")
                             (symbol-name appearance))))
          (should (equal (imprimeur-skin-xix-test-style browser "#imprimeur-title" "color") colour))
          (should (equal (imprimeur-skin-xix-test-style browser ".xix-lettrine > p" "color" "::first-letter")
                         colour)))))))

(ert-deftest imprimeur-skin-xix-keeps-the-lines-of-an-org-document ()
  (imprimeur-skin-xix-test-with (_buffer browser "doc.org" imprimeur-skin-xix-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    (should (equal (imprimeur-test-cdp-eval
                    browser "[...document.querySelectorAll('main > [data-line]')].map((block) => block.dataset.line)")
                   ["5" "7" "9" "11" "13"]))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xix-lettrine').dataset.line") "7"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('[data-imprimeur-line]').length") 0))))

(defun imprimeur-skin-xix-test-paragraphs ()
  "Return a long Org document whose paragraphs open chapters, each called Paragraph N."
  (concat "#+TITLE: Essai\n#+LANGUAGE: fr\n\n"
          (mapconcat (lambda (number)
                       (format "* Chapitre %d\n\nParagraph %d.\n\nAnother paragraph of this chapter.\n\n" number number))
                     (number-sequence 1 60) "")))

(ert-deftest imprimeur-skin-xix-follows-the-source-to-a-lettrine-and-back ()
  (imprimeur-skin-xix-test-with (buffer browser "doc.org" (imprimeur-skin-xix-test-paragraphs))
    (let ((top "[...document.querySelectorAll('#imprimeur-main > *')]
.find((block) => block.textContent.includes('Paragraph 41.')).getBoundingClientRect().top")
          (target "Paragraph 41."))
      (imprimeur-test-cdp-wait browser "document.querySelectorAll('.xix-lettrine').length === 60")
      ;; A command moves the source, and the lettrine's block reaches the top.
      (let ((overriding-local-map
             (define-keymap "<f12>" (lambda ()
                                      (interactive)
                                      (save-excursion
                                        (goto-char (point-min))
                                        (search-forward target)
                                        (set-window-start nil (pos-bol)))))))
        (execute-kbd-macro [f12]))
      (imprimeur-test-wait-for (lambda () (<= (abs (imprimeur-test-cdp-eval browser top)) 2)))
      ;; The wheel moves the page, and the source follows it.
      (let ((start (window-start)))
        (imprimeur-test-cdp-wheel browser 1500)
        (imprimeur-test-wait-for (lambda () (> (window-start) start))))
      (should (eq (current-buffer) buffer)))))

(ert-deftest imprimeur-skin-xix-changes-the-face-by-its-option ()
  (imprimeur-skin-xix-test-with (buffer browser "doc.org" imprimeur-skin-xix-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    (should-not (imprimeur-skin-xix-test-attributes browser))
    (should (string-match-p "\\`\"XIX fine\", \"XIX Junicode\", Junicode,"
                            (imprimeur-skin-xix-test-style browser "#imprimeur-main" "fontFamily")))
    (pcase-dolist (`(,value . ,family) imprimeur-skin-xix-test-faces)
      (ert-info (value)
        (imprimeur-skin-xix-test-choose buffer browser "text-face" value)
        (let ((stack (imprimeur-skin-xix-test-style browser "#imprimeur-main" "fontFamily")))
          (should-not (string-search "Junicode" stack))
          ;; The first family of the stack, after the one that holds U+202F alone.
          (should (equal family (car (split-string (replace-regexp-in-string "\\`\"XIX fine\", " "" stack)
                                                   "\"" t ", ")))))))
    (imprimeur-skin-xix-test-choose buffer browser "text-face" "junicode")
    (should-not (imprimeur-skin-xix-test-attributes browser))))

(defconst imprimeur-skin-xix-test-sizes
  (concat "#+TITLE: Essai\n#+LANGUAGE: fr\n\n* Un\n\nUn mot[fn:1], et *un autre*.\n\nUn second alinéa.\n\n"
          "#+CAPTION: Un tableau\n| a | b |\n\n[fn:1] Une note, et *un mot fort*.\n")
  "A French document in Org with a title, paragraphs, a note and a caption.")

(defun imprimeur-skin-xix-test-first-family (browser selector &optional pseudo)
  "Return the first family of SELECTOR's PSEUDO in BROWSER's page, past XIX fine."
  (car (split-string (replace-regexp-in-string
                      "\\`\"XIX fine\", " ""
                      (imprimeur-skin-xix-test-style browser selector "fontFamily" pseudo))
                     "\"" t ", ")))

(ert-deftest imprimeur-skin-xix-takes-bodoni-s-optical-cuts-by-size ()
  (imprimeur-skin-xix-test-with (buffer browser "doc.org" imprimeur-skin-xix-test-sizes)
    (imprimeur-test-cdp-wait browser "document.querySelector('.footnotes') !== null")
    (pcase-dolist (`(,value ,title ,text ,note)
                   '(("bodoni-moda-optical" "XIX Bodoni 40" "XIX Bodoni 20" "XIX Bodoni 17")
                     ("bodoni-moda" "Bodoni Moda" "Bodoni Moda" "Bodoni Moda")))
      (ert-info (value)
        (imprimeur-skin-xix-test-choose buffer browser "text-face" value)
        (pcase-dolist (`(,selector ,pseudo ,family)
                       `(("#imprimeur-title" nil ,title)
                         (".xix-lettrine > p" "::first-letter" ,title)
                         ("main h1" nil ,title)
                         (".xix-lettrine + p" nil ,text)
                         (".xix-lettrine strong" nil ,text)
                         (".footnotes li" nil ,note)
                         (".footnotes strong" nil ,note)
                         ("caption" nil ,note)
                         ("caption" "::before" ,note)))
          (ert-info (selector)
            (should (equal (imprimeur-skin-xix-test-first-family browser selector pseudo) family))))))))

(ert-deftest imprimeur-skin-xix-keeps-its-code-font-in-a-note-under-the-optical-cuts ()
  (imprimeur-skin-xix-test-with (buffer browser "doc.org" "#+TITLE: Essai\n\n* Un\n\nUn mot[fn:1].\n\n[fn:1] Une note, =un code=.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.footnotes code') !== null")
    (imprimeur-skin-xix-test-choose buffer browser "text-face" "bodoni-moda-optical")
    (should (equal (imprimeur-skin-xix-test-first-family browser ".footnotes code") "Courier Prime"))))

(ert-deftest imprimeur-skin-xix-falls-back-quietly-without-the-new-faces ()
  ;; Only the fonts of the development shell, whatever else this machine has.
  (let* ((configuration (make-temp-file
                         "fonts" nil ".conf"
                         (format "<fontconfig><dir>%s</dir><cachedir>%s</cachedir></fontconfig>\n"
                                 (getenv "IMPRIMEUR_TEST_FONTS") temporary-file-directory)))
         (process-environment (cons (concat "FONTCONFIG_FILE=" configuration) process-environment)))
    (imprimeur-skin-xix-test-with (buffer browser "doc.org" imprimeur-skin-xix-test-org)
      (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
      (imprimeur-test-cdp-call browser "DOM.enable")
      (imprimeur-test-cdp-call browser "CSS.enable")
      (dolist (value '("bodoni-moda-optical" "playfair" "playfair-display" "old-standard"))
        (ert-info (value)
          (imprimeur-skin-xix-test-choose buffer browser "text-face" value)
          ;; The paragraph draws, in what the machine has, with nothing said of it.
          (let* ((root (plist-get (imprimeur-test-cdp-call browser "DOM.getDocument") :root))
                 (node (imprimeur-test-cdp-call
                        browser "DOM.querySelector"
                        `(:nodeId ,(plist-get root :nodeId) :selector ".xix-lettrine > p")))
                 (fonts (plist-get (imprimeur-test-cdp-call browser "CSS.getPlatformFontsForNode" node) :fonts)))
            (should (> (length fonts) 0))
            (should (cl-every (lambda (font) (string-prefix-p "DejaVu" (plist-get font :familyName))) fonts)))
          (should-not (imprimeur-test-cdp-errors browser)))))))

(ert-deftest imprimeur-skin-xix-keeps-historical-to-the-faces-away-from-junicode ()
  (imprimeur-skin-xix-test-with (buffer browser "doc.org" imprimeur-skin-xix-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    (imprimeur-skin-xix-test-choose buffer browser "ligatures" "historical")
    (pcase-dolist (`(,value . ,_family) imprimeur-skin-xix-test-faces)
      (ert-info (value)
        (imprimeur-skin-xix-test-choose buffer browser "text-face" value)
        (should (string-suffix-p " historical-ligatures"
                                 (imprimeur-skin-xix-test-style browser "#imprimeur-main" "fontVariantLigatures")))))))

(ert-deftest imprimeur-skin-xix-changes-the-ligatures-by-their-option ()
  (imprimeur-skin-xix-test-with (buffer browser "doc.org" imprimeur-skin-xix-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    (let ((default "common-ligatures discretionary-ligatures no-historical-ligatures"))
      (should (equal (imprimeur-skin-xix-test-style browser "#imprimeur-main" "fontVariantLigatures") default))
      (pcase-dolist (`(,value . ,ligatures)
                     '(("none" . "none")
                       ("common" . "common-ligatures no-discretionary-ligatures no-historical-ligatures")
                       ;; Junicode's own historical set would rewrite French, so it stays off.
                       ("historical" . "common-ligatures discretionary-ligatures no-historical-ligatures")))
        (ert-info (value)
          (imprimeur-skin-xix-test-choose buffer browser "ligatures" value)
          (should (equal (imprimeur-skin-xix-test-style browser "#imprimeur-main" "fontVariantLigatures")
                         ligatures))))
      ;; Under another face, historical says what it says.
      (imprimeur-skin-xix-test-choose buffer browser "text-face" "libertinus")
      (should (equal (imprimeur-skin-xix-test-style browser "#imprimeur-main" "fontVariantLigatures")
                     "common-ligatures discretionary-ligatures historical-ligatures"))
      (imprimeur-skin-xix-test-choose buffer browser "text-face" "junicode")
      (imprimeur-skin-xix-test-choose buffer browser "ligatures" "discretionary")
      (should-not (imprimeur-skin-xix-test-attributes browser))
      (should (equal (imprimeur-skin-xix-test-style browser "#imprimeur-main" "fontVariantLigatures") default)))))

(ert-deftest imprimeur-skin-xix-changes-the-measure-by-its-option ()
  (imprimeur-skin-xix-test-with (buffer browser "doc.org" imprimeur-skin-xix-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    (let ((size (string-to-number (imprimeur-test-cdp-eval browser "getComputedStyle(document.documentElement).fontSize"))))
      (dolist (value imprimeur-skin-xix-test-measures)
        (ert-info (value)
          (imprimeur-skin-xix-test-choose buffer browser "measure" value)
          ;; The column of text, and 1 rem of padding on each side.
          (should (= (string-to-number (imprimeur-skin-xix-test-style browser "#imprimeur-main" "maxInlineSize"))
                     (* size (+ 2 (string-to-number (string-replace "-5" ".5" value))))))))
      (imprimeur-skin-xix-test-choose buffer browser "measure" "30")
      (should-not (imprimeur-skin-xix-test-attributes browser)))))

(ert-deftest imprimeur-skin-xix-takes-no-option-from-a-document ()
  (imprimeur-skin-xix-test-with
      (_buffer browser "doc.md"
               (concat "---\ntitle: Essai\nlang: fr\ntext-face: theano\nmeasure: 24\nligatures: none\n"
                       "data-xix-text-face: theano\nimprimeur-option-text-face: theano\n---\n\n"
                       "# Un\n\nUn mot.\n\n<div data-xix-measure=\"24\">Rien.</div>\n"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.xix-lettrine') !== null")
    (should-not (imprimeur-skin-xix-test-attributes browser))
    (should (string-match-p "\"XIX Junicode\"" (imprimeur-skin-xix-test-style browser "#imprimeur-main" "fontFamily")))
    (should-not (string-search "calc" (imprimeur-skin-xix-test-style browser "#imprimeur-main" "maxInlineSize")))
    (should (= (string-to-number (imprimeur-skin-xix-test-style browser "#imprimeur-main" "maxInlineSize"))
               (* 32 (string-to-number (imprimeur-test-cdp-eval
                                        browser "getComputedStyle(document.documentElement).fontSize")))))))

(ert-deftest imprimeur-skin-xix-is-chosen-by-the-configuration-of-the-readme ()
  (let* ((readme (with-temp-buffer
                   (insert-file-contents (expand-file-name "README.md" repo-test-root))
                   (buffer-string)))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'xix\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-xix-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-xix)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"xix\" (imprimeur-skin-get \"xix\") (imprimeur-skin-configured \"xix\" (imprimeur-skin-get \"xix\")) nil))"))))
    (should (equal (car result) 0))
    (should (string-suffix-p "xix[[data-xix-measure 28]]" (cdr result)))))

;;; imprimeur-skin-xix-test.el ends here
