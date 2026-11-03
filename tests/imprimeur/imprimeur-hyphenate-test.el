;;; imprimeur-hyphenate-test.el --- Tests of the shared filter hyphenate  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements of plan 021, acceptance 2 and 6, and of plan 010's "Soft hyphens":
;;
;; Known French and English words break where a dictionary breaks them, by hand below.
;; A word of at least 6 letters may break, with 2 before and 3 after; never after s,
;; between c and t, or between f and f, i or l.  A capitalised word stays whole in
;; French, and in English until 8 letters; a word with any later capital stays whole.
;; No break in code, maths, a raw block, an address, a heading, a table or a caption, and
;; breaks in notes.  fr and en take patterns, en British, no language counts as English,
;; and any other language gets none.  The filter's strings are the vendored files.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)

(defconst imprimeur-hyphenate-test-filters
  (expand-file-name "imprimeur/assets/pandoc/filters" repo-test-root)
  "The directory of the shared filters.")

(defconst imprimeur-hyphenate-test-vendored
  (expand-file-name "imprimeur/assets/vendor/hyph-utf8" repo-test-root)
  "The directory of the vendored patterns.")

(defun imprimeur-hyphenate-test-run (language text format)
  "Return TEXT in FORMAT, in LANGUAGE or none, after the filters of a skin, on real pandoc.
Each soft hyphen shows as a vertical bar."
  (let ((pandoc (imprimeur-test-require "pandoc")))
    (with-temp-buffer
      (insert text)
      (let ((status (apply #'call-process-region
                           (point-min) (point-max) pandoc t t nil
                           "--sandbox" "--from" "gfm" "--to" format "--wrap=none"
                           (append (and language (list "--metadata" (concat "lang=" language)))
                                   (mapcan (lambda (filter)
                                             (list "--lua-filter"
                                                   (expand-file-name (concat filter ".lua")
                                                                     imprimeur-hyphenate-test-filters)))
                                           '("common" "french" "hyphenate"))))))
        (should (equal status 0)))
      (string-replace "\u00AD" "|" (string-trim (buffer-string))))))

(defun imprimeur-hyphenate-test-words (language rows)
  "Check ROWS in LANGUAGE: each a word as it should break, or stay whole, with bars."
  (dolist (row rows)
    (ert-info (row)
      (should (equal (imprimeur-hyphenate-test-run language (string-replace "|" "" row) "plain") row)))))

(ert-deftest imprimeur-hyphenate-breaks-known-french-words ()
  (imprimeur-hyphenate-test-words
   "fr" '("ty|po|gra|phie" "bi|blio|thèque" "or|di|na|teur" "mon|tagne" "châ|teau" "uni|ver|sité"
          "phi|lo|so|phie" "éga|lité")))

(ert-deftest imprimeur-hyphenate-breaks-known-english-words ()
  (imprimeur-hyphenate-test-words
   "en" '("to|gether" "beau|ti|ful" "gov|ern|ment" "im|port|ant" "hy|phen|a|tion" "uni|versity")))

(ert-deftest imprimeur-hyphenate-keeps-its-rules ()
  (ert-info ("At least 6 letters")
    (imprimeur-hyphenate-test-words "fr" '("table" "che|val")))
  (ert-info ("None after s, between c and t, or in an f tie")
    ;; ins|truc|tion, dif|fi|cile, souf|fler, les|quels by the patterns of a dictionary.
    (imprimeur-hyphenate-test-words "fr" '("instruction" "diffi|cile" "souffler" "lesquels"))
    (imprimeur-hyphenate-test-words "en" '("basket" "actor" "diffi|cult")))
  (ert-info ("Capitals, in French")
    (imprimeur-hyphenate-test-words "fr" '("Bordeaux" "BORDEAUX" "Typographie")))
  (ert-info ("Capitals, in English")
    (imprimeur-hyphenate-test-words "en" '("Madrid" "Wash|ing|ton" "ALEXANDER" "McDonalds" "iPhoneography"))))

(defun imprimeur-hyphenate-test-short-breaks (text)
  "Return the words of TEXT, with bars, that leave too few letters at an edge.
Fails when TEXT holds too few breaks to say anything."
  (let ((case-fold-search nil) (start 0) (breaks 0) (short nil))
    (while (string-match "[[:alpha:]]+\\(?:|[[:alpha:]]+\\)+" text start)
      (let* ((word (match-string 0 text))
             (end (match-end 0))
             (parts (split-string word "|")))
        (setq start end
              breaks (1+ breaks))
        (when (or (< (length (car parts)) 2) (< (length (car (last parts))) 3))
          (push word short))))
    (should (> breaks 100))
    short))

(ert-deftest imprimeur-hyphenate-leaves-enough-letters-at-each-end ()
  (pcase-dolist (`(,language . ,file) '(("fr" . "examples/xix/francais.org") ("en" . "README.md")))
    (ert-info (file)
      (should-not
       (imprimeur-hyphenate-test-short-breaks
        (imprimeur-hyphenate-test-run
         language
         (with-temp-buffer
           (insert-file-contents (expand-file-name file repo-test-root))
           (buffer-string))
         "plain"))))))

(ert-deftest imprimeur-hyphenate-breaks-only-prose ()
  (dolist (text '("`typographie`"
                  "```\ntypographie\n```"
                  "```mermaid\ngraph LR\n  typographie\n```\n\nPlate: typographie"
                  "<div title=\"typographie\">x</div>"
                  "$typographie$"
                  "<https://example.org/typographie-longue>"
                  "[https://example.org/typographie](https://example.org/typographie)"
                  "<typographie@example.invalid>"
                  "typographie.example.org"
                  "docs/typographie"
                  "typographie2"
                  "# typographie\n"
                  "![typographie](pic.png)"
                  "Table: typographie\n\n| a |\n|---|\n| typographie |\n"))
    (ert-info (text)
      (should-not (string-search "|" (string-replace "| a |" "" (imprimeur-hyphenate-test-run "fr" text "html"))))))
  (dolist (text '("Une typographie."
                  "*Une typographie.*"
                  "Une note.[^1]\n\n[^1]: Une typographie."
                  "> Une typographie."
                  "- Une typographie."
                  "[Une typographie](https://example.org/)"))
    (ert-info (text)
      (should (string-search "ty|po|gra|phie" (imprimeur-hyphenate-test-run "fr" text "html"))))))

(ert-deftest imprimeur-hyphenate-follows-the-document-s-language ()
  (pcase-dolist (`(,language . ,expected)
                 '(("fr" . "ty|po|gra|phie") ("fr-CA" . "ty|po|gra|phie") ("FR" . "ty|po|gra|phie")
                   ("en" . "ty|po|graphie") ("en-GB" . "ty|po|graphie") (nil . "ty|po|graphie")
                   ("de" . "typographie") ("fry" . "typographie") ("zh-Hant" . "typographie")))
    (ert-info ((or language "none"))
      (should (equal (imprimeur-hyphenate-test-run language "typographie" "plain") expected)))))

(defun imprimeur-hyphenate-test-bytes (file)
  "Return the bytes of FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (buffer-string)))

(ert-deftest imprimeur-hyphenate-holds-the-vendored-patterns ()
  (let ((filter (imprimeur-hyphenate-test-bytes
                 (expand-file-name "hyphenate.lua" imprimeur-hyphenate-test-filters))))
    (pcase-dolist (`(,name . ,file) '(("french" . "hyph-fr.pat.txt") ("english" . "hyph-en-gb.pat.txt")))
      (ert-info (file)
        (let ((vendored (imprimeur-hyphenate-test-bytes (expand-file-name file imprimeur-hyphenate-test-vendored)))
              (opening (format "local %s = [[\n" name)))
          (should (string-search (concat opening vendored "]]\n") filter)))))))

(ert-deftest imprimeur-hyphenate-records-the-licence-and-checksums-of-its-patterns ()
  (let ((notice (imprimeur-hyphenate-test-bytes (expand-file-name "NOTICE" imprimeur-hyphenate-test-vendored)))
        (readme (imprimeur-hyphenate-test-bytes (expand-file-name "README.md" imprimeur-hyphenate-test-vendored))))
    ;; Both headers name the licence, and the text of each stands in full.
    (should (string-search "name: MIT" notice (1+ (string-search "name: MIT" notice))))
    (should (string-search "may be freely distributed" notice))
    (dolist (file '("hyph-fr.pat.txt" "hyph-en-gb.pat.txt"))
      (ert-info (file)
        (should (string-search
                 (format "%s  %s" (secure-hash 'sha256 (imprimeur-hyphenate-test-bytes
                                                        (expand-file-name file imprimeur-hyphenate-test-vendored)))
                         file)
                 readme))))))

(ert-deftest imprimeur-hyphenate-stays-within-the-limit-of-complexity ()
  (let ((luacheck (imprimeur-test-require "luacheck")))
    (should (equal (call-process luacheck nil nil nil "--no-config" "--no-color"
                                 "--max-cyclomatic-complexity" "10" "--globals" "pandoc" "--"
                                 (expand-file-name "hyphenate.lua" imprimeur-hyphenate-test-filters))
                   0))))

;;; imprimeur-hyphenate-test.el ends here
