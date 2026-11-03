;;; sommaire-rules-test.el --- The rules against their fixtures  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: docs/minitoc-rules.md.  For every fixture in
;; tests/fixtures/minitoc, written by hand from that file, the rules applied
;; to NAME.model.json give NAME.expected.json, and for its table of scopes
;; NAME.panel.json (plan 005, acceptance 7).  The fixtures are read with
;; json.el.

;;; Code:

(require 'ert)
(require 'json)
(require 'seq)
(require 'repo-test-helpers)
(require 'sommaire-rules)
(require 'sommaire-test-helpers)

(defun sommaire-rules-test--read-strict (name part)
  "Return PART of the fixture NAME, with false, null and arrays told apart."
  (let ((json-object-type 'plist) (json-array-type 'vector)
        (json-false :false) (json-null :null))
    (json-read-file (expand-file-name (format "%s.%s.json" name part)
                                      sommaire-test-directory))))

(defun sommaire-rules-test--keys (object)
  "Return the keys of the plist OBJECT, in order."
  (let (keys)
    (while object
      (push (pop object) keys)
      (pop object))
    (nreverse keys)))

(defun sommaire-rules-test--check-node (node id)
  "Check NODE against tree schema 1, given ID, the number preorder gives it.
Return the id that follows the last node of its subtree."
  (should (equal (sommaire-rules-test--keys node)
                 '(:id :title :archived :intro :explicit :children)))
  (should (eql (plist-get node :id) id))
  (should (or (stringp (plist-get node :title))
              (and (eql id 0) (eq (plist-get node :title) :null))))
  (dolist (flag '(:archived :intro :explicit))
    (should (memq (plist-get node flag) '(t :false))))
  (should (vectorp (plist-get node :children)))
  (when (eq (plist-get node :archived) t)
    (should (equal (mapcar (lambda (key) (plist-get node key)) '(:intro :explicit :children))
                   '(:false :false [])))
    (should-not (eql id 0)))
  (seq-reduce (lambda (next child) (sommaire-rules-test--check-node child next))
              (plist-get node :children)
              (1+ id)))

(defun sommaire-rules-test--check-entry (entry)
  "Check ENTRY against the decision schema."
  (should (equal (sommaire-rules-test--keys entry) '(:id :title :archived :children)))
  (should (natnump (plist-get entry :id)))
  (should (stringp (plist-get entry :title)))
  (should (memq (plist-get entry :archived) '(t :false)))
  (should (vectorp (plist-get entry :children)))
  (seq-do #'sommaire-rules-test--check-entry (plist-get entry :children)))

(defun sommaire-rules-test--check-reference (reference)
  "Check REFERENCE against the decision schema."
  (should (equal (sommaire-rules-test--keys reference) '(:id :title)))
  (should (natnump (plist-get reference :id)))
  (should (or (stringp (plist-get reference :title))
              (eq (plist-get reference :title) :null))))

(ert-deftest sommaire-rules-fixtures-are-the-listed-ones ()
  "The directory holds the listed fixtures, each with all its files."
  (should (equal (directory-files sommaire-test-directory nil "\\`[^.]")
                 (sort (mapcan (lambda (fixture)
                                 (mapcar (lambda (suffix) (concat (car fixture) "." suffix))
                                         (append '("expected.json" "model.json" "panel.json") (cdr fixture))))
                               sommaire-test-fixtures)
                       #'string<))))

(ert-deftest sommaire-rules-fixtures-follow-the-schemas ()
  "Every fixture has the shapes of the rules file, and one local minitoc per node."
  (dolist (fixture sommaire-test-fixtures)
    (ert-info ((car fixture))
      (let* ((model (sommaire-rules-test--read-strict (car fixture) "model"))
             (expected (sommaire-rules-test--read-strict (car fixture) "expected"))
             (nodes (sommaire-rules-test--check-node (plist-get model :root) 0)))
        (should (equal (sommaire-rules-test--keys model) '(:schema :root)))
        (should (eql (plist-get model :schema) 1))
        (should (equal (sommaire-rules-test--keys expected) '(:schema :minitocs :locals)))
        (should (eql (plist-get expected :schema) 1))
        (seq-do (lambda (minitoc)
                  (should (equal (sommaire-rules-test--keys minitoc) '(:anchor :entries)))
                  (should (natnump (plist-get minitoc :anchor)))
                  (seq-do #'sommaire-rules-test--check-entry (plist-get minitoc :entries)))
                (plist-get expected :minitocs))
        (seq-do (lambda (local)
                  (should (equal (sommaire-rules-test--keys local)
                                 '(:active :section :current :entries :path)))
                  (should (natnump (plist-get local :active)))
                  (unless (eq (plist-get local :section) :null)
                    (sommaire-rules-test--check-reference (plist-get local :section)))
                  (should (or (natnump (plist-get local :current))
                              (eq (plist-get local :current) :null)))
                  (should (vectorp (plist-get local :entries)))
                  (seq-do #'sommaire-rules-test--check-entry (plist-get local :entries))
                  (should (vectorp (plist-get local :path)))
                  (seq-do #'sommaire-rules-test--check-reference (plist-get local :path)))
                (plist-get expected :locals))
        (should (equal (seq-map (lambda (local) (plist-get local :active))
                                (plist-get expected :locals))
                       (number-sequence 0 (1- nodes))))))))

(ert-deftest sommaire-rules-minitocs-give-the-expected ()
  "For every fixture, the rules give the expected inline minitocs."
  (dolist (fixture sommaire-test-fixtures)
    (ert-info ((car fixture))
      (should (equal (sommaire-rules-minitocs
                      (sommaire-test-read (car fixture) "model"))
                     (plist-get (sommaire-test-read (car fixture) "expected")
                                :minitocs))))))

(ert-deftest sommaire-rules-local-gives-the-expected ()
  "For every fixture and every active heading, the rules give the expected local minitoc."
  (dolist (fixture sommaire-test-fixtures)
    (let ((model (sommaire-test-read (car fixture) "model")))
      (dolist (local (plist-get (sommaire-test-read (car fixture) "expected")
                                :locals))
        (ert-info ((format "%s, heading %d" (car fixture) (plist-get local :active)))
          (should (equal (sommaire-rules-local model (plist-get local :active))
                         local)))))))

;; The scope.  The tests below walk the model by themselves, so that they
;; judge the panel by what "The scope" says and not by the fixtures alone.

(defun sommaire-rules-test--scope-of (row)
  "Return the root and the depth of ROW of a table of scopes, as the rules take them."
  (list (intern (plist-get row :root))
        (let ((depth (plist-get row :depth)))
          (if (equal depth "all") 'all depth))))

(defun sommaire-rules-test--nodes (node depth)
  "Return pairs (DEPTH . ID) for NODE, which lies at DEPTH, and all below it."
  (cons (cons depth (plist-get node :id))
        (mapcan (lambda (child) (sommaire-rules-test--nodes child (1+ depth)))
                (plist-get node :children))))

(defun sommaire-rules-test--rows (panel)
  "Return pairs (DEPTH . ID) for the rows of PANEL."
  (mapcar (lambda (row) (cons (plist-get row :depth) (plist-get row :id)))
          (plist-get panel :entries)))

(defun sommaire-rules-test--panels (function)
  "Call FUNCTION with the model of each fixture and each of its ids."
  (dolist (fixture sommaire-test-fixtures)
    (let ((model (sommaire-test-read (car fixture) "model")))
      (dolist (node (sommaire-rules-test--nodes (plist-get model :root) 0))
        (ert-info ((format "%s, heading %d" (car fixture) (cdr node)))
          (funcall function model (cdr node)))))))

(ert-deftest sommaire-rules-scopes-follow-the-schema ()
  "Every table of scopes has the shapes of the rules file, and each is one to pin."
  (dolist (fixture sommaire-test-fixtures)
    (ert-info ((car fixture))
      (let ((table (sommaire-rules-test--read-strict (car fixture) "panel")))
        (should (equal (sommaire-rules-test--keys table) '(:schema :scopes)))
        (should (eql (plist-get table :schema) 1))
        (should (> (length (plist-get table :scopes)) 0))
        (seq-do (lambda (row)
                  (should (equal (sommaire-rules-test--keys row) '(:active :root :depth :panel)))
                  (should (member (plist-get row :root) '("document" "section")))
                  (should (or (equal (plist-get row :depth) "all")
                              (natnump (plist-get row :depth))))
                  (let ((panel (plist-get row :panel)))
                    (should (equal (sommaire-rules-test--keys panel) '(:root :current :entries)))
                    (unless (eq (plist-get panel :root) :null)
                      (sommaire-rules-test--check-reference (plist-get panel :root)))
                    (seq-do (lambda (entry)
                              (should (equal (sommaire-rules-test--keys entry)
                                             '(:id :title :archived :depth)))
                              (should (stringp (plist-get entry :title)))
                              (should (memq (plist-get entry :archived) '(t :false)))
                              (should (natnump (plist-get entry :depth))))
                            (plist-get panel :entries))))
                (plist-get table :scopes))))))

(ert-deftest sommaire-rules-panel-gives-the-table ()
  "For every fixture and every scope of its table, the rules give its panel."
  (dolist (fixture sommaire-test-fixtures)
    (let ((model (sommaire-test-read (car fixture) "model")))
      (dolist (row (plist-get (sommaire-test-read (car fixture) "panel") :scopes))
        (ert-info ((format "%s: %S" (car fixture) row))
          (should (equal (apply #'sommaire-rules-panel model (plist-get row :active)
                                (sommaire-rules-test--scope-of row))
                         (plist-get row :panel))))))))

(ert-deftest sommaire-rules-panel-document-lists-its-levels-only ()
  "A document scope lists every heading of those levels of the tree, and no other."
  (sommaire-rules-test--panels
   (lambda (model active)
     (let ((all (cdr (sommaire-rules-test--nodes (plist-get model :root) 0))))
       (dolist (depth '(1 2 3))
         (should (equal (sommaire-rules-test--rows
                         (sommaire-rules-panel model active 'document depth))
                        (seq-filter (lambda (node) (<= (car node) depth)) all))))
       (should (equal (sommaire-rules-test--rows
                       (sommaire-rules-panel model active 'document 'all))
                      all))))))

(ert-deftest sommaire-rules-panel-section-lists-the-section-of-r4 ()
  "A section scope hangs from the section of the local minitoc, whatever the depth."
  (sommaire-rules-test--panels
   (lambda (model active)
     (let* ((local (sommaire-rules-local model active))
            (section (plist-get local :section))
            (node (seq-find (lambda (candidate)
                              (eql (plist-get candidate :id) (plist-get section :id)))
                            (let ((pending (list (plist-get model :root))) (seen nil))
                              (while pending
                                (let ((next (pop pending)))
                                  (push next seen)
                                  (setq pending (append (plist-get next :children) pending))))
                              seen))))
       (dolist (depth '(1 2 all))
         (let ((panel (sommaire-rules-panel model active 'section depth)))
           (should (equal (plist-get panel :root) section))
           (should (equal (sommaire-rules-test--rows panel)
                          (and section
                               (seq-filter
                                (lambda (row) (or (eq depth 'all) (<= (car row) depth)))
                                (cdr (sommaire-rules-test--nodes node 0))))))))
       ;; At depth 1 the current entry is the current entry of R4.
       (should (equal (plist-get (sommaire-rules-panel model active 'section 1) :current)
                      (plist-get local :current)))))))

(ert-deftest sommaire-rules-panel-current-is-the-deepest-listed-on-the-way ()
  "The current entry holds the active heading, and nothing listed deeper does."
  (sommaire-rules-test--panels
   (lambda (model active)
     (let* ((path (mapcar (lambda (reference) (plist-get reference :id))
                          (plist-get (sommaire-rules-local model active) :path))))
       (dolist (scope '((document . 1) (document . 2) (document . all)
                        (section . 1) (section . 2) (section . all)))
         (let* ((panel (sommaire-rules-panel model active (car scope) (cdr scope)))
                (on-the-way (seq-filter (lambda (row) (memql (cdr row) path))
                                        (sommaire-rules-test--rows panel))))
           (should (eql (plist-get panel :current) (cdr (car (last on-the-way)))))))))))

(ert-deftest sommaire-rules-panel-never-expands-an-archived-heading ()
  "Every archived heading is listed, and nothing is listed under it."
  (let ((model (sommaire-test-read "archive" "model")))
    (dolist (scope '((document . 2) (document . all)))
      (let* ((rows (plist-get (sommaire-rules-panel model 0 (car scope) (cdr scope)) :entries))
             (archived (seq-filter (lambda (row) (plist-get row :archived)) rows)))
        (should (equal (mapcar (lambda (row) (plist-get row :title)) archived)
                       '("Old skins" "Attic" "Old one" "Old two" "Old three")))
        (dolist (row archived)
          (let ((next (cadr (memq row rows))))
            (should (or (null next) (<= (plist-get next :depth) (plist-get row :depth))))))))))

(ert-deftest sommaire-rules-panel-refuses-what-is-no-scope ()
  "A root, a depth or an id outside the rules is the caller's error."
  (let ((model (sommaire-test-read "normal" "model")))
    (dolist (root '(nil other "document"))
      (should-error (sommaire-rules-panel model 0 root 1)))
    (dolist (depth '(0 -1 nil 1.5 "all" other))
      (should-error (sommaire-rules-panel model 0 'document depth))
      (should-error (sommaire-rules-panel model 0 'section depth)))
    (should-error (sommaire-rules-panel model 17 'document 1))
    (should-error (sommaire-rules-panel model -1 'section 1))))

(ert-deftest sommaire-rules-panel-survives-a-very-deep-document ()
  "A document chooses its depth, which must not exhaust the Lisp stack."
  (let ((node (list :id 5000 :title "Deep" :archived nil :intro nil :explicit nil
                    :children nil)))
    (dotimes (index 5000)
      (setq node (list :id (- 4999 index) :title "Deep" :archived nil :intro nil
                       :explicit nil :children (list node))))
    (let ((panel (sommaire-rules-panel (list :schema 1 :root node) 5000 'document 'all)))
      (should (= (length (plist-get panel :entries)) 5000))
      (should (eql (plist-get panel :current) 5000))
      (should (eql (plist-get (car (last (plist-get panel :entries))) :depth) 5000)))))

(ert-deftest sommaire-rules-chain-shows-only-paths ()
  "A chain of single children has no inline minitoc, no button and no section."
  (let ((model (sommaire-test-read "chain" "model")))
    (should (null (sommaire-rules-minitocs model)))
    (dolist (active '(0 1 2 3 4))
      (let ((local (sommaire-rules-local model active)))
        (should (null (plist-get local :section)))
        (should (null (plist-get local :current)))
        (should (null (plist-get local :entries)))))
    (should (equal (mapcar (lambda (reference) (plist-get reference :title))
                           (plist-get (sommaire-rules-local model 4) :path))
                   '("Subtitle" "Section" "Subsection" "Paragraph")))))

(ert-deftest sommaire-rules-local-refuses-an-unknown-heading ()
  "An active id that is not in the model is the caller's error."
  (let ((model (sommaire-test-read "chain" "model")))
    (should-error (sommaire-rules-local model 5))
    (should-error (sommaire-rules-local model -1))))

(ert-deftest sommaire-rules-leave-the-model-alone ()
  "The rules change nothing in a model, which an adapter may keep in a cache."
  (dolist (fixture sommaire-test-fixtures)
    (ert-info ((car fixture))
      (let* ((model (sommaire-test-read (car fixture) "model"))
             (copy (copy-tree model)))
        (sommaire-rules-minitocs model)
        (dolist (local (plist-get (sommaire-test-read (car fixture) "expected")
                                  :locals))
          (sommaire-rules-local model (plist-get local :active))
          (sommaire-rules-panel model (plist-get local :active) 'document 'all)
          (sommaire-rules-panel model (plist-get local :active) 'section 1))
        (should (equal model copy))))))

(ert-deftest sommaire-rules-survive-a-very-deep-document ()
  "A document chooses its depth, which must not exhaust the Lisp stack."
  (let ((node (list :id 5000 :title "Deep" :archived nil :intro nil :explicit nil
                    :children nil)))
    (dotimes (index 5000)
      (setq node (list :id (- 4999 index) :title "Deep" :archived nil :intro nil
                       :explicit nil :children (list node))))
    (let* ((model (list :schema 1 :root node))
           (local (sommaire-rules-local model 5000)))
      (should (null (sommaire-rules-minitocs model)))
      (should (null (plist-get local :section)))
      (should (= (length (plist-get local :path)) 5000)))))

(ert-deftest sommaire-rules-constants-match-the-authority ()
  "The constants equal the table of docs/minitoc-rules.md."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "docs/minitoc-rules.md" repo-test-root))
    (pcase-dolist (`(,name . ,value)
                   `(("min_children" . ,sommaire-rules-min-children)
                     ("max_depth" . ,sommaire-rules-max-depth)
                     ("root_levels" . ,sommaire-rules-root-levels)
                     ("section_levels" . ,sommaire-rules-section-levels)))
      (goto-char (point-min))
      (should (re-search-forward (format "^| `%s` | %d |" name value) nil t)))))

(ert-deftest sommaire-rules-read-the-depth-constant ()
  "R1 reads the constant that the table pins, rather than a number of its own.
In `chain-siblings' with a limit of 1, Section lies too deep: it is not worth
a minitoc, so it is no section and is not merged into the block of Subtitle."
  (let ((model (sommaire-test-read "chain-siblings" "model"))
        (sommaire-rules-max-depth 1))
    (should (equal (plist-get (sommaire-rules-local model 2) :section)
                   '(:id 1 :title "Subtitle")))
    (should (equal (sommaire-rules-minitocs model)
                   '((:anchor 1 :entries ((:id 2 :title "Section" :archived nil :children nil)
                                          (:id 6 :title "Section 2" :archived nil
                                           :children nil))))))))

(ert-deftest sommaire-rules-outline-nests-by-level ()
  "A heading's parent is the nearest preceding heading of a lower level, or the root."
  (let* ((heading (lambda (level title)
                    (list :level level :title title :begin 0 :body 0 :end 0)))
         (root (list :title "Root" :begin 0 :body 0 :end 0))
         (outline (sommaire-rules-outline
                   root
                   (list (funcall heading 3 "Before any first level")
                         (funcall heading 1 "Alpha")
                         (funcall heading 4 "Skipped")
                         (funcall heading 2 "Back up")
                         (funcall heading 3 "Under back up")
                         (funcall heading 1 "Omega"))))
         (node (lambda (id title &rest children)
                 (list :id id :title title :archived nil :intro nil :explicit nil
                       :children children))))
    (should (equal (plist-get outline :model)
                   (list :schema 1
                         :root (funcall node 0 "Root"
                                        (funcall node 1 "Before any first level")
                                        (funcall node 2 "Alpha"
                                                 (funcall node 3 "Skipped")
                                                 (funcall node 4 "Back up"
                                                          (funcall node 5 "Under back up")))
                                        (funcall node 6 "Omega")))))))

(ert-deftest sommaire-rules-outline-keeps-flags-and-places ()
  "Any true value is t in the model, and PLACES holds each heading under its id."
  (let* ((root (list :title nil :explicit 'yes :begin 1 :body 2 :end 9))
         (child (list :level 1 :title "A" :archived '("ARCHIVE") :intro 42 :begin 3 :body 4 :end 9))
         (outline (sommaire-rules-outline root (list child))))
    (should (equal (plist-get outline :model)
                   '(:schema 1
                     :root (:id 0 :title nil :archived nil :intro nil :explicit t
                            :children ((:id 1 :title "A" :archived t :intro t :explicit nil
                                        :children nil))))))
    (should (equal (plist-get outline :places) (vector root child)))))

(ert-deftest sommaire-rules-outline-survives-a-very-deep-document ()
  "A document chooses its depth, which must not exhaust the Lisp stack."
  (let* ((headings (mapcar (lambda (level)
                             (list :level level :title "Deep" :begin 0 :body 0 :end 0))
                           (number-sequence 1 5000)))
         (model (plist-get (sommaire-rules-outline (list :begin 0 :body 0 :end 0) headings)
                           :model))
         (node (plist-get model :root))
         (depth 0))
    (while (plist-get node :children)
      (setq node (car (plist-get node :children))
            depth (1+ depth)))
    (should (= depth 5000))))

(ert-deftest sommaire-rules-outline-keeps-the-order-of-many-siblings ()
  "Whatever their number, siblings stay in document order, under the right parent."
  (let* ((titles (mapcar #'number-to-string (number-sequence 1 2000)))
         (headings (cons (list :level 1 :title "Parent" :begin 0 :body 0 :end 0)
                         (mapcar (lambda (title)
                                   (list :level 2 :title title :begin 0 :body 0 :end 0))
                                 titles)))
         (model (plist-get (sommaire-rules-outline (list :begin 0 :body 0 :end 0) headings)
                           :model))
         (top (plist-get (plist-get model :root) :children)))
    (should (= (length top) 1))
    (should (equal (mapcar (lambda (child) (plist-get child :title))
                           (plist-get (car top) :children))
                   titles))))

(ert-deftest sommaire-rules-outline-work-is-linear ()
  "A document chooses its width, so a heading must not cost the length of its siblings.
Twice the headings, of any shape, walk at most about twice the elements."
  (pcase-dolist (`(,name . ,levels)
                 '(("siblings" 1) ("one parent" 2) ("a cycle of levels" 1 2 3 4 5 6)))
    (ert-info (name)
      (let ((walked (lambda (count)
                      (let ((headings (cons (list :level 1 :title "A" :begin 0 :body 0 :end 0)
                                            (mapcar (lambda (index)
                                                      (list :level (nth (% index (length levels)) levels)
                                                            :title "A" :begin 0 :body 0 :end 0))
                                                    (number-sequence 1 count)))))
                        (sommaire-test-walked
                         (lambda ()
                           (sommaire-rules-outline (list :begin 0 :body 0 :end 0) headings)))))))
        (should (<= (funcall walked 2000) (* 2.2 (funcall walked 1000))))))))

(ert-deftest sommaire-rules-active-follows-rule-r4 ()
  "The active heading is the innermost one that holds the position.
The document spans 1 to 100: a heading A at 10 up to 50 with a child B at
20 up to 30, a gap from 30 to 50 such as a dropped subtree leaves, and a
heading C at 50 up to the end."
  (let ((outline (sommaire-rules-outline
                  (list :begin 1 :body 1 :end 100)
                  (list (list :level 1 :title "A" :begin 10 :body 11 :end 50)
                        (list :level 2 :title "B" :begin 20 :body 21 :end 30)
                        (list :level 1 :title "C" :begin 50 :body 51 :end 100)))))
    (pcase-dolist (`(,position . ,id)
                   '((1 . 0) (9 . 0)    ; before the first heading
                     (10 . 1) (19 . 1)  ; a heading's line and its body
                     (20 . 2) (29 . 2)  ; the innermost heading
                     (30 . 1) (49 . 1)  ; the parent, past its child's subtree
                     (50 . 3) (99 . 3)
                     (100 . 3)))        ; the very end of the document
      (ert-info ((format "position %d" position))
        (should (eql (sommaire-rules-active outline position) id))))
    (should-error (sommaire-rules-active outline 0))
    (should-error (sommaire-rules-active outline 101))))

(ert-deftest sommaire-rules-load-changes-no-global-state ()
  "Requiring the rules adds no timer, hook or key, and loads neither package."
  (should (equal (repo-test-load-effects 'sommaire-rules)
                 '(:timers 0 :hooks nil :global-map nil :minor-modes nil
                   :auto-modes nil :sommaire nil :imprimeur nil))))

(ert-deftest sommaire-rules-load-needs-no-parser ()
  "Loading the rules prints nothing, and loads neither Org nor Markdown nor JSON."
  (should (equal (repo-test-emacs
                  (list "-L" (expand-file-name "sommaire" repo-test-root)
                        "-l" "sommaire-rules"
                        "--eval"
                        "(prin1 (seq-filter #'featurep '(org org-element markdown-mode json)))"))
                 '(0 . "nil"))))

;;; sommaire-rules-test.el ends here
