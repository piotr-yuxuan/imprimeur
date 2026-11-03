;;; imprimeur-skin-test.el --- Tests of skins and of the filters they share  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 019, with plans 007 and 009).  A manifest takes the keys of
;; the plan and refuses anything else: a name outside [a-z][a-z0-9-]*, an unknown
;; key, a directory remote or relative, no stylesheet, a file name with `..', or
;; not regular, or of another extension, a shared filter that does not exist or is
;; the core's, an option that is malformed or whose default is no choice.  A
;; refusal warns and registers nothing.  Only a registered skin's listed files are
;; served, compared whole.  An option takes the view's choice, then the
;; configuration, then the default, and at its default leaves the root bare; an
;; entry that nothing registers warns once.  pandoc takes a skin's filters between
;; the core's two, +smart only where the format has it, and nothing of an option.
;;
;; The filters, on real pandoc in Org and in gfm: a filter sees whole words and one
;; shape of block, may wrap any block and set the title and the language, and the
;; lines and the marker survive it.  `common' and `french' do what plan 009 says of
;; them, and `french' nothing to code, to a bare address or outside French.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-skin)

(defun imprimeur-skin-test-directory (&rest files)
  "Return a new directory holding the FILES named, each with a line of text."
  (let ((directory (make-temp-file "skin" t)))
    (dolist (file files)
      (make-directory (file-name-directory (expand-file-name file directory)) t)
      (write-region "/* A file. */\n" nil (expand-file-name file directory) nil 'silent))
    directory))

(defmacro imprimeur-skin-test-with-registry (&rest body)
  "Run BODY with a registry of its own, holding what the core registers."
  (declare (indent 0))
  `(let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
         (imprimeur-skin--warned nil))
     ,@body))

