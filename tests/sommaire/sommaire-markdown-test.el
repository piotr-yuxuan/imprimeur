;;; sommaire-markdown-test.el --- The Markdown adapter of sommaire  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: docs/minitoc-rules.md, "What an adapter puts in the tree", R2,
;; R4, R5 and R6, and plan 005: for every fixture in Markdown, the adapter's
;; model equals NAME.model.json, and the scanner's headings equal pandoc's.
;; Pandoc is the oracle for the block structure: real pandoc, read through its
;; JSON output, judges every Markdown fixture and the documents of
;; `sommaire-markdown-test--documents', so that none of these expectations
;; comes from the scanner.  The other expectations come from the rules.

;;; Code:

(require 'ert)
(require 'json)
(require 'seq)
(require 'repo-test-helpers)
(require 'sommaire-test-helpers)
(require 'sommaire-markdown)

(defconst sommaire-markdown-test--pandoc-filter
  (concat "function Pandoc(doc)\n"
          "  local toc = pandoc.structure.table_of_contents(doc, {toc_depth = 6})\n"
          "  return pandoc.Pandoc({toc, pandoc.Div(doc.blocks)})\n"
          "end\n")
  "A Lua filter that gives pandoc's table of contents, then the document's blocks.")

(defconst sommaire-markdown-test--documents
  '(;; ATX headings.
    "# One\n## Two\n### Three\n#### Four\n##### Five\n###### Six\n"
    "####### Seven hashes\n"
    "#No space\n"
    "#\tA tab\n"
    " # One space\n  ## Two spaces\n   ### Three spaces\n"
    "    # Four spaces\n"
    "\t# A tab of indentation\n"
    "  \t# Spaces then a tab\n"
    "## Closed ##\n"
    "## Closed with more ######   \n"
    "# Not closed#\n"
    "# Hash # inside\n"
    "#\n"
    "## ##\n"
    "A paragraph\n# Interrupted\nThe paragraph after\n"
    "# Spaced    out   words\n"
    ;; Setext headings.
    "One\n===\n"
    "Two\n---\n"
    "Two\n-\n"
    "One\n=\n"
    "  Indented\n  ---\n"
    "Three spaces\n   ===  \n"
    "Four spaces\n    ---\n"
    "Several\nlines\nof it\n---\n"
    "Then indented\n    continued\n---\n"
    "A = B\n= =\n"
    "\n===\n"
    "---\n"
    "--\n"
    "Paragraph\n\n---\n"
    ;; Thematic breaks.
    "Text\n***\n# After\n"
    "- - -\n# After\n"
    "* * *\n# After\n"
    "_ _ _\n# After\n"
    "-- -\nText\n"
    ;; Fences.
    "```\n# In code\n```\n# After\n"
    "~~~\n# In code\n~~~\n# After\n"
    "````\n```\n# In code\n````\n# After\n"
    "```\n# In code\n``\n# Still in code\n```\n# After\n"
    "```\n# In code\n~~~\n# Still in code\n"
    "   ```\n# In code\n  ```\n# After\n"
    "```\n# In code\n    ```\n# Still in code\n```\n# After\n"
    "``` not a fence ```\n# After\n"
    "~~~ a`b\n# In code\n~~~\n# After\n"
    "``` sh\n# In code\n``` sh\n# Still in code\n```\n# After\n"
    "A paragraph\n```\n# In code\n```\n# After\n"
    ;; Indented code.
    "    code\n\n    # Code\n\n# After\n"
    "A paragraph\n    # Continued\n"
    ;; HTML comments.
    "<!-- One line -->\n# After\n"
    "<!--\n# In a comment\n\n# Still\n-->\n# After\n"
    "<!-- Unclosed\n# In a comment\n"
    "   <!-- Indented -->\n# After\n"
    "    <!-- Code -->\n# After\n"
    "A paragraph\n<!-- Interrupting\n# In a comment\n-->\n# After\n"
    "A paragraph <!-- inline -->\n---\n"
    "## A title <!-- with a comment -->\n"
    "## Before <!-- a comment --> after\n"
    ;; Other HTML blocks.
    "<div>\n# Raw\n</div>\n\n# After\n"
    "<div>\n\n# Between blank lines\n\n</div>\n"
    "<DIV CLASS=\"a\">\n# Raw\n"
    "<details>\n# Raw\n</details>\n\n# After\n"
    "<details>\n\n# Between blank lines\n\n</details>\n"
    "<pre>\n\n# Raw\n\n</pre>\n# After\n"
    "<script>\n\n# Raw\n</script>\n# After\n"
    "<style>\n\n# Raw\n</style>\n# After\n"
    "<pre>One line</pre>\n# After\n"
    "<?php\n\n# Raw\n?>\n# After\n"
    "<!DOCTYPE html>\n# After\n"
    "<![CDATA[\n\n# Raw\n]]>\n# After\n"
    "<span>\n# Raw\n\n# After\n"
    "<span class=\"a\" id=\"b\">\n# Raw\n\n# After\n"
    "</span>\n# Raw\n\n# After\n"
    "A paragraph\n<span>\n# After\n"
    ;; Block quotes.
    "> # Quoted\n"
    ">No space\n# After\n"
    "   > # Indented\n"
    "> Quoted\n# After\n"
    "> Quoted\n---\n"
    "> Quoted\nlazily\n---\n"
    "> Quoted\nlazily\n===\n"
    "> Quoted\n\nText\n---\n"
    "A paragraph\n> Interrupted\n"
    "> ```\n> # In code\n> ```\n# After\n"
    ;; List items.
    "- # In an item\n"
    "+ # In an item\n"
    "* # In an item\n"
    "1. # In an item\n"
    "1) # In an item\n"
    "- Item\n# After\n"
    "- Item\n\n  # In the item\n\n# After\n"
    "- Item\n\n # Short of the content\n"
    "  - Indented item\n\n    # In the item\n\n  # Short of the content\n"
    "- Item\n  # In the item\n"
    "- Item\n---\n"
    "- Item\n# After\n  ## Indented after the list\n"
    "- Item\n\nA paragraph\n\n  ## Indented after the list\n"
    "> Quoted\n\n  ## Indented after the quote\n"
    "- Item\nlazily\n---\n"
    "- Item\n\nText\n---\n"
    "- Item\n  - Nested\n    # In the nested item\n\n# After\n"
    "- One\n- Two\n  # In the second\n\n# After\n"
    "1. One\n2. Two\n   # In the second\n\n# After\n"
    "10. One\n2. Two\n   # In the second\n"
    "1. Item\n\n   # In the item\n\n  # Short of the content\n"
    "-   Wide\n\n    # In the item\n\n# After\n"
    "-      Code in the item\n\n  # In the item\n\n# After\n"
    "-\n\n  # An empty item is over\n\n# After\n"
    "-\n  # In the item\n\n# After\n"
    "-\tA tab\n\n  # Short of the content\n"
    "- Item\n\n  ```\n  # In code\n# After\n"
    "A paragraph\n- Interrupted\n# After\n"
    "A paragraph\n1. Interrupted\n# After\n"
    "A paragraph\n2. Not a list\n---\n"
    "A paragraph\n-\n"
    "A paragraph\n*\n---\n"
    "2. Starts a list\n\n   # In the item\n"
    "1234567890. Too long for a marker\n---\n"
    "1.No space\n---\n"
    "-No space\n---\n"
    ;; Link definitions, which open a paragraph that they leave empty.
    "[a]: /url\n===\n"
    "[a]: /url \"Title\"\n---\n"
    "A paragraph\n[a]: /url\n---\n"
    "[a]: /url\nThen a paragraph\n---\n"
    "[a]: /url\n[b]: /url\nThen a paragraph\n---\n"
    "[a]: /url\n    # Continued\n   ---\n"
    "[a]: /url\n-\nMore\n---\n"
    ;; What a container leaves open.
    "> # Quoted\nA paragraph\n---\n"
    "> # Quoted\n<span>\n# Raw\n"
    ">\n    code\nA paragraph\n-\n"
    "> Quoted\n<span>\n# Raw\n"
    "- # In an item\nA paragraph\n---\n"
    "-\nA paragraph\n---\n"
    "  - Item\n<span>\n  # Raw\n"
    "- Item\n\n  # In the item\nA paragraph\n---\n"
    "- Item\n  ---\nA paragraph\n---\n"
    "- Item\n  continued\nlazily\n---\n"
    ;; Front matter.
    "---\ntitle: T\n---\n# After\n"
    "---\ntitle: T\n...\n# After\n"
    "---\ntitle: T\n# In the front matter\n---\n"
    "---\n\ntitle: T\n---\n"
    "\n---\ntitle: T\n---\n"
    "---\ntitle: T\n"
    "---\n# A comment\n---\n# After\n"
    "---\n# A comment\ntitle: T\n---\n# After\n"
    "---\n---\n# After\n"
    "---\n...\n# After\n"
    "---\n\"quoted\": T\n---\n# After\n"
    "---\n  indented: T\n---\n# After\n"
    ;; No mapping, so no front matter.
    "---\nJust text\n---\n# After\n"
    "---\n- A list\n---\n# After\n")
  "Markdown documents that pandoc judges, each pinning a trap of block structure.")

