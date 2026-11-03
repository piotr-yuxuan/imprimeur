;;; imprimeur-skin-xvii-test.el --- Tests of the skin XVII  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 022:
;;
;; "IM Fell English by default, with long s, historical ligatures and manchettes each a
;; switch and all on, red titles, woodcut bands, three-line block initials": the manifest's
;; defaults and choices, by hand from docs/work/planned/skin-defaults.md and the workbench's
;; params.json.
;;
;; Acceptance 2: with XVII chosen, on real pandoc, an Org and a gfm French document show the
;; band, the red title, the initial, long s and a manchette; each option changes what it
;; says, alone.  Acceptance 3: copying and search give the document's text: round s, no soft
;; hyphen, the heading's own case.  Acceptance 5: the filter is within 10, by luacheck.
;; Acceptance 6: no example's page holds Project Gutenberg's licence paragraph.
;;
;; What the filter does, by the trial's reports: a manchette beside a call, none from a
;; heading, a table, a figure or a verse; an initial on the first paragraph of a chapter,
;; never after a sign, showing the capital without its diacritics while the document's
;; letters stay in the line; a round s before a hyphen; a year before 1900 as an imprint,
;; the document's date staying in the text; names joined.  "No soft hyphen may spoil a long
;; s": none after an s, between c and t, or between f and f, i or l.
;;
;; The tests register XVII in a registry of their own, as the other tests see Minitel alone.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-cdp)
(require 'imprimeur)

(defconst imprimeur-skin-xvii-test-file
  (expand-file-name "imprimeur-skin-xvii/imprimeur-skin-xvii.el" repo-test-root)
  "The skin's main file.")

(defconst imprimeur-skin-xvii-test-vermilion '((light . "rgb(163, 42, 31)") (dark . "rgb(224, 122, 85)"))
  "The red of the title, on paper and in candlelight.")

(defconst imprimeur-skin-xvii-test-org
  (concat "#+TITLE: Discours de la méthode\n#+SUBTITLE: Un sous-titre\n#+AUTHOR: René Descartes\n"
          "#+INSTITUTE: À Leyde\n#+DATE: 1637\n#+LANGUAGE: fr\n\n"
          "* Première partie\n\nÀ la première ligne, « bien » dit-il[fn:1]; la typographie de celles-ci suit, "
          "et la considération des distinctions aussi.\n\nUn second alinéa.\n\n"
          "* Seconde partie\n\nQuand la queue descend.\n\n[fn:1] Une manchette distinctive.\n")
  "A French document in Org, with chapters, a note and an initial on an accented capital.")

(defconst imprimeur-skin-xvii-test-gfm
  (concat "---\ntitle: Discours de la méthode\nsubtitle: Un sous-titre\nauthor: René Descartes\n"
          "institute: À Leyde\ndate: 1637\nlang: fr\n---\n\n"
          "# Première partie\n\nÀ la première ligne, « bien » dit-il[^1]; la typographie de celles-ci suit, "
          "et la considération des distinctions aussi.\n\nUn second alinéa.\n\n"
          "# Seconde partie\n\nQuand la queue descend.\n\n[^1]: Une manchette distinctive.\n")
  "The same document in GitHub Markdown.")

(defmacro imprimeur-skin-xvii-test-with (spec &rest body)
  "Run BODY with XVII as the skin of a scratch document open in a browser.
SPEC is (BUFFER BROWSER FILE TEXT): BUFFER visits FILE, holding TEXT, in
the selected Emacs window, in `imprimeur-mode'; BROWSER shows its page."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,browser ,file ,text) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
              (imprimeur-skin 'xvii)
              (imprimeur-skin-options nil)
              (imprimeur-reader-alist (cons '("\\.md\\'" . "gfm+sourcepos") imprimeur-reader-alist))
              (imprimeur-browser-program imprimeur-test-fake-browser)
              (root (repo-test-git-tree (list (cons ,file ,text))))
              (,buffer (find-file-noselect (expand-file-name ,file root))))
         (load imprimeur-skin-xvii-test-file nil t)
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

(defun imprimeur-skin-xvii-test-style (browser selector property &optional pseudo)
  "Return the computed PROPERTY of SELECTOR's PSEUDO in BROWSER's page."
  (imprimeur-test-cdp-eval
   browser (format "getComputedStyle(document.querySelector(%S), %s)[%S]"
                   selector (if pseudo (format "%S" pseudo) "null") property)))

(defun imprimeur-skin-xvii-test-text (browser selector)
  "Return the text of what SELECTOR finds in BROWSER's page, without its soft hyphens."
  (string-replace "\u00AD" "" (imprimeur-test-cdp-eval browser (format "document.querySelector(%S).textContent" selector))))

(defun imprimeur-skin-xvii-test-selected (browser selector)
  "Return what a selection of what SELECTOR finds in BROWSER's page reads."
  (imprimeur-test-cdp-eval
   browser (format "(() => { getSelection().selectAllChildren(document.querySelector(%S)); return getSelection().toString(); })()"
                   selector)))

(defun imprimeur-skin-xvii-test-attributes (browser)
  "Return the names of the data-xvii attributes on the root of BROWSER's page."
  (append (imprimeur-test-cdp-eval
           browser "[...document.documentElement.attributes].map((a) => a.name).filter((n) => n.startsWith('data-xvii'))")
          nil))

(defun imprimeur-skin-xvii-test-choose (buffer browser id value)
  "Give the option ID of BUFFER's skin VALUE, and wait for BROWSER's page to read it."
  (with-current-buffer buffer (imprimeur-set-skin-option id value))
  (imprimeur-test-cdp-wait
   browser (format "document.documentElement.getAttribute('data-xvii-%s') === %s"
                   id (if (equal value (plist-get (cdr (assq (intern id) (plist-get (imprimeur-skin-get "xvii") :options)))
                                                  :default))
                          "null"
                        (format "%S" value)))))

(defun imprimeur-skin-xvii-test-said (browser)
  "Return what each option decides of BROWSER's page, as an alist from the option.
The face, the long s and ligatures by the features of the text, and whether a
manchette or the note at the end of the section shows."
  (list (cons 'family (car (split-string (imprimeur-skin-xvii-test-style browser "#imprimeur-main" "fontFamily") ",")))
        (cons 'features (imprimeur-skin-xvii-test-style browser "#imprimeur-main" "fontFeatureSettings"))
        (cons 'manchette (imprimeur-skin-xvii-test-style browser ".xvii-manchette" "display"))
        (cons 'note (imprimeur-skin-xvii-test-style browser ".footnotes li" "visibility"))))

(ert-deftest imprimeur-skin-xvii-registers-from-its-autoloads-alone ()
  (let* ((directory (make-temp-file "autoloads" t))
         (autoloads (expand-file-name "loaddefs.el" directory))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-xvii-test-file)
                        "--eval" (format "(loaddefs-generate %S %S)"
                                         (file-name-directory imprimeur-skin-xvii-test-file) autoloads)
                        "--eval" "(message \"MARK\")"
                        "-l" autoloads
                        "--eval" "(princ (format \"before=%S \" (featurep 'imprimeur-skin-xvii)))"
                        "--eval" "(require 'imprimeur-skin)"
                        "--eval" "(princ (format \"after=%S \" (and (imprimeur-skin-get \"xvii\") t)))"))))
    (should (equal (car result) 0))
    (let ((printed (substring (cdr result) (+ (string-search "MARK" (cdr result)) 5))))
      (should (equal printed "before=nil after=t ")))))

(ert-deftest imprimeur-skin-xvii-keeps-the-owner-s-defaults-and-choices ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry)))
    (load imprimeur-skin-xvii-test-file nil t)
    (let* ((manifest (imprimeur-skin-get "xvii"))
           (options (plist-get manifest :options)))
      (should (equal (plist-get manifest :title) "XVII"))
      (should (plist-get manifest :smart))
      (should (eq (plist-get manifest :notes) 'section))
      (pcase-dolist (`(,id ,default . ,choices)
                     '((face "im-fell" "im-fell" "eb-garamond" "garamond-libre")
                       (long-s "on" "on" "off")
                       (ligatures "on" "on" "off")
                       (manchettes "on" "on" "off")))
        (ert-info ((symbol-name id))
          (should (equal (plist-get (alist-get id options) :default) default))
          (should (equal (mapcar #'car (plist-get (alist-get id options) :choices)) choices))))
      (should (equal (mapcar #'car options) '(face long-s ligatures manchettes))))))

(defun imprimeur-skin-xvii-test-french (file text)
  "Check the French page of FILE, holding TEXT, on paper."
  (imprimeur-skin-xvii-test-with (_buffer browser file text)
    (should (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.skin") "xvii"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    ;; The band over a chapter.
    (should (string-search "data:image/svg" (imprimeur-skin-xvii-test-style browser "h1" "maskImage" "::before")))
    ;; The title page, in its two sizes, and what the page does not hear of after the title.
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-titre-tete") "Discours"))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-titre-suite") "de la méthode"))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-sous-titre") "Un sous-titre"))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-auteur") "René Descartes"))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-adresse") "À Leyde"))
    (should (equal (imprimeur-skin-xvii-test-style browser "#imprimeur-title" "display") "none"))
    ;; The initial, three lines tall, with the plain capital; the true letter in the text.
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xvii-initiale').dataset.xviiForme") "A"))
    (should (equal (imprimeur-skin-xvii-test-style browser ".xvii-initiale" "content" "::before") "\"A\" / \"\""))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-lettre") "À"))
    (should (eq (imprimeur-test-cdp-eval browser "(() => {
  const box = document.querySelector('.xvii-initiale').getBoundingClientRect();
  const line = parseFloat(getComputedStyle(document.querySelector('.xvii-initiale').parentElement).lineHeight);
  return box.height > 2 * line && box.height < 3 * line && box.width === box.height;
})()")
                t))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xvii-initiale').length") 2))
    ;; Long s and the ligatures, by the features of the text.
    (should (equal (imprimeur-skin-xvii-test-style browser "#imprimeur-main" "fontFeatureSettings") "\"dlig\", \"hist\""))
    ;; The manchette beside its call, with the note out of the way, and a letter for its call.
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-manchette") "Une manchette distinctive."))
    (should (equal (imprimeur-skin-xvii-test-style browser ".xvii-manchette" "display") "block"))
    (should (equal (imprimeur-skin-xvii-test-style browser ".footnotes li" "visibility") "hidden"))
    (should-not (imprimeur-test-cdp-errors browser))))

(ert-deftest imprimeur-skin-xvii-sets-a-french-org-document ()
  (imprimeur-skin-xvii-test-french "doc.org" imprimeur-skin-xvii-test-org))

(ert-deftest imprimeur-skin-xvii-sets-a-french-markdown-document ()
  (imprimeur-skin-xvii-test-french "doc.md" imprimeur-skin-xvii-test-gfm))

(ert-deftest imprimeur-skin-xvii-paints-the-title-in-red ()
  (pcase-dolist (`(,appearance . ,colour) imprimeur-skin-xvii-test-vermilion)
    (ert-info ((symbol-name appearance))
      (let ((imprimeur-appearance appearance))
        (imprimeur-skin-xvii-test-with (_buffer browser "doc.org" imprimeur-skin-xvii-test-org)
          (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-titre-tete') !== null")
          (imprimeur-test-wait-for
           (lambda () (equal (imprimeur-test-cdp-eval browser "document.documentElement.dataset.appearance")
                             (symbol-name appearance))))
          (should (equal (imprimeur-skin-xvii-test-style browser ".xvii-titre-tete" "color") colour)))))))

(ert-deftest imprimeur-skin-xvii-copies-and-finds-the-document-s-text ()
  (imprimeur-skin-xvii-test-with (_buffer browser "doc.org" imprimeur-skin-xvii-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    ;; The filter wrote soft hyphens, and the s before a hyphen is apart.
    (should (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-main').textContent.includes('­')"))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-s-rond") "s"))
    (let ((paragraph (plist-get (imprimeur-test-cdp-copy browser "main p:has(> .xvii-initiale)") :text)))
      (should (string-prefix-p "À la première ligne" paragraph))
      (should (string-search "celles-ci" paragraph))
      (should-not (string-search "­" paragraph))
      (should-not (string-search "ſ" paragraph))
      ;; Neither the manchette nor the call belongs to the sentence.
      (should-not (string-search "manchette" paragraph)))
    (let ((title (imprimeur-skin-xvii-test-selected browser ".xvii-titre")))
      (should (string-search "de la méthode" title))
      (should (string-search "René Descartes" title))
      (should (string-search "1637" title)))
    ;; A heading copies in its own case, without its label or stop.
    (should (equal (imprimeur-skin-xvii-test-selected browser "h1") "Première partie"))
    (imprimeur-test-cdp-eval browser "getSelection().removeAllRanges()")
    (dolist (words '("À la première" "Première partie" "typographie" "distinctions" "celles-ci"
                     "Une manchette distinctive" "1637"))
      (ert-info (words)
        (should (eq (imprimeur-test-cdp-eval
                     browser (format "(() => { getSelection().removeAllRanges(); return window.find(%S); })()" words))
                    t))))))

(ert-deftest imprimeur-skin-xvii-spoils-no-long-s-with-a-soft-hyphen ()
  (imprimeur-skin-xvii-test-with (_buffer browser "doc.md"
                                          (concat "---\ntitle: Essai\nlang: fr\n---\n\n"
                                                  "# Un\n\nLes considérations distinctes, la philosophie de "
                                                  "la satisfaction, les affirmations officielles et "
                                                  "l'instruction des obstacles.\n"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    (let ((text (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-main').textContent")))
      (should (string-search "­" text))
      (let ((case-fold-search nil))
        (should-not (string-match-p "s­\\|c­t\\|f­[fil]" text))))))

(defun imprimeur-skin-xvii-test-opening (paragraph)
  "Return what the filter opens PARAGRAPH with, in a French chapter on a real page.
A list: the shape shown, the class of its block, the letter kept, the first
word's rest, and the capitals drawn for it; or nil."
  (imprimeur-skin-xvii-test-with (_buffer browser "doc.md" (format "---\ntitle: Essai\nlang: fr\n---\n\n# Un\n\n%s\n" paragraph))
    (imprimeur-test-cdp-wait browser "document.querySelector('h1') !== null")
    (let ((opening (imprimeur-test-cdp-eval browser "(() => {
  const block = document.querySelector('.xvii-initiale');
  if (!block) return null;
  const rest = document.querySelector('.xvii-premier-mot');
  return [block.dataset.xviiForme, block.classList.contains('xvii-suppleante') ? 'stand-in' : 'engraved',
          document.querySelector('.xvii-lettre').textContent,
          rest?.textContent ?? '', rest?.dataset.xviiCapitales ?? ''];
})()")))
      (and opening (append opening nil)))))

(ert-deftest imprimeur-skin-xvii-opens-what-it-may-with-an-initial ()
  (pcase-dolist (`(,paragraph . ,expected)
                 '(("Il y avait." "I" "stand-in" "I" "l" "L")
                   ("À la ligne." "A" "engraved" "À" "" "")
                   ("États du royaume." "E" "stand-in" "É" "tats" "TATS")
                   ("Quand même." "Q" "engraved" "Q" "uand" "UAND")
                   ("Considération suit." "C" "stand-in" "C" "onsidération" "ONSIDÉRATION")
                   ("*Parmi* les." "P" "stand-in" "P" "armi" "ARMI")
                   ("Pense-t-on." "P" "stand-in" "P" "ense-t-on" "ENSE-T-ON")
                   ("« Non », dit-il." . nil)
                   ("`code` suit." . nil)
                   ("minuscule suit." . nil)
                   ("> Cité." . nil)
                   ("- Un point." . nil)))
    (ert-info (paragraph)
      (should (equal (imprimeur-skin-xvii-test-opening paragraph) expected)))))

(ert-deftest imprimeur-skin-xvii-breaks-no-word-in-an-initial ()
  ;; English lets a long capitalised word break, and a first word at no size has no line to end.
  (imprimeur-skin-xvii-test-with
      (_buffer browser "doc.md" "---\ntitle: Essai\nlang: en\n---\n\n# One\n\nConsiderations upon the Commonwealth.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    (should (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-main').textContent.includes('­')"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xvii-premier-mot').textContent") "onsiderations"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xvii-premier-mot').dataset.xviiCapitales") "ONSIDERATIONS"))))

(ert-deftest imprimeur-skin-xvii-keeps-a-century-true-under-its-small-capitals ()
  (imprimeur-skin-xvii-test-with
      (_buffer browser "doc.md" "---\ntitle: Essai\nlang: fr\n---\n\nUn livre du XVIIe siècle.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.imprimeur-siecle') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.imprimeur-siecle').dataset.xviiBasses") "xvii"))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-siecle-lettres") "XVII"))
    (should (equal (imprimeur-skin-xvii-test-style browser ".xvii-siecle-lettres" "fontSize") "0px"))
    (should (string-search "XVIIe" (imprimeur-skin-xvii-test-selected browser "main p:has(.imprimeur-siecle)")))))

(ert-deftest imprimeur-skin-xvii-keeps-a-decomposed-letter-whole ()
  ;; Org's reader leaves a decomposed capital as the document wrote it.
  (imprimeur-skin-xvii-test-with
      (_buffer browser "doc.org" "#+TITLE: Essai\n#+LANGUAGE: fr\n\n* Un\n\nÉtats du roi.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xvii-initiale').dataset.xviiForme") "E"))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-lettre") "É"))
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-premier-mot") "tats"))))

(ert-deftest imprimeur-skin-xvii-opens-a-plain-note-with-an-initial ()
  (imprimeur-skin-xvii-test-with (_buffer browser "doc.md" "# Titre\n\nÀ la ligne.\n\nPuis.\n\n## Sec\n\nLa suite.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-titre-tete") "Titre"))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xvii-initiale').length") 1))
    (should (eq (imprimeur-test-cdp-eval browser "document.querySelector('.xvii-cul-de-lampe') === null") t))))