(ert-deftest imprimeur-skin-parser-takes-the-whole-manifest ()
  (let* ((directory (imprimeur-skin-test-directory "skin.css" "img/rule.svg" "mine.lua"))
         (options '((tone :label "Tone" :choices (("soft" . "Soft") ("loud" . "Loud")) :default "soft")))
         (parsed (imprimeur-skin-parse-manifest
                  'mine (list :title "Mine" :directory directory :stylesheets '("skin.css")
                              :files '("img/rule.svg") :filters '(common "mine.lua" french)
                              :smart t :notes 'section :options options)))
         (manifest (nth 1 parsed)))
    (should (eq (car parsed) :ok))
    (should (equal (plist-get manifest :directory) (file-name-as-directory directory)))
    (should (equal (plist-get manifest :files) '("img/rule.svg")))
    (should (equal (plist-get manifest :filters)
                   (list (expand-file-name "pandoc/filters/common.lua" imprimeur-render-assets)
                         (expand-file-name "mine.lua" directory)
                         (expand-file-name "pandoc/filters/french.lua" imprimeur-render-assets))))
    (should (eq (plist-get manifest :smart) t))
    (should (eq (plist-get manifest :notes) 'section))
    (should (equal (plist-get manifest :options) options))))

(ert-deftest imprimeur-skin-parser-refuses ()
  (let* ((directory (imprimeur-skin-test-directory "skin.css" "font.woff2" "not-lua.txt" "sub/a.css"))
         (base (list :title "T" :directory directory :stylesheets '("skin.css")))
         (choices '(("a" . "A") ("b" . "B")))
         (good-option `(tone :label "Tone" :choices ,choices :default "a")))
    (make-directory (expand-file-name "dir.css" directory))
    (pcase-dolist (`(,name . ,manifest)
                   `((Mine . ,base) (a/b . ,base) (a..b . ,base) (\.\. . ,base) ("mine" . ,base)
                     (,(intern (make-string 65 ?a)) . ,base)
                     (mine . (:title "T"))
                     (mine . ,(append base '(:unknown 1)))
                     (mine . ,(append base '(:keys ("s"))))
                     (mine . ,(append base '(:title)))
                     (mine . (:directory ,directory :stylesheets ("skin.css")))
                     (mine . (:title "T" :directory ,directory))
                     (mine . (:title "T" :directory ,directory :stylesheets nil))
                     (mine . (:title "T" :directory "relative/" :stylesheets ("skin.css")))
                     (mine . (:title "T" :directory "/ssh:host:/skins/" :stylesheets ("skin.css")))
                     ,@(mapcar (lambda (file)
                                 `(mine . (:title "T" :directory ,directory :stylesheets (,file))))
                               '("../skin.css" "sub/../skin.css" "/etc/passwd.css" "absent.css" "dir.css"
                                 ".hidden.css" "a b.css" "é.css" "%2e%2e/skin.css" "sub//a.css"))
                     (mine . ,(append base '(:files ("font.woff2"))))
                     (mine . ,(append base '(:files ("../skin.css"))))
                     (mine . ,(append base '(:files "skin.css")))
                     (mine . ,(append base '(:filters ("not-lua.txt"))))
                     (mine . ,(append base '(:filters ("absent.lua"))))
                     (mine . ,(append base '(:filters (no-such-filter))))
                     (mine . ,(append base '(:filters (imprimeur))))
                     (mine . ,(append base '(:filters (finish))))
                     (mine . ,(append base '(:filters (\.\./imprimeur))))
                     (mine . ,(append base '(:filters (nil))))
                     (mine . ,(append base '(:smart "yes")))
                     (mine . ,(append base '(:notes document)))
                     (mine . ,(append base `(:options ((Tone :label "L" :choices ,choices :default "a")))))
                     (mine . ,(append base `(:options ((tone :choices ,choices :default "a")))))
                     (mine . ,(append base `(:options (,good-option ,good-option))))
                     (mine . ,(append base '(:options ((tone :label "L" :choices (("a" . "A")) :default "a")))))
                     (mine . ,(append base `(:options ((tone :label "L" :choices ,choices :default "c")))))
                     (mine . ,(append base '(:options ((tone :label "L" :default "a"
                                                             :choices (("a" . "A") ("a" . "B")))))))
                     (mine . ,(append base '(:options ((tone :label "L" :default "a"
                                                             :choices (("a" . "A") ("A b" . "B")))))))))
      (ert-info ((format "%S %S" name manifest))
        (should (eq (car (imprimeur-skin-parse-manifest name manifest)) :error))))
    (should (eq (car (imprimeur-skin-parse-manifest
                      'mine (append base `(:options (,good-option)))))
                :ok))))

(ert-deftest imprimeur-skin-define-warns-and-registers-nothing-on-a-refusal ()
  (imprimeur-skin-test-with-registry
    (let ((warnings nil)
          (directory (imprimeur-skin-test-directory "skin.css")))
      (cl-letf (((symbol-function 'display-warning)
                 (lambda (_type message &rest _) (push message warnings))))
        (should-not (imprimeur-skin-define 'mine :title "T" :directory directory
                                           :stylesheets '("skin.css") :page "no"))
        (should-not (imprimeur-skin-get "mine"))
        (should (string-search ":page" (car warnings)))
        (should (eq (imprimeur-skin-define 'mine :title "T" :directory directory :stylesheets '("skin.css"))
                    'mine))
        (should (equal (length warnings) 1))
        (should (member "mine" (imprimeur-skin-names)))
        (should (member "minitel" (imprimeur-skin-names)))))))

(ert-deftest imprimeur-skin-initial-name-falls-back-on-minitel ()
  (let ((imprimeur-skin 'minitel)
        (messages nil))
    (should (equal (imprimeur-skin-initial-name) "minitel"))
    (cl-letf (((symbol-function 'message) (lambda (&rest args) (push args messages))))
      (let ((imprimeur-skin 'nothing-registered))
        (should (equal (imprimeur-skin-initial-name) "minitel"))))
    (should (= (length messages) 1))))

(ert-deftest imprimeur-skin-serves-listed-files-only ()
  (imprimeur-skin-test-with-registry
    (let ((directory (imprimeur-skin-test-directory "skin.css" "img/rule.svg" "other.css" "filter.lua")))
      (imprimeur-skin-define 'mine :title "T" :directory directory :stylesheets '("skin.css")
                             :files '("img/rule.svg") :filters '("filter.lua"))
      (pcase-dolist (`(,path . ,file)
                     `(("skins/mine/0/skin.css" . "skin.css")
                       ("skins/mine/12/img/rule.svg" . "img/rule.svg")
                       ("skins/mine/x/skin.css")
                       ("skins/mine/skin.css")
                       ("skins/mine/0/other.css")
                       ("skins/mine/0/filter.lua")
                       ("skins/mine/0/../mine/0/skin.css")
                       ("skins/mine/0/img/../skin.css")
                       ("skins/mine/0/%73kin.css")
                       ("skins/absent/0/skin.css")
                       ("skins/../mine/0/skin.css")
                       ("js/runtime.mjs")
                       (nil)))
        (ert-info ((format "%S" path))
          (should (equal (car (imprimeur-skin-served-file path))
                         (and file (expand-file-name file directory))))))
      (should (equal (cdr (imprimeur-skin-served-file "skins/mine/0/skin.css")) "text/css; charset=utf-8"))
      (should (equal (cdr (imprimeur-skin-served-file "skins/mine/0/img/rule.svg")) "image/svg+xml"))
      (delete-file (expand-file-name "skin.css" directory))
      (should-not (imprimeur-skin-served-file "skins/mine/0/skin.css")))))

(ert-deftest imprimeur-skin-attributes-decide-by-precedence ()
  (let ((manifest '(:options ((tone :label "T" :choices (("soft" . "S") ("loud" . "L")) :default "soft")
                              (face :label "F" :choices (("a" . "A") ("b" . "B")) :default "a")))))
    (pcase-dolist (`(,configured ,chosen ,expected)
                   '((nil nil [])
                     (((tone . "soft")) nil [])
                     (nil ((tone . "soft")) [])
                     (((tone . "loud")) nil [["data-xix-tone" "loud"]])
                     (nil ((tone . "loud")) [["data-xix-tone" "loud"]])
                     (((tone . "loud")) ((tone . "soft")) [])
                     (((tone . "soft")) ((tone . "loud")) [["data-xix-tone" "loud"]])
                     (((face . "b")) ((tone . "loud")) [["data-xix-tone" "loud"] ["data-xix-face" "b"]])))
      (should (equal (imprimeur-skin-attributes "xix" manifest configured chosen) expected)))))

(ert-deftest imprimeur-skin-configured-warns-once-of-what-nothing-registers ()
  (let* ((manifest '(:options ((tone :label "T" :choices (("soft" . "S") ("loud" . "L")) :default "soft"))))
         (imprimeur-skin-options (list (list (intern "xix") '(tone . "loud") '(tone . "shrill") '(size . "9"))
                                       (list (intern "other-skin") '(tone . "soft"))))
         (imprimeur-skin--warned nil)
         (warnings 0))
    (cl-letf (((symbol-function 'display-warning) (lambda (&rest _) (setq warnings (1+ warnings)))))
      (should (equal (imprimeur-skin-configured "xix" manifest) '((tone . "loud"))))
      (should (= warnings 2))
      (should (equal (imprimeur-skin-configured "xix" manifest) '((tone . "loud"))))
      (should (= warnings 2)))))

(ert-deftest imprimeur-skin-arguments-put-a-skin-between-the-core-filters ()
  (let* ((imprimeur-pandoc-program (imprimeur-test-require "pandoc"))
         (filters (lambda (arguments)
                    (mapcar (lambda (argument) (file-name-nondirectory (substring argument 13)))
                            (seq-filter (lambda (argument) (string-prefix-p "--lua-filter=" argument))
                                        arguments))))
         (bare (imprimeur-render-arguments "org" nil nil "bash"))
         (skin '(:filters ("/a/one.lua" "/b/two.lua") :smart t :notes section))
         (dressed (imprimeur-render-arguments "org" nil nil "bash" skin)))
    (should (equal (funcall filters bare) '("imprimeur.lua" "finish.lua")))
    (should (equal (funcall filters dressed) '("imprimeur.lua" "one.lua" "two.lua" "finish.lua")))
    (should (equal (seq-take dressed 2) '("-f" "org+smart")))
    (should (member "--reference-location=section" dressed))
    (should-not (member "--reference-location=section" bare))
    (should (equal (car (last dressed)) "--sandbox"))))

(ert-deftest imprimeur-skin-smart-is-asked-of-the-format ()
  (let ((imprimeur-render--smart nil)
        (pandoc (imprimeur-test-require "pandoc")))
    (pcase-dolist (`(,reader . ,expected)
                   '(("org" . "org+smart") ("gfm+sourcepos" . "gfm+sourcepos+smart") ("rst" . "rst+smart")
                     ("creole" . "creole") ("pod" . "pod") ("csv" . "csv") ("tsv" . "tsv")))
      (should (equal (imprimeur-render-smart-reader pandoc reader) expected)))
    (let ((asked 0)
          (original (symbol-function 'process-lines)))
      (cl-letf (((symbol-function 'process-lines)
                 (lambda (&rest arguments) (setq asked (1+ asked)) (apply original arguments))))
        (imprimeur-render-smart-reader pandoc "org")
        (imprimeur-render-smart-reader pandoc "org+sourcepos")
        (should (= asked 0))))
    (should (equal (imprimeur-render-smart-reader "/no/such/pandoc" "org") "org"))))

;;;; The filters, on real pandoc

(defun imprimeur-skin-test-filter (source)
  "Return a Lua file holding SOURCE."
  (make-temp-file "filter" nil ".lua" source))

(defun imprimeur-skin-test-render (reader text &rest filters)
  "Return the outcome of TEXT read by READER through FILTERS, smartly."
  (let* ((pandoc (imprimeur-test-require "pandoc"))
         (imprimeur-pandoc-program pandoc)
         (outcome nil))
    (imprimeur-render-start
     (list :program pandoc :text text :directory (make-temp-file "render" t)
           :arguments (imprimeur-render-arguments reader nil nil (imprimeur-render-languages pandoc)
                                                  (list :filters filters :smart t)))
     (lambda (result) (setq outcome result)))
    (imprimeur-test-wait-for (lambda () outcome))))

(defun imprimeur-skin-test-html (reader text &rest filters)
  "Return the HTML of TEXT read by READER through FILTERS."
  (let ((outcome (apply #'imprimeur-skin-test-render reader text filters)))
    (should (eq (car outcome) :ok))
    (nth 1 outcome)))

(defun imprimeur-skin-test-shared (name)
  "Return the file of the shared filter NAME."
  (expand-file-name (format "pandoc/filters/%s.lua" name) imprimeur-render-assets))

(defconst imprimeur-skin-test-wrap-every-block
  "return { { Pandoc = function (doc)
  local out = pandoc.Blocks({})
  for _, block in ipairs(doc.blocks) do
    out:insert(pandoc.Div({ block }, { class = 'kept' }))
  end
  doc.blocks = out
  return doc
end } }"
  "A filter that puts every block of the top level in a Div with a class.")

(defconst imprimeur-skin-test-readers
  '(("gfm+sourcepos" . "One\n\ntwo\n\n# Three\n\n```\nfour\n```\n")
    ("org" . "#+IMPRIMEUR_LINE: 1\nOne\n\n#+IMPRIMEUR_LINE: 3\ntwo\n\n#+IMPRIMEUR_LINE: 5\n* Three\n\n#+IMPRIMEUR_LINE: 7\n#+begin_src\nfour\n#+end_src\n"))
  "A document of four blocks, starting at lines 1, 3, 5 and 7, in each format.")

(ert-deftest imprimeur-skin-filter-sees-whole-words ()
  (let ((probe (imprimeur-skin-test-filter
                "return { { Str = function (str) if str.text == 'pense-t-on' then return pandoc.Str('WHOLE') end end } }")))
    (dolist (reader '("gfm+sourcepos" "org"))
      (should (string-search "WHOLE" (imprimeur-skin-test-html reader "Que pense-t-on?\n\npense-t-on\n" probe))))))

(ert-deftest imprimeur-skin-filter-may-wrap-any-block-and-keep-its-line ()
  (let ((wrap (imprimeur-skin-test-filter imprimeur-skin-test-wrap-every-block)))
    (pcase-dolist (`(,reader . ,text) imprimeur-skin-test-readers)
      (ert-info (reader)
        (let ((html (imprimeur-skin-test-html reader text wrap))
              (start 0)
              (lines nil))
          (while (string-match "<div data-imprimeur-line=\"\\([0-9]+\\)\"></div>\n<[^>]*class=\"kept\"" html start)
            (push (string-to-number (match-string 1 html)) lines)
            (setq start (match-end 0)))
          (should (equal (nreverse lines) '(1 3 5 7))))))))

(ert-deftest imprimeur-skin-org-gives-a-filter-the-shape-of-markdown ()
  (let ((mark (imprimeur-skin-test-filter
               "local function unwrapped(block)
  if block.t == 'Div' and block.attributes.wrapper and #block.content == 1 then return block.content[1] end
  return block
end
return { { Pandoc = function (doc)
  local out = pandoc.Blocks({})
  for _, block in ipairs(doc.blocks) do
    if unwrapped(block).t == 'Para' then block.classes:insert('marked') end
    out:insert(block)
  end
  doc.blocks = out
  return doc
end } }")))
    ;; A paragraph is in a wrapper in both formats, and a heading carries its own.
    (pcase-dolist (`(,reader . ,text) imprimeur-skin-test-readers)
      (ert-info (reader)
        (let ((html (imprimeur-skin-test-html reader text mark)))
          (should (= (cl-count-if (lambda (word) (string-search "marked" word))
                                  (split-string html "\n"))
                     2))
          ;; A wrapper that a filter gave a class stays, and with it its paragraph.
          (should (string-match-p "class=\"marked\"[^>]*>\n<p>One</p>" html))
          (should-not (string-match-p "<h1[^>]*data-imprimeur-line" html)))))
    ;; With no filter, Org leaves no wrapper and no attribute: the page's p + p holds.
    (let ((html (imprimeur-skin-test-html "org" (cdr (assoc "org" imprimeur-skin-test-readers)))))
      (should-not (string-search "data-wrapper" html))
      (should (string-match-p "<p>One</p>\n<div data-imprimeur-line=\"3\"></div>\n<p>two</p>" html)))
    (dolist (hostile '("#+ATTR_HTML: :data-imprimeur-line 3\"><script>alert(1)</script>\n| a |\n"
                       "#+IMPRIMEUR_LINE: 1\n#+begin_center\nx\n#+end_center\n"))
      (let ((html (imprimeur-skin-test-html "org" hostile)))
        (should-not (string-search "<script" html))
        (should-not (string-match-p "data-imprimeur-line=\"[^0-9]" html))))))

(ert-deftest imprimeur-skin-filter-may-set-title-and-language-and-insert-first ()
  (let ((set (imprimeur-skin-test-filter
              "return { { Pandoc = function (doc)
  doc.meta.title = 'From a filter'
  doc.meta.lang = 'fr'
  doc.blocks:insert(1, pandoc.Para({ pandoc.Str('First') }))
  return pandoc.Pandoc(doc.blocks, doc.meta)
end } }")))
    (dolist (reader '("gfm+sourcepos" "org"))
      (let ((outcome (imprimeur-skin-test-render reader "Words.\n" set)))
        (should (eq (car outcome) :ok))
        (should (equal (nth 2 outcome) '(:title "From a filter" :lang "fr")))
        (should (string-prefix-p "<p>First</p>" (nth 1 outcome)))))))

(ert-deftest imprimeur-skin-finish-keeps-a-language-out-of-pandocs-warnings ()
  (let ((outcome (imprimeur-skin-test-render "gfm" "---\nlang: zh-TW\n---\n\nWords.\n")))
    (should (equal (plist-get (nth 2 outcome) :lang) "zh-TW"))
    (should-not (nth 3 outcome))))

(ert-deftest imprimeur-skin-common-shapes-a-document ()
  (let ((common (imprimeur-skin-test-shared "common"))
        (start "\\`\\(?:<div data-imprimeur-line=\"1\"></div>\n\\)?"))
    (pcase-dolist (`(,reader ,text ,expected . ,refused)
                   `(("org" "Words.\n\n* Lone\n\nMore.\n" "<h1 class=\"unnumbered\"")
                     ("gfm" "Words.\n\n# Lone\n\nMore.\n" "<h1 class=\"unnumbered\"")
                     ("org" "#+title: T\n\n* Lone\n\nMore.\n" "<h1 class=\"unnumbered\"")
                     ("org" "* One\n\n* Two\n" "<h1 id=\"doc-one\">\\|<h1 id=\"one\">" "unnumbered")
                     ("gfm" "![A picture](pic.png)\n" "<figure>" )
                     ("gfm" "![A film](clip.webm)\n" "<figure>")
                     ("org" "[[file:clip.webm][A film]]\n" "<figure>")
                     ("gfm" "![](pic.png)\n" "<img" "<figure>")
                     ("org" "[[file:clip.webm]]\n" "<video" "<figure>")
                     ("org" "See [[file:clip.webm][a film]] here.\n" "<a href=\"clip.webm\">a film</a>" "<figure>" "<video")
                     ("gfm" "Table: The data.\n\n| a |\n|---|\n| b |\n" "<caption>The data.</caption>" "Table:")
                     ("gfm" "表：資料\n\n| a |\n|---|\n| b |\n" "<caption>資料</caption>" "表：")
                     ("gfm" "Table: No table follows.\n" "Table: No table")
                     ("gfm" "```mermaid\ngraph TD\n```\n\nPlate: The plan.\n"
                      "class=\"captioned-content\"" "Plate:")
                     ("gfm" "```mermaid\ngraph TD\n```\n\nFigure: The plan.\n"
                      "class=\"captioned-content\"" "Figure:")
                     ("gfm" "```mermaid\ngraph TD\n```\n\n圖：計畫\n"
                      "class=\"captioned-content\"" "圖：")
                     ("gfm" "Plate: No diagram before.\n" "Plate: No diagram")
                     ("gfm" "<https://example.org/a_b?c=d>\n"
                      "https://<wbr>example.org/<wbr>a_<wbr>b\\?<wbr>c=<wbr>d</a>")
                     ("org" "[[https://example.org/a][a site]]\n" ">a site</a>" "<wbr>")
                     ("gfm" "```\nplain\n```\n" "<div class=\"imprimeur-code\">")
                     ("org" "#+begin_src\nplain\n#+end_src\n" "<div class=\"imprimeur-code\">")
                     ("gfm" "```python\nx = 1\n```\n" "sourceCode" "imprimeur-code")))
      (ert-info ((format "%s: %s" reader text))
        (let ((html (imprimeur-skin-test-html reader text common)))
          (should (string-match-p expected html))
          (dolist (word refused) (should-not (string-search word html))))))
    (dolist (reader '("org" "gfm"))
      (let ((outcome (imprimeur-skin-test-render
                      reader (if (equal reader "org") "* Alone\n\nWords.\n" "# Alone\n\nWords.\n") common)))
        (should (equal (plist-get (nth 2 outcome) :title) "Alone"))
        (should-not (string-search "<h1" (nth 1 outcome)))
        (should (string-match-p (concat start "\\(?:<div data-wrapper[^>]*>\n\\)?<p>Words") (nth 1 outcome)))))))

(defun imprimeur-skin-test-french (reader text)
  "Return the HTML of TEXT, in French, read by READER through `french'."
  (imprimeur-skin-test-html reader
                            (if (string-prefix-p "gfm" reader)
                                (concat "---\nlang: fr\n---\n\n" text)
                              (concat "#+LANGUAGE: fr\n\n" text))
                            (imprimeur-skin-test-shared "french")))

(ert-deftest imprimeur-skin-french-sets-french ()
  (pcase-dolist (`(,text . ,expected)
                 '(("Oui ? Non ! Si ; et : fin.\n" . "Oui ? Non ! Si ; et : fin.")
                   ("Oui? Non! Si; et: fin.\n" . "Oui ? Non ! Si ; et : fin.")
                   ("Oui ? Non !\n" . "Oui ? Non !")
                   ("Il dit « non » et «oui».\n" . "Il dit « non » et « oui ».")
                   ("Il dit \"non\".\n" . "Il dit « non ».")
                   ("Il dit \"non 'jamais' non\".\n" . "« non “jamais” non ».")
                   ("Que pense-t-on, va-t-il ?\n"
                    . "<span class=\"imprimeur-inversion\">pense-t-on</span>, <span class=\"imprimeur-inversion\">va-t-il</span> ?")
                   ("Au XXe siècle.\n" . "<span class=\"imprimeur-siecle\">XX<sup>e</sup></span> siècle")
                   ("Le 1er, Mme et Mlle.\n"
                    . "<span class=\"imprimeur-superieur\">1<sup>er</sup></span>, <span class=\"imprimeur-superieur\">M<sup>me</sup></span> et <span class=\"imprimeur-superieur\">M<sup>lle</sup></span>.")
                   ("Le 12:30 et a:b restent.\n" . "Le 12:30 et a:b restent.")))
    (dolist (reader '("gfm+sourcepos" "org"))
      (ert-info ((format "%s: %s" reader text))
        (should (string-search expected (imprimeur-skin-test-french reader text)))))))

(ert-deftest imprimeur-skin-french-leaves-code-and-addresses ()
  (let ((html (imprimeur-skin-test-french "gfm+sourcepos"
                                          "`a ? b` et <https://example.org/a?b>\n\n```\nc ? \"d\" Mme\n```\n")))
    (should (string-search ">a ? b</code>" html))
    (should (string-search "https://example.org/a?b</a>" html))
    (should (string-search "c ? &quot;d&quot; Mme" html)))
  ;; A word of the document in another language stays as it is.
  (dolist (text '("---\nlang: en\n---\n\nWho ? \"Mme\" pense-t-on XXe.\n" "Who ? pense-t-on XXe.\n"))
    (let ((html (imprimeur-skin-test-html "gfm" text (imprimeur-skin-test-shared "french"))))
      (should-not (string-search " " html))
      (should-not (string-search "imprimeur-" html)))))

(ert-deftest imprimeur-skin-french-says-alerts-and-spaces-a-title ()
  (should (string-search "Avertissement"
                         (imprimeur-skin-test-french "gfm+sourcepos" "> [!WARNING]\n> Prudence.\n")))
  (let ((outcome (imprimeur-skin-test-render "org" "#+LANGUAGE: fr\n#+title: Que dit-on ?\n\nMot.\n"
                                             (imprimeur-skin-test-shared "french"))))
    (should (equal (plist-get (nth 2 outcome) :title) "Que dit-on ?"))))

(ert-deftest imprimeur-skin-filters-take-nothing-from-the-document-as-a-path ()
  ;; A document's metadata can name no filter and no option.
  (let ((html (imprimeur-skin-test-html
               "gfm" "---\nlua-filter: /etc/passwd\nimprimeur-option-tone: loud\n---\n\nWords.\n"
               (imprimeur-skin-test-shared "common") (imprimeur-skin-test-shared "french"))))
    (should (string-match-p "<p>Words.</p>" html))
    (should-not (string-search "loud" html))))

;;; imprimeur-skin-test.el ends here