(defun sommaire-markdown-test--plain (inlines)
  "Return the text of pandoc's INLINES, which are plain or raw.
A title has no raw part, and single spaces between its words."
  (string-join
   (split-string
    (mapconcat (lambda (inline)
                 (pcase (plist-get inline :t)
                   ("Str" (plist-get inline :c))
                   ((or "Space" "SoftBreak") " ")
                   ("RawInline" "")
                   (type (error "Inline %s in a document that should be plain" type))))
               inlines ""))
   " "))

(defun sommaire-markdown-test--pandoc-headers (blocks)
  "Return (LEVEL . TITLE) of each heading of pandoc's BLOCKS, as a table of contents.
It reads the blocks at the top and those in a Div, since a heading in a
block quote or a list item stays out of pandoc's table of contents."
  (mapcan (lambda (block)
            (pcase (plist-get block :t)
              ("Header"
               (let ((content (plist-get block :c)))
                 (list (cons (nth 0 content)
                             (sommaire-markdown-test--plain (nth 2 content))))))
              ("Div" (sommaire-markdown-test--pandoc-headers
                      (nth 1 (plist-get block :c))))))
          blocks))

(defun sommaire-markdown-test--toc-titles (toc)
  "Return the titles in the bullet list TOC, in document order."
  (mapcan (lambda (item)
            (mapcan (lambda (block)
                      (pcase (plist-get block :t)
                        ("Plain"
                         ;; A heading with no identifier gets no link.
                         (let* ((inlines (plist-get block :c))
                                (link (and (equal (plist-get (car inlines) :t) "Link")
                                           (car inlines))))
                           (list (sommaire-markdown-test--plain
                                  (if link (nth 1 (plist-get link :c)) inlines)))))
                        ("BulletList" (sommaire-markdown-test--toc-titles block))))
                    item))
          (plist-get toc :c)))