(ert-deftest imprimeur-skin-xvii-sets-the-imprint-from-a-year-only ()
  (pcase-dolist (`(,date . ,imprint)
                 '(("1637" . "M. DC. XXXVII.") ("1800" . "M. DCCC.") ("1644" . "M. DC. XLIV.") ("1000" . "M.")
                   ("1900" . nil) ("999" . nil) ("12 mai 1637" . nil)))
    (ert-info (date)
      (imprimeur-skin-xvii-test-with (_buffer browser "doc.md" (format "---\ntitle: Essai\ndate: %s\n---\n\nUn mot.\n" date))
        (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-date') !== null")
        (should (equal (imprimeur-skin-xvii-test-text browser ".xvii-date") date))
        (should (equal (imprimeur-test-cdp-eval browser "document.querySelector('.xvii-date').dataset.xviiImprint ?? null")
                       imprint))))))

(ert-deftest imprimeur-skin-xvii-parts-a-title-and-joins-names ()
  (pcase-dolist (`(,meta ,head ,tail ,author)
                 '(("title: Discours de la méthode\nlang: fr\n" "Discours" "de la méthode" nil)
                   ("title: Traité complet\nlang: fr\n" "Traité complet" nil nil)
                   ("title: Essai d'une méthode\nlang: fr\n" "Essai" "d’une méthode" nil)
                   ("title: Areopagitica\nlang: en\n" "Areopagitica" nil nil)
                   ("title: Essai\nlang: fr\nauthor: [Un, Deux, Trois]\n" "Essai" nil "Un, Deux et Trois")
                   ("title: Essai\nlang: en\nauthor: [{name: Un}, {name: Deux}]\n" "Essai" nil "Un and Deux")
                   ("title: Essai\nauthor: [Un, Deux]\n" "Essai" nil "Un, Deux")))
    (ert-info (meta)
      (imprimeur-skin-xvii-test-with (_buffer browser "doc.md" (format "---\n%s---\n\nUn mot.\n" meta))
        (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-titre-tete') !== null")
        (let ((said (lambda (class)
                      (imprimeur-test-cdp-eval browser (format "document.querySelector('.%s')?.textContent ?? null" class)))))
          (should (equal (funcall said "xvii-titre-tete") head))
          (should (equal (funcall said "xvii-titre-suite") tail))
          (should (equal (funcall said "xvii-auteur") author)))))))

