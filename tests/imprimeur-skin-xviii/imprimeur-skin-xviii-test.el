;;; imprimeur-skin-xviii-test.el --- Tests of the skin XVIII  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 021:
;;
;; "Baskervville by default, no long s, fleuron bands, framed two-line lettrines, with every
;; workbench choice one M-g o away": the manifest's defaults and choices, by hand from
;; docs/work/planned/skin-defaults.md and the workbench's params.json.
;;
;; Acceptance 4: with XVIII chosen, on real pandoc, an Org and a gfm French document show the
;; band, the red title and the framed lettrine; each option's values change what they say,
;; and long s changes nothing under Baskervville and says so.  Acceptance 6: the filter is
;; within 10, by luacheck.
;;
;; What the filter does, by the trial's reports: a lettrine on the first paragraph of a
;; chapter, never after a sign, raising the capital without its diacritics while the document's
;; letter stays in the line, so that it copies and is found; a stop after headings of levels 1
;; and 2 out of what a minitoc reads; a year before 1900 as an imprint, the document's date
;; staying in the text.  A language with no patterns rags, and with no language a plate with
;; no caption takes no bare numeral.
;;
;; The tests register XVIII in a registry of their own, as the other tests see Minitel alone.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-skin-xviii-test-file
  (expand-file-name "imprimeur-skin-xviii/imprimeur-skin-xviii.el" repo-test-root)
  "The skin's main file.")

(defconst imprimeur-skin-xviii-test-vermilion '((light . "rgb(163, 42, 31)") (dark . "rgb(224, 122, 85)"))
  "The red of the title and the lettrine, on paper and in candlelight.")

(defconst imprimeur-skin-xviii-test-org
  (concat "#+TITLE: Essai\n#+SUBTITLE: Un sous-titre\n#+AUTHOR: Un auteur\n#+DATE: 1759\n#+LANGUAGE: fr\n\n"
          "* Première\n\nÀ la première ligne, « bien » dit-il; la typographie suit.\n\nUn second alinéa.\n\n"
          "* Seconde\n\nQuand la queue descend.\n")
  "A French document in Org, with chapters and a lettrine on an accented capital.")

(defconst imprimeur-skin-xviii-test-gfm
  (concat "---\ntitle: Essai\nsubtitle: Un sous-titre\nauthor: Un auteur\ndate: 1759\nlang: fr\n---\n\n"
          "# Première\n\nÀ la première ligne, « bien » dit-il; la typographie suit.\n\nUn second alinéa.\n\n"
          "# Seconde\n\nQuand la queue descend.\n")
  "The same document in GitHub Markdown.")