(defun sommaire-markdown-test--pandoc (directory file)
  "Return what pandoc reads in FILE, through the filter in DIRECTORY.
The value is (HEADERS . TITLES): the (LEVEL . TITLE) of the headings in the
syntax tree, and the titles in the table of contents."
  (let* ((result (repo-test-run "pandoc"
                                (list "--from=gfm" "--to=json"
                                      "--lua-filter" (expand-file-name "toc.lua" directory)
                                      file)))
         (json-object-type 'plist)
         (json-array-type 'list)
         (blocks (progn
                   (should (eql (car result) 0))
                   (plist-get (json-read-from-string (cdr result)) :blocks))))
    (cons (sommaire-markdown-test--pandoc-headers (nth 1 (plist-get (nth 1 blocks) :c)))
          (sommaire-markdown-test--toc-titles (nth 0 blocks)))))

(defun sommaire-markdown-test--headings ()
  "Return (LEVEL . TITLE) of the headings that this buffer's outline holds."
  (delq nil (mapcar (lambda (place)
                      (and (plist-get place :level)
                           (cons (plist-get place :level) (plist-get place :title))))
                    (plist-get (sommaire-markdown-outline) :places))))

(defun sommaire-markdown-test--should-equal-pandoc (directory file)
  "Check this buffer's headings against what pandoc reads in FILE, its text.
DIRECTORY holds the filter."
  (let ((pandoc (sommaire-markdown-test--pandoc directory file))
        (headings (sommaire-markdown-test--headings)))
    (should (equal headings (car pandoc)))
    (should (equal (mapcar #'cdr headings) (cdr pandoc)))))

(defun sommaire-markdown-test--require-pandoc ()
  "Skip the running test when there is no pandoc, and name it."
  (unless (executable-find "pandoc")
    (ert-skip "missing executable pandoc")))

(defun sommaire-markdown-test--root-of (text)
  "Return the root of the model of a buffer holding TEXT."
  (with-temp-buffer
    (insert text)
    (plist-get (plist-get (sommaire-markdown-outline) :model) :root)))

(defun sommaire-markdown-test--titles (node)
  "Return the titles of the children of NODE."
  (mapcar (lambda (child) (plist-get child :title)) (plist-get node :children)))

(defun sommaire-markdown-test--first-child (text)
  "Return the first child of the root of the model of TEXT."
  (car (plist-get (sommaire-markdown-test--root-of text) :children)))

(defun sommaire-markdown-test--narrowed-root (text from to)
  "Return the root of TEXT narrowed from the text FROM up to the text TO.
FROM and TO are searched for from the start; a nil TO means the end."
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (let ((begin (progn (search-forward from) (match-beginning 0)))
          (end (if to
                   (progn (search-forward to) (match-beginning 0))
                 (point-max))))
      (narrow-to-region begin end)
      (plist-get (plist-get (sommaire-markdown-outline) :model) :root))))

(ert-deftest sommaire-markdown-model-of-every-fixture ()
  "For every fixture in Markdown, the adapter's model equals NAME.model.json."
  (should (sommaire-test-documents "md"))
  (dolist (name (sommaire-test-documents "md"))
    (ert-info (name)
      (with-temp-buffer
        (sommaire-test-insert name "md")
        (when (equal name "narrowing")
          (sommaire-test-narrow-to-usage "##"))
        (should (equal (plist-get (sommaire-markdown-outline) :model)
                       (sommaire-test-read name "model")))))))

(ert-deftest sommaire-markdown-headings-equal-pandocs-on-the-fixtures ()
  "On every Markdown fixture, the headings equal those of real pandoc.
This test needs pandoc."
  (sommaire-markdown-test--require-pandoc)
  (let ((directory (repo-test-tree `(("toc.lua" . ,sommaire-markdown-test--pandoc-filter)))))
    (should (sommaire-test-documents "md"))
    (dolist (name (sommaire-test-documents "md"))
      (ert-info (name)
        (let ((file (expand-file-name (concat name ".md") sommaire-test-directory)))
          (with-temp-buffer
            (insert-file-contents file)
            (sommaire-markdown-test--should-equal-pandoc directory file)))))))

(ert-deftest sommaire-markdown-headings-equal-pandocs-on-its-traps ()
  "On documents that pin each trap of block structure, the headings equal pandoc's.
This test needs pandoc, and each document is its own file for it."
  (sommaire-markdown-test--require-pandoc)
  (let* ((directory (repo-test-tree `(("toc.lua" . ,sommaire-markdown-test--pandoc-filter))))
         (file (expand-file-name "document.md" directory)))
    (dolist (text sommaire-markdown-test--documents)
      (ert-info ((format "%S" text))
        (with-temp-file file (insert text))
        (with-temp-buffer
          (insert text)
          (sommaire-markdown-test--should-equal-pandoc directory file))))))

(ert-deftest sommaire-markdown-headings-without-pandoc ()
  "The usual traps in one document leave only its headings, with or without pandoc."
  (with-temp-buffer
    (insert "# One\n\n```\n# In code\n```\n\n    # In code\n\n<!--\n# In a comment\n-->\n\n"
            "Two\n---\n\n> # Quoted\n\n- # In an item\n\n  # In the item\n\n#### Three ###\n")
    (should (equal (sommaire-markdown-test--headings)
                   '((1 . "One") (2 . "Two") (4 . "Three"))))))

(ert-deftest sommaire-markdown-kind-of-a-line ()
  "Each kind of line, with what must be open before it, from CommonMark's rules."
  (pcase-dolist (`(,line ,open ,kind)
                 '(("" nil blank) ("   " paragraph blank)
                   ("    code" nil code) ("    text" paragraph text) ("    text" lazy text)
                   ("---" paragraph underline) ("===" paragraph underline) ("-" paragraph underline)
                   ("   --- " paragraph underline)
                   ("---" lazy break) ("---" nil break)
                   ("===" lazy text) ("===" nil text)
                   ("# a" nil atx) ("###### a" paragraph atx) ("#" lazy atx) ("   # a" nil atx)
                   ("####### a" nil text) ("#a" nil text)
                   ("```" nil fence) ("~~~ a`b" paragraph fence) ("``` a" lazy fence)
                   ("``` a`" nil text) ("``" nil text)
                   ("<!-- a" nil comment) ("<!-- a" paragraph comment)
                   ("<![CDATA[" nil html-cdata) ("<!doctype html>" nil html-declaration)
                   ("<?php" nil html-instruction) ("<pre>" nil html-raw)
                   ("<SCRIPT src=x>" nil html-raw) ("<prefix>" nil html-tag)
                   ("<div>" nil div) ("</div>" paragraph div) ("<div class=\"a\">  " lazy div)
                   ("<div>text" nil html-block) ("<details>" nil html-block)
                   ("</table>" paragraph html-block) ("<hr/>" nil html-block)
                   ("<span>" nil html-tag) ("</span>" nil html-tag) ("<a b=\"c\">" nil html-tag)
                   ("<span>" paragraph text) ("<span>" lazy html-tag) ("<span>" definition text)
                   ("<a>text</a>" nil text)
                   ("<x@y.invalid>" nil text)
                   ("***" nil break) ("- - -" paragraph break) ("_  _  _" lazy break)
                   ("--" nil text) ("**a**" nil text)
                   ("> a" nil block-quote) (">" paragraph block-quote) (">a" lazy block-quote)
                   ("- a" nil item) ("-" nil item) ("+ a" lazy item) ("1. a" nil item)
                   ("7) a" nil item) ("2. a" lazy item) ("123456789. a" nil item)
                   ("- a" paragraph item) ("1. a" paragraph item) ("01. a" paragraph item)
                   ("2. a" paragraph text) ("1." paragraph text) ("*" paragraph text)
                   ("1234567890. a" nil text) ("-a" nil text) ("1.a" nil text)
                   ("[a]: /url" nil definition) ("[a]: </u r l> \"t\"" nil definition)
                   ("[a]: /url 't'" nil definition) ("[a]: /url (t)" nil definition)
                   ("[a]: /url" paragraph text) ("[a]: /url" definition definition)
                   ("[a]: /url text" nil text) ("[^1]: Note" nil text)
                   ("---" definition break) ("===" definition text) ("- a" definition item)
                   ("-" definition text) ("    a" definition text) ("# a" definition atx)
                   ("Text" nil text) ("Text" paragraph text) ("Text" lazy text)))
    (ert-info ((format "%S with %S open" line open))
      (should (eq (let ((case-fold-search t)) (sommaire-markdown--kind line open)) kind)))))

(ert-deftest sommaire-markdown-parse-atx ()
  "An ATX heading's level, and its text without its closing marks."
  (pcase-dolist (`(,line ,level ,text)
                 '(("# a" 1 " a") ("###### a" 6 " a") ("  ## a" 2 " a")
                   ("# a #" 1 " a") ("# a ###  " 1 " a") ("# a#" 1 " a#") ("# a # b" 1 " a # b")
                   ("#" 1 "") ("## ##" 2 "")))
    (ert-info (line)
      (should (equal (sommaire-markdown--parse-atx line) (cons level text))))))

(ert-deftest sommaire-markdown-closer ()
  "What ends the block that a line opens, and when the line opens none."
  (let ((closer (lambda (kind line) (sommaire-markdown--closer kind line))))
    (ert-info ("a fence ends at the same mark, at least as long, with nothing else")
      (let ((regexp (funcall closer 'fence "````sh")))
        (dolist (line '("````" "   ````  " "`````"))
          (should (string-match-p regexp line)))
        (dolist (line '("```" "~~~~" "    ````" "```` sh" "text"))
          (should-not (string-match-p regexp line))))
      (let ((regexp (funcall closer 'fence "  ~~~ a")))
        (should (string-match-p regexp "~~~"))
        (should-not (string-match-p regexp "```"))))
    (ert-info ("a fence too long for a regexp stays usable")
      (should-not (string-match-p (funcall closer 'fence (make-string 70000 ?`)) "text")))
    (ert-info ("a comment that ends on its line opens nothing")
      (should (null (funcall closer 'comment "<!-- a -->")))
      (should (equal (funcall closer 'comment "<!-- a") "-->")))
    (ert-info ("a block of HTML closed by a blank line")
      (dolist (kind '(div html-block html-tag))
        (should (string-match-p (funcall closer kind "<x>") "   "))
        (should-not (string-match-p (funcall closer kind "<x>") "</x>"))))
    (ert-info ("the others end at their own mark, on their line or later")
      (pcase-dolist (`(,kind ,line ,end)
                     '((html-raw "<pre>" "a</pre>") (html-raw "<style>" "</style> b")
                       (html-instruction "<?a" "b?>") (html-declaration "<!a" "b>")
                       (html-cdata "<![CDATA[" "]]>")))
        (should (string-match-p (funcall closer kind line) end))
        (should (null (funcall closer kind (concat line end))))))
    (ert-info ("other kinds open nothing")
      (dolist (kind '(blank text code atx underline break block-quote item definition))
        (should (null (funcall closer kind "a")))))))

(ert-deftest sommaire-markdown-open-in-container ()
  "A line of a container leaves a paragraph open unless its content is another block."
  (pcase-dolist (`(,line . ,open)
                 '(("> a" . lazy) (">a" . lazy) ("- a" . lazy) ("1. a" . lazy) ("> > a" . lazy)
                   ("> - a" . lazy) ("- [ ] a" . lazy) ("  a" . lazy)
                   (">" . nil) ("-" . nil) ("" . nil) ("   " . nil) ("> # a" . nil) ("- # a" . nil)
                   ("> ```" . nil) ("- ---" . nil) ("> > # a" . nil) ("  # a" . nil)))
    (ert-info (line)
      (should (eq (sommaire-markdown--open-in-container line) open)))))

(ert-deftest sommaire-markdown-item-offset ()
  "The column where a list item's content begins, from CommonMark's rules."
  (pcase-dolist (`(,line . ,offset)
                 '(("- a" . 2) ("-  a" . 3) ("-    a" . 5)
                   ;; Five spaces start indented code, one space after the marker.
                   ("-     a" . 2) ("-        a" . 2)
                   ("  - a" . 4) ("1. a" . 3) ("10) a" . 4) ("   123. a" . 8)))
    (ert-info (line)
      (with-temp-buffer
        (insert line "\nA line after it\n")
        (goto-char (point-min))
        (should (eql (sommaire-markdown--item-offset line) offset)))))
  (ert-info ("an empty item takes its content from the next line, or holds nothing")
    (pcase-dolist (`(,text . ,offset)
                   '(("-\nA line\n" . 2) ("-   \nA line\n" . 2) ("  1.\nA line\n" . 5)
                     ("-\n\nA line\n" . nil) ("-\n   \nA line\n" . nil) ("-" . nil)))
      (with-temp-buffer
        (insert text)
        (goto-char (point-min))
        (should (eql (sommaire-markdown--item-offset
                      (buffer-substring-no-properties (point) (pos-eol)))
                     offset))))))

(ert-deftest sommaire-markdown-untabify ()
  "A tab reaches the next stop of 4 columns."
  (pcase-dolist (`(,line . ,expanded)
                 '(("a" . "a") ("\ta" . "    a") (" \ta" . "    a") ("   \ta" . "    a")
                   ("    \ta" . "        a") ("-\ta" . "-   a") ("a\t\tb" . "a       b")))
    (ert-info (line)
      (should (equal (sommaire-markdown--untabify line) expanded)))))

(ert-deftest sommaire-markdown-yaml-scalar ()
  "The string that a one-line YAML scalar denotes, or nil for anything else."
  (pcase-dolist (`(,text . ,value)
                 '(("Plain" . "Plain") ("Two words" . "Two words") ("Trailing  " . "Trailing")
                   ("With # a comment" . "With") ("Not#a comment" . "Not#a comment")
                   ("\"Quoted\"" . "Quoted") ("\"A: b\"" . "A: b") ("\"Quoted\" # Comment" . "Quoted")
                   ("\"An \\\"inner\\\" one\"" . "An \"inner\" one") ("\"Back\\\\slash\"" . "Back\\slash")
                   ("'Single'" . "Single") ("'It''s'" . "It's") ("'A' # Comment" . "A")
                   ("|" . nil) (">-" . nil) ("[a, b]" . nil) ("{a: b}" . nil) ("&anchor a" . nil)
                   ("*alias" . nil) ("!tag a" . nil) ("# Comment" . nil) ("\"Unclosed" . nil)
                   ("'Unclosed" . nil) ("" . nil)))
    (ert-info (text)
      (should (equal (sommaire-markdown--yaml-scalar text) value)))))

(ert-deftest sommaire-markdown-root ()
  "The root: a lone first H1, or the document with the front matter's title."
  (pcase-dolist (`(,text ,title ,titles)
                 '(("# Lone\n## A\n## B\n" "Lone" ("A" "B"))
                   ("Lone\n====\n\nA\n---\n" "Lone" ("A"))
                   ("# One\n# Two\n" nil ("One" "Two"))
                   ("# One\n## A\n# Two\n" nil ("One" "Two"))
                   ("## A\n# One\n" nil ("A" "One"))
                   ("## A\n## B\n" nil ("A" "B"))
                   ("---\ntitle: Front\n---\n# Lone\n## A\n" "Lone" ("A"))
                   ("---\ntitle: Front\n---\n# One\n# Two\n" "Front" ("One" "Two"))
                   ("---\ntitle: Front\n---\n## A\n" "Front" ("A"))
                   ("---\ntitle: Front\n---\nText\n" "Front" nil)
                   ("---\ntitle: \"A: quoted\"\n---\n" "A: quoted" nil)
                   ("---\ntitle: 'It''s'\n...\n" "It's" nil)
                   ("---\ntitle:\tA tab\n---\n" "A tab" nil)
                   ("---\nother: 1\ntitle: Second\n---\n" "Second" nil)
                   ("---\nauthor: Someone\n---\n" nil nil)
                   ("---\ntitle: |\n  A block\n---\n" nil nil)
                   ("---\nnested:\n  title: Not the document's\n---\n" nil nil)
                   ("---\n# A comment\ntitle: After it\n---\n" "After it" nil)
                   ("---\ntitle: T\n" nil nil)
                   ("---\nJust text\n---\n" nil ("Just text"))
                   ("---\nTitle: Case\n---\n" nil nil)
                   ("---\nsubtitle: Not it\n---\n" nil nil)
                   ("Text\n\n---\ntitle: Not at the start\n---\n" nil ("title: Not at the start"))
                   ("" nil nil)
                   ("Text\n" nil nil)))
    (ert-info (text)
      (let ((root (sommaire-markdown-test--root-of text)))
        (should (equal (plist-get root :title) title))
        (should (equal (sommaire-markdown-test--titles root) titles))))))

(ert-deftest sommaire-markdown-front-matter-holds-no-headings ()
  "Nothing in front matter is a heading, nor an introduction."
  (let ((root (sommaire-markdown-test--root-of "---\ntitle: T\n# Not a heading\n---\n# A\n# B\n")))
    (should (equal (sommaire-markdown-test--titles root) '("A" "B")))
    (should-not (plist-get root :intro))))

(ert-deftest sommaire-markdown-introduction ()
  "What lies between a heading and its first child, by kind of block."
  (pcase-dolist (`(,body . ,intro)
                 '(("" . nil)
                   ("\n\n" . nil)
                   ("<!-- A comment -->\n" . nil)
                   ("<!--\nA comment\n\non lines\n-->\n" . nil)
                   ("[a]: /url\n" . nil)
                   ("[a]: /url \"Title\"\n[b]: /url\n" . nil)
                   ("<div>\n\n" . nil)
                   ("</div>\n\n" . nil)
                   ("<div class=\"a\">\n</div>\n\n" . nil)
                   ("A paragraph.\n\n" . t)
                   ("- An item\n\n" . t)
                   ("1. An item\n\n" . t)
                   ("> A quote\n\n" . t)
                   ("```\ncode\n```\n\n" . t)
                   ("    code\n\n" . t)
                   ("***\n\n" . t)
                   ("<details>\n\n" . t)
                   ("<span>\n\n" . t)
                   ("<div>\nText in the block\n</div>\n\n" . t)
                   ("<!-- A comment -->\n\nA paragraph.\n\n" . t)
                   ("[a]: /url\n\nA paragraph.\n\n" . t)))
    (ert-info (body)
      (should (eq (plist-get (sommaire-markdown-test--first-child
                              (concat "# A\n" body "## B\n\n# C\n"))
                             :intro)
                  intro)))))

(ert-deftest sommaire-markdown-introduction-is-the-last-headings ()
  "Text belongs to the heading above it, and a setext title is no introduction."
  (let* ((root (sommaire-markdown-test--root-of "# A\n## B\nText\n## C\n# D\nText\n"))
         (a (nth 0 (plist-get root :children)))
         (d (nth 1 (plist-get root :children))))
    (should-not (plist-get root :intro))
    (should-not (plist-get a :intro))
    (should (plist-get (nth 0 (plist-get a :children)) :intro))
    (should-not (plist-get (nth 1 (plist-get a :children)) :intro))
    (should (plist-get d :intro)))
  (ert-info ("a setext heading's own lines")
    (let ((root (sommaire-markdown-test--root-of "# A\n\nTitle of\nB\n---\n\n# C\n")))
      (should (equal (sommaire-markdown-test--titles (car (plist-get root :children)))
                     '("Title of B")))
      (should-not (plist-get (car (plist-get root :children)) :intro))))
  (ert-info ("but a paragraph before it stays one")
    (let ((node (sommaire-markdown-test--first-child "# A\n\nText\n\nB\n---\n\n# C\n")))
      (should (plist-get node :intro)))))

(ert-deftest sommaire-markdown-introduction-of-the-root ()
  "The root's span starts where the document starts."
  (pcase-dolist (`(,text . ,intro)
                 '(("# Lone\n\nText\n\n## A\n" . t)
                   ("Text\n\n# Lone\n\n## A\n" . t)
                   ("<!-- A comment -->\n\n# Lone\n\n## A\n" . nil)
                   ("---\ntitle: T\n---\n\n# Lone\n\n## A\n" . nil)
                   ("---\ntitle: T\n---\n\nText\n\n# One\n\n# Two\n" . t)
                   ("# One\n\n# Two\n\nText\n" . nil)))
    (ert-info (text)
      (should (eq (plist-get (sommaire-markdown-test--root-of text) :intro) intro)))))

(ert-deftest sommaire-markdown-explicit-tables ()
  "R2: a table marker makes the root explicit, whichever heading it follows."
  (pcase-dolist (`(,text . ,explicit)
                 '(("<!-- markdown-toc start - Don't edit -->\n<!-- markdown-toc end -->\n# A\n# B\n" . t)
                   ("<!-- markdown-toc start\nspanning lines -->\n# A\n# B\n" . t)
                   ("# A\n# B\n\n<!-- markdown-toc start -->\n" . t)
                   ("# Contents <!-- :TOC: -->\n# B\n" . t)
                   ("# Contents <!-- :TOC_2: -->\n# B\n" . t)
                   ("# Contents <!-- :toc@2@gh: -->\n# B\n" . t)
                   ("# Contents <!-- :TOC:QUOTE: -->\n# B\n" . t)
                   ("<!-- :TOC: -->\n# A\n# B\n" . t)
                   ("# A\n# B\n" . nil)
                   ("<!-- A comment about markdown-toc -->\n# A\n# B\n" . nil)
                   ("# Contents <!-- :TOCK: -->\n# B\n" . nil)
                   ("# Contents :TOC:\n# B\n" . nil)
                   ("```\n<!-- markdown-toc start -->\n```\n# A\n# B\n" . nil)
                   ("    <!-- markdown-toc start -->\n\n# A\n# B\n" . nil)
                   ("- <!-- markdown-toc start -->\n\n# A\n# B\n" . nil)
                   ("<!-- Before\n<!-- markdown-toc start -->\n# A\n# B\n" . nil)))
    (ert-info (text)
      (should (eq (plist-get (sommaire-markdown-test--root-of text) :explicit) explicit))))
  (ert-info ("it stays at the root")
    (let ((root (sommaire-markdown-test--root-of "# A\n## Contents <!-- :TOC: -->\n# C\n")))
      (should (plist-get root :explicit))
      (should-not (plist-get (car (plist-get root :children)) :explicit)))))

(ert-deftest sommaire-markdown-tables-are-no-introduction ()
  "An explicit table is not substantive, and it ends where its marks say."
  (pcase-dolist (`(,body . ,intro)
                 '(;; A markdown-toc table runs to its end marker.
                   ("<!-- markdown-toc start -->\n**Table**\n\n- [A](#a)\n\n<!-- markdown-toc end -->\n" . nil)
                   ("<!-- markdown-toc start -->\n```\ncode\n```\n<!-- markdown-toc end -->\n" . nil)
                   ("<!-- markdown-toc start -->\n<!-- markdown-toc end -->\nAfter it.\n" . t)
                   ("<!-- markdown-toc start -->\n<!-- markdown-toc end -->\n- After it\n" . t)))
    (ert-info (body)
      (should (eq (plist-get (sommaire-markdown-test--first-child
                              (concat "# A\n" body "## B\n\n# C\n"))
                             :intro)
                  intro))))
  (ert-info ("a toc-org table runs to the next heading")
    (let* ((root (sommaire-markdown-test--root-of
                  "# Contents <!-- :TOC: -->\n- [A](#a)\n\nMore of it\n\n# A\nText of A\n"))
           (children (plist-get root :children)))
      (should-not (plist-get (nth 0 children) :intro))
      (should (plist-get (nth 1 children) :intro))))
  (ert-info ("a table with no end marker stops at a heading, too")
    (let* ((root (sommaire-markdown-test--root-of
                  "# A\n<!-- markdown-toc start -->\nTable\n\n# B\nText of B\n"))
           (children (plist-get root :children)))
      (should-not (plist-get (nth 0 children) :intro))
      (should (plist-get (nth 1 children) :intro)))))

(ert-deftest sommaire-markdown-table-marker-leaves-the-title ()
  "A comment on a heading's line is no part of its title."
  (should (equal (sommaire-markdown-test--titles
                  (sommaire-markdown-test--root-of
                   "# Contents   <!-- :TOC: -->\n# Foo <!-- a --> bar <!-- b --> baz\n"))
                 '("Contents" "Foo bar baz"))))

(ert-deftest sommaire-markdown-toc-org-marker-keeps-its-heading ()
  "The rules drop toc-org containers in Org only, and pandoc lists this heading."
  (let ((root (sommaire-markdown-test--root-of "# Contents <!-- :TOC: -->\n- [A](#a)\n\n# A\n")))
    (should (equal (sommaire-markdown-test--titles root) '("Contents" "A")))))

(ert-deftest sommaire-markdown-title-is-bounded ()
  "A heading's title reads a bounded length, so a hostile line costs little."
  (let ((title (plist-get (sommaire-markdown-test--first-child
                           (concat "## " (make-string 5000 ?a) "\n"))
                          :title)))
    (should (string-prefix-p "aaa" title))
    (should (<= (length title) sommaire-markdown--longest-title))
    (should (> (length title) (/ sommaire-markdown--longest-title 2)))))

(ert-deftest sommaire-markdown-narrowing ()
  "R6: a part that starts at a heading with only deeper ones has it as its root."
  (let ((text (concat "---\ntitle: Front\n---\n\nThe document's text.\n\n"
                      "# A\n\nBody of A.\n\n## B\n\n## C\n\n# D\n")))
    (pcase-dolist (`(,from ,to ,title ,intro ,titles)
                   `(("# A" "# D" "A" t ("B" "C"))
                     ("## B" "## C" "B" nil nil)
                     ;; A heading of a level other than 1 does as well.
                     ("## C" "# D" "C" nil nil)
                     ;; Another heading as high as the first one: no heading is the root.
                     ("# A" nil nil nil ("A" "D"))
                     ("## B" "# D" nil nil ("B" "C"))
                     ;; A part that does not start at a heading.
                     ("Body of A" "# D" nil t ("B" "C"))
                     ("The document's" "## B" nil t ("A"))
                     ("\n# A" "## B" nil nil ("A"))
                     ;; The front matter's title does not survive narrowing.
                     ("---" "# A" nil t nil)))
      (ert-info ((format "from %S to %S" from to))
        (let ((root (sommaire-markdown-test--narrowed-root text from to)))
          (should (equal (plist-get root :title) title))
          (should (eq (plist-get root :intro) intro))
          (should (equal (sommaire-markdown-test--titles root) titles))))))
  (ert-info ("a lone H1 in a part is not the rule that applies")
    (let ((root (sommaire-markdown-test--narrowed-root "Text\n\n# A\n\n## B\n" "\n# A" nil)))
      (should-not (plist-get root :title))
      (should (equal (sommaire-markdown-test--titles root) '("A")))))
  (ert-info ("a part's table")
    (let ((root (sommaire-markdown-test--narrowed-root
                 "# A\n<!-- :TOC: -->\n## B\n# D\n" "# A" "# D")))
      (should (equal (plist-get root :title) "A"))
      (should (plist-get root :explicit))))
  (ert-info ("front matter is read only at the buffer's first position")
    (let ((root (sommaire-markdown-test--narrowed-root
                 "Text\n\n---\ntitle: T\n---\n" "---" nil)))
      (should (equal (sommaire-markdown-test--titles root) '("title: T"))))))

(ert-deftest sommaire-markdown-active-heading ()
  "R4: which heading each part of a document belongs to."
  (let ((text (concat "---\ntitle: T\n---\n\nThe document's text.\n\n"
                      "# A\n\nBody of A.\n\n"
                      "Title of\nB\n---\n\nBody of B.\n\n"
                      "```\n# In code\n```\n\n"
                      "### C ###\n\n"
                      "# D\n")))
    (with-temp-buffer
      (insert text)
      (let ((outline (sommaire-markdown-outline)))
        (pcase-dolist (`(,place . ,id)
                       '(("title: T" . 0) ("The document's" . 0)
                         ("# A" . 1) ("Body of A" . 1)
                         ("Title of" . 2) ("\nB\n" . 2) ("---\n\nBody" . 2) ("Body of B" . 2)
                         ("# In code" . 2)
                         ("### C" . 3)
                         ("# D" . 4)))
          (ert-info (place)
            (goto-char (point-min))
            (search-forward place)
            (should (eql (sommaire-rules-active outline (1- (point))) id))))
        (ert-info ("the very end of the buffer")
          (should (eql (sommaire-rules-active outline (point-max)) 4)))))))

(ert-deftest sommaire-markdown-active-heading-with-a-lone-h1 ()
  "R4: all of a document with a lone H1 belongs to it, or to a heading below it."
  (with-temp-buffer
    (insert "Before it\n\n# Lone\n\nText\n\n## A\n\nBody\n\n### B\n\n## C\n")
    (let ((outline (sommaire-markdown-outline)))
      (pcase-dolist (`(,place . ,id)
                     '(("Before" . 0) ("# Lone" . 0) ("Text" . 0)
                       ("## A" . 1) ("Body" . 1) ("### B" . 2) ("## C" . 3)))
        (ert-info (place)
          (goto-char (point-min))
          (search-forward place)
          (should (eql (sommaire-rules-active outline (match-beginning 0)) id)))))))

(ert-deftest sommaire-markdown-places-of-the-heading ()
  "A heading's place starts at its first line and ends with its subtree."
  (with-temp-buffer
    (insert "Text\n\n# A\n\n## B\n\n### C\n\n## D\n\n# E\n")
    (let ((places (plist-get (sommaire-markdown-outline) :places))
          (at (lambda (text)
                (save-excursion (goto-char (point-min)) (search-forward text)
                                (match-beginning 0)))))
      (should (= (length places) 6))
      (should (eql (plist-get (aref places 0) :begin) (point-min)))
      (should (eql (plist-get (aref places 0) :end) (point-max)))
      (should (eql (plist-get (aref places 1) :begin) (funcall at "# A")))
      (should (eql (plist-get (aref places 1) :end) (funcall at "# E")))
      (should (eql (plist-get (aref places 2) :end) (funcall at "## D")))
      (should (eql (plist-get (aref places 3) :end) (funcall at "## D")))
      (should (eql (plist-get (aref places 4) :end) (funcall at "# E")))
      (should (eql (plist-get (aref places 5) :end) (point-max))))))

(ert-deftest sommaire-markdown-first-character-after-the-heading ()
  "R5: a Markdown heading has no metadata, so its body starts at its next text."
  (pcase-dolist (`(,text . ,body)
                 '(("# A\n# B\nText\n" . "# B")
                   ("# A\n\n\nText\n# B\n" . "Text")
                   ("# A\n    Code\n# B\n" . "    Code")
                   ("# A\n  \n\t\nText\n# B\n" . "Text")
                   ("A\n=\n\nText\n# B\n" . "Text")))
    (ert-info (text)
      (with-temp-buffer
        (insert text)
        (goto-char (point-min))
        (search-forward body)
        (should (eql (plist-get (aref (plist-get (sommaire-markdown-outline) :places) 1) :body)
                     (match-beginning 0))))))
  (ert-info ("a heading at the end of the buffer")
    (with-temp-buffer
      (insert "# A\n# B\n")
      (should (eql (plist-get (aref (plist-get (sommaire-markdown-outline) :places) 2) :body)
                   (point-max))))))

(ert-deftest sommaire-markdown-outline-is-cached-per-modification-tick ()
  "The scanner runs once for a given text and narrowing, whatever else happens."
  (with-temp-buffer
    (insert "# A\n# B\n")
    (let ((first (sommaire-markdown-outline)))
      (should (eq (sommaire-markdown-outline) first))
      (ert-info ("fontification changes properties, not the text")
        (put-text-property 1 3 'face 'bold)
        (should (eq (sommaire-markdown-outline) first)))
      (ert-info ("point changes nothing")
        (goto-char 2)
        (should (eq (sommaire-markdown-outline) first)))
      (ert-info ("an edit that keeps the size scans again")
        (goto-char 3)
        (delete-char 1)
        (insert "A")
        (should-not (eq (sommaire-markdown-outline) first)))
      (ert-info ("an edit scans again")
        (goto-char (point-max))
        (insert "# C\n")
        (should (equal (sommaire-markdown-test--headings) '((1 . "A") (1 . "B") (1 . "C")))))
      (ert-info ("narrowing scans again")
        (narrow-to-region 1 5)
        (should (equal (plist-get (plist-get (plist-get (sommaire-markdown-outline) :model)
                                             :root)
                                  :title)
                       "A")))
      (ert-info ("widening does not give the narrowed outline back")
        (widen)
        (should (equal (sommaire-markdown-test--headings) '((1 . "A") (1 . "B") (1 . "C"))))))))

(ert-deftest sommaire-markdown-reader-failure-gives-a-root ()
  "A document that the scanner cannot read gives a root alone, a message, one try."
  (with-temp-buffer
    (insert "# A\n")
    (let ((tries 0) (messages nil))
      (cl-letf (((symbol-function 'sommaire-markdown--step)
                 (lambda (&rest _)
                   (setq tries (1+ tries))
                   (error "Boom")))
                ((symbol-function 'message)
                 (lambda (format-string &rest arguments)
                   (push (apply #'format format-string arguments) messages))))
        (let ((outline (sommaire-markdown-outline)))
          (should (equal (plist-get outline :model)
                         '(:schema 1 :root (:id 0 :title nil :archived nil :intro nil
                                            :explicit nil :children nil))))
          (should (eql (sommaire-rules-active outline (point)) 0))
          (should (eq (sommaire-markdown-outline) outline))
          (should (= tries 1))
          (should (= (length messages) 1))
          (should (string-search "Boom" (car messages))))))))

(ert-deftest sommaire-markdown-very-long-lines ()
  "A very long line costs the document nothing: the other lines still count."
  (dolist (line (list (make-string 1000000 ?\t)
                      (make-string 1000000 ?\s)
                      (make-string 50000 ?-)
                      (make-string 1000000 ?#)
                      (make-string 1000000 ?a)
                      (concat "- " (make-string 1000000 ?a))
                      (concat "[a]: data:image/png;base64," (make-string 1000000 ?a))
                      (concat "![a](data:image/png;base64," (make-string 1000000 ?a) ")")
                      (concat "<div " (make-string 1000000 ?a) ">")))
    (ert-info ((substring line 0 8))
      (with-temp-buffer
        (insert "## A\n\n" line "\n\n## B\n")
        (should (equal (sommaire-markdown-test--headings) '((2 . "A") (2 . "B")))))))
  (ert-info ("a fence too long for a regexp to count still opens")
    (with-temp-buffer
      (insert "## A\n\n" (make-string 70000 ?`) "\n\n## In code\n")
      (should (equal (sommaire-markdown-test--headings) '((2 . "A")))))))

(ert-deftest sommaire-markdown-line-too-long-for-the-matcher ()
  "A line that exhausts the regexp matcher's stack leaves a root and a message.
Hundreds of thousands of repeated marks are what it takes, and no real
document has them, so the outline gives up rather than guess at the rest."
  (dolist (line (list (make-string 1000000 ?-)
                      (mapconcat #'identity (make-list 500000 "-") " ")
                      (mapconcat #'identity (make-list 300000 ">") " ")))
    (ert-info ((substring line 0 8))
      (let ((messages nil))
        (cl-letf (((symbol-function 'message)
                   (lambda (&rest arguments) (push arguments messages))))
          (with-temp-buffer
            (insert "## A\n\n" line "\n\n## B\n")
            (should (null (plist-get (plist-get (plist-get (sommaire-markdown-outline) :model)
                                                :root)
                                     :children)))))
        (should (= (length messages) 1))))))

(ert-deftest sommaire-markdown-ignores-the-major-mode ()
  "The outline reads only the text, so it cannot depend on a mode's settings."
  (let ((text "---\ntitle: T\n---\n<DIV>\n# Raw\n\n\t# Code\n\n# A\n\n- Item\n\n  # In it\n"))
    (let ((expected (with-temp-buffer
                      (insert text)
                      (plist-get (sommaire-markdown-outline) :model))))
      (should (equal (plist-get (plist-get expected :root) :title) "A"))
      (should (null (plist-get (plist-get expected :root) :children)))
      (with-temp-buffer
        (insert text)
        (setq-local case-fold-search nil
                    tab-width 2
                    inhibit-field-text-motion nil)
        (set-syntax-table (make-syntax-table))
        (modify-syntax-entry ?# "<")
        (modify-syntax-entry ?\n ">")
        (put-text-property (point-min) (point-max) 'invisible t)
        (put-text-property (point-min) (point-max) 'field 'x)
        (should (equal (plist-get (sommaire-markdown-outline) :model) expected))))))

(ert-deftest sommaire-markdown-leaves-point-and-match-data ()
  "Reading the outline moves nothing that its caller may be using."
  (with-temp-buffer
    (insert "# A\nText\n# B\n")
    (goto-char 6)
    (string-match "b" "abc")
    (let ((match (match-data)))
      (sommaire-markdown-outline)
      (should (= (point) 6))
      (should (equal (match-data) match)))))

(ert-deftest sommaire-markdown-load-needs-no-mode ()
  "Loading the scanner prints nothing, and loads no Markdown mode and no sommaire."
  (should (equal (repo-test-emacs
                  (list "-L" (expand-file-name "sommaire" repo-test-root)
                        "-l" "sommaire-markdown"
                        "--eval"
                        (concat "(prin1 (seq-filter #'featurep"
                                " '(markdown-mode markdown-ts-mode org sommaire imprimeur)))")))
                 '(0 . "nil"))))

(ert-deftest sommaire-markdown-load-changes-no-global-state ()
  "Requiring the scanner adds no timer, hook or key."
  (should (equal (repo-test-load-effects 'sommaire-markdown)
                 '(:timers 0 :hooks nil :global-map nil :minor-modes nil
                   :auto-modes nil :sommaire nil :imprimeur nil))))

;;; sommaire-markdown-test.el ends here