(ert-deftest imprimeur-skin-xvii-closes-chapters-and-stops-what-has-no-sign ()
  (imprimeur-skin-xvii-test-with
      (_buffer browser "doc.md"
               "---\ntitle: Essai\nlang: fr\n---\n\n# Un mot\n\nTexte.\n\n## Une fin\n\n# Déjà ?\n\nTexte.\n\n## Oh…\n\n# Et æ\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('h1') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('h1, h2')].map((h) => getComputedStyle(h, '::after').content !== 'none')")
                   [t t nil nil t]))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('h1 .xvii-chapitre').length") 3))
    (should (equal (imprimeur-test-cdp-eval browser "document.querySelectorAll('main > .xvii-cul-de-lampe').length") 3))
    (should (equal (imprimeur-skin-xvii-test-style browser "h1 .xvii-chapitre" "content" "::before")
                   "\"CHAPITRE \" counter(xvii-chapitre, xvii-chapitre) \".\""))))

(ert-deftest imprimeur-skin-xvii-gives-a-manchette-only-where-one-can-stand ()
  (imprimeur-skin-xvii-test-with
      (_buffer browser "doc.md"
               (concat "---\ntitle: Essai\nlang: fr\n---\n\n"
                       "# Un[^titre]\n\nDans le *texte[^texte]* et.\n\n> Cité[^cite].\n\n"
                       "| A |\n|---|\n| B[^table] |\n\n"
                       "[^titre]: Du titre.\n\n[^texte]: Du texte.\n\n[^cite]: De la citation.\n\n[^table]: Du tableau.\n"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.footnotes') !== null")
    (should (equal (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('.xvii-manchette')].map((m) => m.textContent)")
                   ["Du texte." "De la ci\u00ADta\u00ADtion."]))
    ;; A note stays at the end of its section only when no manchette can show it.
    (should (equal (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('.footnotes li')].map((li) => getComputedStyle(li).visibility)")
                   ["visible" "hidden" "hidden" "visible"]))
    ;; The call beside a manchette leads nowhere, and one without keeps its link.
    (should (equal (imprimeur-test-cdp-eval browser "[...document.querySelectorAll('a.footnote-ref')].map((a) => getComputedStyle(a).visibility)")
                   ["visible" "hidden" "hidden" "visible"]))))

(ert-deftest imprimeur-skin-xvii-centres-a-document-with-no-manchette ()
  (imprimeur-skin-xvii-test-with (_buffer browser "doc.md" "---\ntitle: Essai\nlang: fr\n---\n\n# Un\n\nUn mot.\n")
    (imprimeur-test-cdp-wait browser "document.querySelector('h1') !== null")
    (should (eq (imprimeur-test-cdp-eval browser "(() => {
  const box = document.getElementById('imprimeur-main').getBoundingClientRect();
  return Math.abs(box.left - (document.documentElement.clientWidth - box.right)) <= 1;
})()")
                t))))

(ert-deftest imprimeur-skin-xvii-frames-a-lone-picture-and-numbers-it-with-a-language ()
  (pcase-dolist (`(,language . ,label)
                 '(("fr" . "\"PL. \" counter(xvii-planche, upper-roman) \".\\2002\"") (nil . "none")))
    (ert-info ((or language "none"))
      (imprimeur-skin-xvii-test-with
          (_buffer browser "doc.md" (format "---\ntitle: Essai\n%s---\n\nUn mot.\n\n![](pic.png)\n"
                                            (if language (format "lang: %s\n" language) "")))
        (imprimeur-test-cdp-wait browser "document.querySelector('img.xvii-seule') !== null")
        (should (string-search "double" (imprimeur-skin-xvii-test-style browser "img.xvii-seule" "borderTopStyle")))
        (let ((said (imprimeur-skin-xvii-test-style browser "p:has(> img.xvii-seule)" "content" "::after")))
          (if language (should (string-search "PL." said)) (should (equal said label))))))))

(ert-deftest imprimeur-skin-xvii-rags-a-language-with-no-patterns ()
  (pcase-dolist (`(,language . ,align) '(("fr" . "justify") ("en" . "justify") ("de" . "start")))
    (ert-info (language)
      (imprimeur-skin-xvii-test-with
          (_buffer browser "doc.md" (format "---\ntitle: Essai\nlang: %s\n---\n\nEin Wort.\n\nEin anderes.\n" language))
        (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
        (should (equal (imprimeur-skin-xvii-test-style browser "main > :last-child p, main > p:last-child" "textAlign") align))))))

(ert-deftest imprimeur-skin-xvii-changes-what-each-option-says-alone ()
  (imprimeur-skin-xvii-test-with (buffer browser "doc.org" imprimeur-skin-xvii-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    (should-not (imprimeur-skin-xvii-test-attributes browser))
    (let ((defaults (imprimeur-skin-xvii-test-said browser)))
      (should (equal defaults '((family . "\"IM FELL English\"") (features . "\"dlig\", \"hist\"")
                                (manchette . "block") (note . "hidden"))))
      (pcase-dolist (`(,id ,value ,property ,said)
                     '(("long-s" "off" features "\"dlig\", \"hist\" 0")
                       ("ligatures" "off" features "\"dlig\" 0, \"hist\"")
                       ("manchettes" "off" manchette "none")))
        (ert-info ((format "%s %s" id value))
          (imprimeur-skin-xvii-test-choose buffer browser id value)
          (imprimeur-test-cdp-wait browser "true")
          (let ((now (imprimeur-skin-xvii-test-said browser)))
            (should (equal (alist-get property now) said))
            ;; Nothing else, but the note that a manchette gives way to.
            (should (equal (assq-delete-all 'note (assq-delete-all property (copy-alist now)))
                           (assq-delete-all 'note (assq-delete-all property (copy-alist defaults))))))
          (should (equal (imprimeur-skin-xvii-test-attributes browser) (list (format "data-xvii-%s" id))))
          (when (equal id "manchettes")
            (should (equal (alist-get 'note (imprimeur-skin-xvii-test-said browser)) "visible"))
            (should (equal (imprimeur-skin-xvii-test-style browser "a.footnote-ref" "visibility") "visible")))
          (imprimeur-skin-xvii-test-choose buffer browser id "on")
          (should (equal (imprimeur-skin-xvii-test-said browser) defaults))))
      (should-not (imprimeur-skin-xvii-test-attributes browser)))))

(ert-deftest imprimeur-skin-xvii-changes-the-face-by-its-option ()
  (imprimeur-skin-xvii-test-with (buffer browser "doc.org" imprimeur-skin-xvii-test-org)
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    (pcase-dolist (`(,value ,family ,on ,long-s-off ,ligatures-off)
                   '(("eb-garamond" "\"EB Garamond 12\"" "\"cv01\", \"dlig\", \"hlig\""
                      "\"cv01\" 0, \"dlig\", \"hlig\"" "\"cv01\", \"dlig\", \"hlig\" 0")
                     ("garamond-libre" "\"Garamond Libre\"" "\"dlig\" 0" "\"dlig\" 0" "\"dlig\" 0")))
      (ert-info (value)
        (imprimeur-skin-xvii-test-choose buffer browser "face" value)
        (should (equal (alist-get 'family (imprimeur-skin-xvii-test-said browser)) family))
        (should (equal (alist-get 'features (imprimeur-skin-xvii-test-said browser)) on))
        (imprimeur-skin-xvii-test-choose buffer browser "long-s" "off")
        (should (equal (alist-get 'features (imprimeur-skin-xvii-test-said browser)) long-s-off))
        (imprimeur-skin-xvii-test-choose buffer browser "long-s" "on")
        (imprimeur-skin-xvii-test-choose buffer browser "ligatures" "off")
        (should (equal (alist-get 'features (imprimeur-skin-xvii-test-said browser)) ligatures-off))
        (imprimeur-skin-xvii-test-choose buffer browser "ligatures" "on")
        ;; The s before a hyphen is round, and the other features stay.
        (should (string-search (if (equal value "eb-garamond") "\"cv01\" 0" "\"dlig\" 0")
                               (imprimeur-skin-xvii-test-style browser ".xvii-s-rond" "fontFeatureSettings")))))
    (imprimeur-skin-xvii-test-choose buffer browser "face" "im-fell")
    (should-not (imprimeur-skin-xvii-test-attributes browser))))

(ert-deftest imprimeur-skin-xvii-takes-no-option-from-a-document ()
  (imprimeur-skin-xvii-test-with
      (_buffer browser "doc.md"
               (concat "---\ntitle: Essai\nlang: fr\nface: garamond-libre\nmanchettes: off\nlong-s: off\n"
                       "data-xvii-face: garamond-libre\nimprimeur-option-face: garamond-libre\n---\n\n"
                       "# Un\n\nUn mot.\n\n<div data-xvii-manchettes=\"off\">Rien.</div>\n"))
    (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
    (should-not (imprimeur-skin-xvii-test-attributes browser))
    (should (string-prefix-p "\"IM FELL English\"" (imprimeur-skin-xvii-test-style browser "#imprimeur-main" "fontFamily")))))

(ert-deftest imprimeur-skin-xvii-sets-its-examples ()
  (pcase-dolist (`(,file ,initials ,manchettes ,plates)
                 '(("descartes.org" 8 5 3) ("milton.md" 1 3 2)))
    (ert-info (file)
      (let ((text (with-temp-buffer
                    (insert-file-contents (expand-file-name file (expand-file-name "examples/xvii" repo-test-root)))
                    (buffer-string))))
        (imprimeur-skin-xvii-test-with (_buffer browser file text)
          (imprimeur-test-cdp-wait browser "document.querySelector('.xvii-initiale') !== null")
          (should (>= (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xvii-initiale').length") initials))
          (should (>= (imprimeur-test-cdp-eval browser "document.querySelectorAll('.xvii-manchette').length") manchettes))
          (should (>= (imprimeur-test-cdp-eval browser "document.querySelectorAll('figure, .captioned-content').length") plates))
          (should (imprimeur-test-cdp-eval browser "document.getElementById('imprimeur-main').textContent.includes('­')"))
          (should (= (imprimeur-test-cdp-eval browser "document.documentElement.scrollWidth")
                     (imprimeur-test-cdp-eval browser "document.documentElement.clientWidth"))))))))

(ert-deftest imprimeur-skin-xvii-no-example-s-page-holds-the-licence-paragraph ()
  (let ((pages (seq-remove (lambda (file) (string-suffix-p "/SOURCES.md" file))
                           (directory-files-recursively (expand-file-name "examples" repo-test-root)
                                                        "\\.\\(?:org\\|md\\)\\'"))))
    (should (>= (length pages) 6))
    (dolist (page pages)
      (ert-info (page)
        (with-temp-buffer
          (insert-file-contents page)
          (should-not (string-search "eBook is for the use of anyone" (buffer-string))))))))

(ert-deftest imprimeur-skin-xvii-is-chosen-by-the-configuration-of-its-readme ()
  (let* ((readme (with-temp-buffer
                   (insert-file-contents (expand-file-name "imprimeur-skin-xvii/README.md" repo-test-root))
                   (buffer-string)))
         (block (progn
                  (string-match "```elisp\n\\(\\(?:[^`]\\|`[^`]\\)*?imprimeur-skin 'xvii\\(?:[^`]\\|`[^`]\\)*?\\)```" readme)
                  (match-string 1 readme)))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "imprimeur" repo-test-root)
                        "-L" (file-name-directory imprimeur-skin-xvii-test-file)
                        "--eval" (concat "(progn " block ")")
                        "--eval" "(require 'imprimeur-skin-xvii)"
                        "--eval" "(princ (imprimeur-skin-initial-name))"
                        "--eval" "(princ (imprimeur-skin-attributes \"xvii\" (imprimeur-skin-get \"xvii\") (imprimeur-skin-configured \"xvii\" (imprimeur-skin-get \"xvii\")) nil))"))))
    (should (equal (car result) 0))
    ;; Every option at its default, so the root stays bare.
    (should (string-suffix-p "xvii[]" (cdr result)))))

(ert-deftest imprimeur-skin-xvii-filter-stays-within-the-limit-of-complexity ()
  (let ((luacheck (imprimeur-test-require "luacheck")))
    (should (equal (call-process luacheck nil nil nil "--no-config" "--no-color"
                                 "--max-cyclomatic-complexity" "10" "--globals" "pandoc" "--"
                                 (expand-file-name "imprimeur-skin-xvii/assets/filter.lua" repo-test-root))
                   0))))

;;; imprimeur-skin-xvii-test.el ends here