(defmacro imprimeur-skin-xviii-test-with (spec &rest body)
  "Run BODY with XVIII as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT, in
the selected Emacs window, in `imprimeur-mode'; BROWSER shows its page."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'xviii)
              (imprimeur-skin-options nil)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (find-file-noselect (expand-file-name ,file root))))
         (load imprimeur-skin-xviii-test-file nil t)
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

(defun imprimeur-skin-xviii-test-style (browser selector property &optional pseudo)
  "Return the computed PROPERTY of SELECTOR's PSEUDO in BROWSER's page."
  (imprimeur-test-cdp-eval
   browser (format "getComputedStyle(document.querySelector(%S), %s)[%S]"
                   selector (if pseudo (format "%S" pseudo) "null") property)))

(defun imprimeur-skin-xviii-test-attributes (browser)
  "Return the names of the data-xviii attributes on the root of BROWSER's page."
  (append (imprimeur-test-cdp-eval
           browser "[...document.documentElement.attributes].map((a) => a.name).filter((n) => n.startsWith('data-xviii'))")
          nil))

(defun imprimeur-skin-xviii-test-choose (buffer browser id value)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-xviii-%s') === %s"
                   id (if (equal value (plist-get (cdr (assq (intern id) (plist-get (imprimeur-skin-get "xviii") :options)))
                                                  :default))
                          "null"
                        (format "%S" value)))))

(ert-deftest imprimeur-skin-xviii-registers-from-its-autoloads-alone ()
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-xviii-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-xviii-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-xviii)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S \" (and (imprimeur-skin-get \"xviii\") t)))"))))
    (should (equal (car result) 0))
    (let ((printed (substring (cdr result) (+ (string-search "MARK" (cdr result)) 5))))
      (should (equal printed "before=nil after=t ")))))

(ert-deftest imprimeur-skin-xviii-keeps-the-owner-s-defaults-and-choices ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-xviii-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "xviii"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "XVIII"))
      (should (plist-get manifest :smart))
      (should (eq (plist-get manifest :notes) 'section))
      (pcase-dolist (`(,id ,default . ,choices)
                     '((face "baskervville" "baskervville" "junicode")
                       (long-s "off" "off" "on")
                       (bands "fleurons" "fleurons" "rinceau" "entrelacs" "perles" "filet")))
        (ert-info ((symbol-name id))
          (should (equal (plist-get (alist-get id options) :default) default))
          (should (equal (mapcar #'car (plist-get (alist-get id options) :choices)) choices))))
      (should (equal (mapcar #'car options) '(face long-s bands)))
      ;; Long s says that it applies to Junicode only.
      (should (string-search "Junicode only" (plist-get (alist-get 'long-s options) :label))))))

(defun imprimeur-skin-xviii-test-french (file text)
  "Check the French page of FILE, holding TEXT, on paper."
  (imprimeur-skin-xviii-test-with (_buffer browser file text)
    (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.skin") "xviii"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
    ;; The band over the title and over a chapter.
    (should (string-search "data:image/svg" (imprimeur-skin-xviii-test-style browser "#imprimeur-title" "maskImage" "::before")))
    (should (string-search "data:image/svg" (imprimeur-skin-xviii-test-style browser "h1:not(.unnumbered)" "maskImage" "::before")))
    ;; The title, and what the page does not hear of after it.
    (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-title').textContent") "Essai"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-sous-titre').textContent") "Un sous-titre"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-auteur').textContent") "Un auteur"))
    ;; The frame, as tall as two lines, with the plain capital; the true letter in the text.
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-lettrine').dataset.xviiiForme") "A"))
    (should (string-search "data:image/svg" (imprimeur-skin-xviii-test-style browser ".xviii-lettrine" "maskImage" "::after")))
    (should (equal (imprimeur-skin-xviii-test-style browser ".xviii-lettrine" "content" "::before") "\"A\" / \"\""))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-lettrine-texte').textContent") "À "))
    (should (eq (imprimeur-test-cdp-eval browser "(() => {
  const box = document.querySelector('.xviii-lettrine').getBoundingClientRect();
  const line = parseFloat(getComputedStyle(document.querySelector('.xviii-lettrine').parentElement).lineHeight);
  return box.height > line && box.height < 2 * line && box.width === box.height;
})()")
                t))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xviii-lettrine').length") 2))
    ;; It copies whole, without soft hyphens, and is found.
    (should (string-prefix-p "À la première" (plist-get (imprimeur-test-cdp-copy browser "p:has(> .xviii-lettrine)") :text)))
    (imprimeur-test-cdp-eval browser "getSelection().removeAllRanges()")
    (should (eq (imprimeur-test-cdp-eval browser "window.find('À la première')") t))
    ;; The imprint is drawn, and the year stays the document's.
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-date').textContent") "1759"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-date').dataset.xviiiImprint") "M. DCC. LIX."))
    ;; Chapters by the sheet; the stop is out of what a minitoc reads.
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('h1').textContent") "Première"))
    (should (equal (imprimeur-skin-xviii-test-style browser ".xviii-point" "content" "::after") "\".\""))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-xviii-sets-a-french-org-document ()
  (imprimeur-skin-xviii-test-french "doc.org" imprimeur-skin-xviii-test-org))

(ert-deftest imprimeur-skin-xviii-sets-a-french-markdown-document ()
  (imprimeur-skin-xviii-test-french "doc.md" imprimeur-skin-xviii-test-gfm))

(ert-deftest imprimeur-skin-xviii-paints-the-title-and-lettrine-in-red ()
  (pcase-dolist (`(,appearance . ,colour) imprimeur-skin-xviii-test-vermilion)
    (ert-info ((symbol-name appearance))
      (let ((imprimeur-appearance appearance))
        (imprimeur-skin-xviii-test-with (_buffer browser "doc.org" imprimeur-skin-xviii-test-org)
          (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
          (imprimeur-test-wait-for
           (lambda () (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.appearance")
                             (symbol-name appearance))))
          (should (equal (imprimeur-skin-xviii-test-style browser "#imprimeur-title" "color") colour))
          (should (equal (imprimeur-skin-xviii-test-style browser ".xviii-lettrine" "color") colour)))))))

(defun imprimeur-skin-xviii-test-opening (paragraph)
  "Return what the filter opens PARAGRAPH with, in a French chapter on a real page.
A list: the shape raised, the letter kept, and the first word's rest, or nil."
  (imprimeur-skin-xviii-test-with (_buffer browser "doc.md" (format "---\ntitle: Essai\nlang: fr\n---\n\n# Un\n\n%s\n" paragraph))
    (imprimeur-test-cdp-wait browser "document.querySelector('h1') !== null")
    (let ((opening (imprimeur-test-cdp-eval browser "(() => {
  const frame = document.querySelector('.xviii-lettrine');
  if (!frame) return null;
  return [frame.dataset.xviiiForme, document.querySelector('.xviii-lettrine-texte').textContent,
          document.querySelector('.xviii-premier-mot')?.textContent ?? ''];
})()")))
      (and opening (append opening nil)))))

(ert-deftest imprimeur-skin-xviii-opens-what-it-may-with-a-lettrine ()
  (pcase-dolist (`(,paragraph . ,expected)
                 '(("Il y avait." "I" "I" "l")
                   ("À la ligne." "A" "À " "")
                   ("États du roi." "E" "É" "tats")
                   ("Œuvres." "Œ" "Œ" "uvres.")
                   ("*Italique* suit." "I" "I" "")
                   ("« Non », dit-il." . nil)
                   ("`code` suit." . nil)
                   ("minuscule suit." . nil)
                   ("> Cité." . nil)
                   ("- Un point." . nil)))
    (ert-info (paragraph)
      (should (equal (imprimeur-skin-xviii-test-opening paragraph) expected)))))

(ert-deftest imprimeur-skin-xviii-keeps-a-decomposed-letter-whole ()
  ;; Org's reader leaves a decomposed capital as the document wrote it.
  (imprimeur-skin-xviii-test-with
      (_buffer browser "doc.org" "#+TITLE: Essai\n#+LANGUAGE: fr\n\n* Un\n\nE\u0301tats du roi.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-lettrine').dataset.xviiiForme") "E"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-lettrine-texte').textContent") "E\u0301"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-premier-mot').textContent") "tats"))))

(ert-deftest imprimeur-skin-xviii-opens-a-plain-note-with-a-lettrine ()
  (imprimeur-skin-xviii-test-with (_buffer browser "doc.md" "# Titre\n\nÀ la ligne.\n\nPuis.\n\n## Sec\n\nLa suite.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-title').textContent") "Titre"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xviii-lettrine').length") 1))
    (should (eq (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-titre') === null") t))))

(ert-deftest imprimeur-skin-xviii-sets-an-imprint-from-a-year-only ()
  (pcase-dolist (`(,date . ,imprint)
                 '(("1759" . "M. DCC. LIX.") ("1800" . "M. DCCC.") ("1805" . "M. DCCC. V.") ("1000" . "M.")
                   ("1899" . "M. DCCC. XCIX.") ("1900" . nil) ("999" . nil) ("12 mai 1759" . nil)))
    (ert-info (date)
      (imprimeur-skin-xviii-test-with (_buffer browser "doc.md" (format "---\ntitle: Essai\ndate: %s\n---\n\nUn mot.\n" date))
        (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-date') !== null")
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-date').textContent") date))
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xviii-date').dataset.xviiiImprint ?? null")
                       imprint))))))

(ert-deftest imprimeur-skin-xviii-stops-a-heading-unless-it-ends-in-a-sign ()
  (imprimeur-skin-xviii-test-with
      (_buffer browser "doc.md" "---\ntitle: Essai\nlang: fr\n---\n\n# Un mot\n\n## Une fin\n\n### Plus bas\n\n# Déjà ?\n\n## Oh…\n\n# Et æ\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('h1') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('h1, h2, h3')].map((h) => h.querySelector('.xviii-point') !== null)")
                   [t t nil nil nil t]))))

(ert-deftest imprimeur-skin-xviii-frames-a-lone-picture-and-numbers-it-with-a-language ()
  (pcase-dolist (`(,language . ,label)
                 '(("fr" . "\"PL. \" counter(xviii-planche, upper-roman) \".\\2002\"") (nil . "none")))
    (ert-info ((or language "none"))
      (imprimeur-skin-xviii-test-with
          (_buffer browser "doc.md" (format "---\ntitle: Essai\n%s---\n\nUn mot.\n\n![](pic.png)\n"
                                            (if language (format "lang: %s\n" language) "")))
        (imprimeur-test-cdp-wait browser "document.querySelector('img.xviii-seule') !== null")
        (should (string-search "double" (imprimeur-skin-xviii-test-style browser "img.xviii-seule" "borderTopStyle")))
        (let ((said (imprimeur-skin-xviii-test-style browser "p:has(> img.xviii-seule)" "content" "::after")))
          (if language (should (string-search "PL." said)) (should (equal said label))))))))

(ert-deftest imprimeur-skin-xviii-rags-a-language-with-no-patterns ()
  (pcase-dolist (`(,language . ,align) '(("fr" . "justify") ("en" . "justify") ("de" . "start")))
    (ert-info (language)
      (imprimeur-skin-xviii-test-with
          (_buffer browser "doc.md" (format "---\ntitle: Essai\nlang: %s\n---\n\nEin Wort.\n\nEin anderes.\n" language))
        (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
        (should (equal (imprimeur-skin-xviii-test-style browser "main > :last-child p, main > p:last-child" "textAlign") align))))))

(ert-deftest imprimeur-skin-xviii-changes-the-face-by-its-option ()
  (imprimeur-skin-xviii-test-with (buffer browser "doc.org" imprimeur-skin-xviii-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
    (should-not (imprimeur-skin-xviii-test-attributes browser))
    (should (string-prefix-p "Baskervville" (imprimeur-skin-xviii-test-style browser "#imprimeur-main" "fontFamily")))
    (imprimeur-skin-xviii-test-choose buffer browser "face" "junicode")
    (should (string-prefix-p "\"XVIII Junicode\"" (imprimeur-skin-xviii-test-style browser "#imprimeur-main" "fontFamily")))
    (imprimeur-skin-xviii-test-choose buffer browser "face" "baskervville")
    (should-not (imprimeur-skin-xviii-test-attributes browser))))

(ert-deftest imprimeur-skin-xviii-long-s-changes-only-junicode ()
  (imprimeur-skin-xviii-test-with (buffer browser "doc.org" imprimeur-skin-xviii-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
    (let ((features (lambda () (imprimeur-skin-xviii-test-style browser "#imprimeur-main" "fontFeatureSettings"))))
      (should (equal (funcall features) "normal"))
      ;; Under Baskervville, nothing but the attribute.
      (imprimeur-skin-xviii-test-choose buffer browser "long-s" "on")
      (should (equal (funcall features) "normal"))
      (should (string-prefix-p "Baskervville" (imprimeur-skin-xviii-test-style browser "#imprimeur-main" "fontFamily")))
      ;; Under Junicode, its long s by ss08 beside its flagged 1.
      (imprimeur-skin-xviii-test-choose buffer browser "face" "junicode")
      (should (equal (funcall features) "\"ss08\", \"ss09\""))
      (imprimeur-skin-xviii-test-choose buffer browser "long-s" "off")
      (should (equal (funcall features) "\"ss09\""))
      (imprimeur-skin-xviii-test-choose buffer browser "face" "baskervville")
      (should-not (imprimeur-skin-xviii-test-attributes browser)))))

(ert-deftest imprimeur-skin-xviii-changes-the-bands-by-their-option ()
  (imprimeur-skin-xviii-test-with (buffer browser "doc.org" imprimeur-skin-xviii-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
    (let* ((band (lambda () (imprimeur-skin-xviii-test-style browser "#imprimeur-title" "maskImage" "::before")))
           (seen (list (funcall band))))
      (dolist (value '("rinceau" "entrelacs" "perles" "filet"))
        (ert-info (value)
          (imprimeur-skin-xviii-test-choose buffer browser "bands" value)
          (should (string-search "data:image/svg" (funcall band)))
          (should-not (member (funcall band) seen))
          (push (funcall band) seen)))
      (imprimeur-skin-xviii-test-choose buffer browser "bands" "fleurons")
      (should (equal (funcall band) (car (last seen))))
      (should-not (imprimeur-skin-xviii-test-attributes browser)))))

(ert-deftest imprimeur-skin-xviii-takes-no-option-from-a-document ()
  (imprimeur-skin-xviii-test-with
      (_buffer browser "doc.md"
               (concat "---\ntitle: Essai\nlang: fr\nface: junicode\nbands: filet\nlong-s: on\n"
                       "data-xviii-face: junicode\nimprimeur-option-face: junicode\n---\n\n"
                       "# Un\n\nUn mot.\n\n<div data-xviii-bands=\"filet\">Rien.</div>\n"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
    (should-not (imprimeur-skin-xviii-test-attributes browser))
    (should (string-prefix-p "Baskervville" (imprimeur-skin-xviii-test-style browser "#imprimeur-main" "fontFamily")))))

(ert-deftest imprimeur-skin-xviii-sets-its-examples ()
  (pcase-dolist (`(,file ,lettrines ,plates)
                 '(("candide.org" 10 2) ("johnson.md" 2 1)))
    (ert-info (file)
      (let ((text (with-temp-buffer
                    (insert-file-contents (expand-file-name file (expand-file-name "examples/xviii" repo-test-root)))
                    (buffer-string))))
        (imprimeur-skin-xviii-test-with (_buffer browser file text)
          (imprimeur-test-cdp-wait browser "document.querySelector('.xviii-lettrine') !== null")
          (should (>= (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xviii-lettrine').length") lettrines))
          (should (>= (imprimeur-test-cdp-eval browser "document.querySelectorAll('figure').length") plates))
          (should (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-main').textContent.includes('\u00AD')"))
          (should (= (imprimeur-test-cdp-eval browser "document.documentElement.scrollWidth")
                     (imprimeur-test-cdp-eval browser "document.documentElement.clientWidth"))))))))

(ert-deftest imprimeur-skin-xviii-is-chosen-by-the-configuration-of-its-readme ()
  (let* ((readme (with-temp-buffer
                   (insert-file-contents (expand-file-name "imprimeur-skin-xviii/README.md" repo-test-root))
                   (buffer-string)))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'xviii\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-xviii-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-xviii)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"xviii\" (imprimeur-skin-get \"xviii\") (imprimeur-skin-configured \"xviii\" (imprimeur-skin-get \"xviii\")) nil))"))))
    (should (equal (car result) 0))
    ;; Every option at its default, so the root stays bare.
    (should (string-suffix-p "xviii[]" (cdr result)))))

(ert-deftest imprimeur-skin-xviii-filter-stays-within-the-limit-of-complexity ()
  (let ((luacheck (imprimeur-test-require "luacheck")))
    (should (equal (call-process luacheck nil nil nil "--no-config" "--no-color"
                                 "--max-cyclomatic-complexity" "10" "--globals" "pandoc" "--"
                                 (expand-file-name "imprimeur-skin-xviii/assets/filter.lua" repo-test-root))
                   0))))

;;; imprimeur-skin-xviii-test.el ends here
