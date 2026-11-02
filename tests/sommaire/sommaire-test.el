;;; sommaire-test.el --- The surfaces of sommaire  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: plan 005, acceptance 3 to 5, and "For step 5" in its notes: what `sommaire-mode' draws from the decisions of
;; docs/minitoc-rules.md.  The expectations come from those rules and that
;; plan, on the fixtures written by hand from them.
;;
;; `format-mode-line' returns "" in batch, so a header line is compared as
;; structure and through `sommaire-test-header', which renders the constructs
;; that a header line can hold.  The tests that make up acceptance 6 run again
;; in a child Emacs: their names start with sommaire-acceptance-.

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'cl-lib)
(require 'org)
(require 'seq)
(require 'repo-test-helpers)
(require 'sommaire)
(require 'sommaire-test-helpers)

(defvar sommaire-test--bread "BREAD"
  "A variable to put in a header line.")

(defun sommaire-test--render (construct)
  "Return the text of the mode line CONSTRUCT, as redisplay would show it.
Signal an error on a percent sign that is not escaped, which redisplay would
take for a command."
  (pcase construct
    ('nil "")
    ((pred stringp)
     (should-not (string-search "%" (replace-regexp-in-string "%%" "" construct t t)))
     (replace-regexp-in-string "%%" "%" construct t t))
    ((pred symbolp) (sommaire-test--render (symbol-value construct)))
    (`(:eval ,form) (sommaire-test--render (eval form t)))
    ((pred consp) (mapconcat #'sommaire-test--render construct ""))
    (_ (error "Not a construct that this renders: %S" construct))))

(defun sommaire-test-header ()
  "Return the text of this buffer's header line, in the selected Emacs window."
  (sommaire-test--render header-line-format))

(defun sommaire-test--heading (title)
  "Move point to the start of the heading called TITLE, in Org or in Markdown."
  (goto-char (point-min))
  (re-search-forward (format "^[*#]+ \\(?:TODO \\[#A\\] \\)?%s\\b" (regexp-quote title)))
  (goto-char (pos-bol)))

(defmacro sommaire-test-with-buffer (setup &rest body)
  "Run BODY with `sommaire-mode' on in a buffer that SETUP fills.
SETUP is a form that runs in the new buffer, with no mode on yet.  The
buffer shows in the selected Emacs window, whose layout comes back after."
  (declare (indent 1) (debug t))
  `(let ((sommaire-test--buffer (generate-new-buffer "sommaire-test")))
     (save-window-excursion
       (unwind-protect
           (with-current-buffer sommaire-test--buffer
             (set-window-buffer nil sommaire-test--buffer)
             ,setup
             (sommaire-mode 1)
             ,@body)
         (kill-buffer sommaire-test--buffer)))))

(defmacro sommaire-test-with-fixture (name extension &rest body)
  "Run BODY as `sommaire-test-with-buffer' does, on the fixture NAME with EXTENSION."
  (declare (indent 2) (debug t))
  `(sommaire-test-with-buffer
       (progn
         (sommaire-test-insert ,name ,extension)
         (when (equal ,extension "org")
           (org-mode)))
     ,@body))

(defmacro sommaire-test-with-org (text &rest body)
  "Run BODY as `sommaire-test-with-buffer' does, in an Org buffer holding TEXT."
  (declare (indent 1) (debug t))
  `(sommaire-test-with-buffer
       (progn
         (insert ,text)
         (org-mode)
         (goto-char (point-min)))
     ,@body))

(defun sommaire-test--local (name active)
  "Return the hand-written local minitoc of the fixture NAME for the id ACTIVE."
  (seq-find (lambda (local) (eql (plist-get local :active) active))
            (plist-get (sommaire-test-read name "expected") :locals)))

;;; The pure segment

(ert-deftest sommaire-segment-names-the-section-and-its-current-entry ()
  "The segment names the section, its number of entries and the current one."
  (let ((segment (sommaire-segment (sommaire-test--local "normal" 3) nil)))
    (should (equal segment "§ Requirements ▾2 › Emacs"))
    (should (eq (get-text-property (string-search "Emacs" segment) 'face segment)
                'sommaire-current))
    (should-not (get-text-property 0 'face segment))))

(ert-deftest sommaire-segment-has-no-current-entry-on-the-section-itself ()
  "With point on the section itself there is no current entry to name."
  (should (equal (sommaire-segment (sommaire-test--local "normal" 2) nil)
                 "§ Requirements ▾2")))

(ert-deftest sommaire-segment-shows-the-path-when-asked ()
  "With WITH-PATH, the segment is the heading path, the section in its place."
  (should (equal (sommaire-segment (sommaire-test--local "normal" 3) t)
                 "Installation › § Requirements ▾2 › Emacs"))
  (let ((segment (sommaire-segment (sommaire-test--local "normal" 4) t)))
    (should (equal segment "Installation › § Requirements ▾2 › Emacs › Native compilation"))
    (should (eq (get-text-property (string-search "Emacs" segment) 'face segment)
                'sommaire-current))
    (should-not (get-text-property (string-search "Native" segment) 'face segment))))

(ert-deftest sommaire-segment-puts-the-root-first ()
  "The root is in no path, so a root that is the section comes first."
  (should (equal (sommaire-segment (sommaire-test--local "chain-siblings" 7) nil)
                 "§ Title ▾2 › Subtitle 2"))
  (should (equal (sommaire-segment (sommaire-test--local "chain-siblings" 7) t)
                 "§ Title ▾2 › Subtitle 2"))
  (should (equal (sommaire-segment (sommaire-test--local "normal" 0) t)
                 "§ A normal document ▾2")))

(ert-deftest sommaire-segment-without-a-section ()
  "With no section only the path shows: rule R4."
  (should (equal (sommaire-segment (sommaire-test--local "chain" 4) nil) ""))
  (should (equal (sommaire-segment (sommaire-test--local "chain" 4) t)
                 "Subtitle › Section › Subsection › Paragraph"))
  (should (equal (sommaire-segment (sommaire-test--local "chain" 0) t) ""))
  (should (equal (sommaire-segment (sommaire-test--local "empty" 0) t) "")))

(ert-deftest sommaire-segment-of-a-root-without-a-title ()
  "A root with no title is a section all the same."
  (should (equal (sommaire-segment (sommaire-test--local "untitled" 0) nil) "§ ▾2")))

(ert-deftest sommaire-segment-escapes-percent-signs ()
  "Every percent sign of a title reaches the header line escaped."
  (let ((local (list :active 2
                     :section '(:id 1 :title "100%-done")
                     :current 2
                     :entries '((:id 2 :title "50%d" :archived nil :children nil)
                                (:id 3 :title "Other" :archived nil :children nil))
                     :path '((:id 1 :title "100%-done") (:id 2 :title "50%d")))))
    (should (equal (sommaire-segment local nil) "§ 100%%-done ▾2 › 50%%d"))
    (should (equal (sommaire-test--render (sommaire-segment local nil))
                   "§ 100%-done ▾2 › 50%d"))
    (should (equal (sommaire-test--render
                    (sommaire-segment (plist-put (copy-sequence local) :section nil) t))
                   "100%-done › 50%d"))))

;;; The header line

(ert-deftest sommaire-acceptance-header-follows-a-string ()
  "An existing string is followed by the segment naming the section and current."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-mode -1)
        (setq header-line-format "BREAD")
        (sommaire-mode 1)
        (sommaire-test--heading "Emacs")
        (ert-run-idle-timers)
        (should (equal (sommaire-test-header) "BREAD  § Requirements ▾2 › Emacs"))))))

(ert-deftest sommaire-acceptance-header-follows-a-breadcrumb-style-list ()
  "A list of constructs keeps them in place, followed by the segment."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (let ((crumb '(:eval "CRUMB")))
        (sommaire-test-with-fixture "normal" extension
          (sommaire-mode -1)
          (setq header-line-format (list crumb))
          (sommaire-mode 1)
          (sommaire-test--heading "Emacs")
          (ert-run-idle-timers)
          (should (eq (car header-line-format) crumb))
          (should (equal (sommaire-test-header) "CRUMB  § Requirements ▾2 › Emacs")))))))

(ert-deftest sommaire-header-follows-any-other-construct ()
  "A single construct, which appending would break, stays one."
  (dolist (construct (list '(:eval "BREAD") 'sommaire-test--bread))
    (ert-info ((format "%S" construct))
      (sommaire-test-with-fixture "normal" "org"
        (sommaire-mode -1)
        (setq header-line-format construct)
        (sommaire-mode 1)
        (sommaire-test--heading "Emacs")
        (ert-run-idle-timers)
        (should (equal (sommaire-test-header) "BREAD  § Requirements ▾2 › Emacs"))
        (sommaire-mode -1)
        (should (equal header-line-format construct))))))

(ert-deftest sommaire-acceptance-header-alone-shows-the-path ()
  "With no header line, the segment shows the heading path."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "Emacs")
        (ert-run-idle-timers)
        (should (equal (sommaire-test-header)
                       "  Installation › § Requirements ▾2 › Emacs"))))))

(ert-deftest sommaire-header-row-stays-whatever-the-section ()
  "The header line is non-nil and the same from the start, wherever point moves."
  (sommaire-test-with-fixture "chain" "org"
    (let ((row header-line-format))
      (should row)
      (ert-run-idle-timers)
      (should (eq header-line-format row))
      (should (equal (sommaire-test-header) "  "))
      (sommaire-test--heading "Paragraph")
      (ert-run-idle-timers)
      (should (eq header-line-format row))
      (should (equal (sommaire-test-header)
                     "  Subtitle › Section › Subsection › Paragraph")))))

(ert-deftest sommaire-acceptance-header-escapes-a-title ()
  "A heading \"100%-done\" reaches the header line escaped, and shows as it is."
  (sommaire-test-with-org "* 100%-done\n** Emacs\n** Pandoc\n* Other\n"
    (sommaire-test--heading "Emacs")
    (ert-run-idle-timers)
    (should (member "§ 100%%-done ▾2 › Emacs"
                    (mapcar #'cdr sommaire--segments)))
    (should (equal (sommaire-test-header) "  § 100%-done ▾2 › Emacs"))))

(ert-deftest sommaire-acceptance-header-comes-back-exactly ()
  "Disabling the mode restores the header line itself, whatever it was."
  (dolist (found (list nil "BREAD" (list '(:eval "CRUMB")) '(:eval "BREAD")
                       'sommaire-test--bread))
    (ert-info ((format "%S" found))
      (sommaire-test-with-fixture "normal" "org"
        (sommaire-mode -1)
        (setq header-line-format found)
        (sommaire-mode 1)
        (should-not (eq header-line-format found))
        (ert-run-idle-timers)
        (sommaire-mode -1)
        (should (eq header-line-format found))
        (should-not sommaire--segments)))))

(ert-deftest sommaire-header-survives-switching-on-and-off-twice ()
  "Switching on twice adds one element, and off twice restores once."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-mode -1)
    (setq header-line-format "BREAD")
    (sommaire-mode 1)
    (let ((row header-line-format))
      (sommaire-mode 1)
      (should (eq header-line-format row)))
    (sommaire-mode -1)
    (sommaire-mode -1)
    (should (equal header-line-format "BREAD"))))

(ert-deftest sommaire-header-leaves-a-later-owner-alone ()
  "What breadcrumb adds and removes while the mode is on stays its own business.
It prepends with `add-to-list' and removes with `delete': see its source."
  (let ((crumb '(:eval "CRUMB")))
    (sommaire-test-with-fixture "normal" "org"
      (sommaire-test--heading "Emacs")
      (ert-run-idle-timers)
      (should (equal (sommaire-test-header)
                     "  Installation › § Requirements ▾2 › Emacs"))
      ;; Something else now shows where point is, so the path gives way.
      (add-to-list 'header-line-format crumb)
      (ert-run-idle-timers)
      (should (equal (sommaire-test-header) "CRUMB  § Requirements ▾2 › Emacs"))
      (setq header-line-format (delete crumb header-line-format))
      (ert-run-idle-timers)
      (should (equal (sommaire-test-header)
                     "  Installation › § Requirements ▾2 › Emacs"))
      (add-to-list 'header-line-format crumb)
      (sommaire-mode -1)
      (should (equal header-line-format (list crumb))))
    ;; With breadcrumb first, it can still find its element and leave.
    (sommaire-test-with-fixture "normal" "org"
      (sommaire-mode -1)
      (setq header-line-format (list crumb))
      (sommaire-mode 1)
      (setq header-line-format (delete crumb header-line-format))
      (should-not (member crumb header-line-format)))))

(ert-deftest sommaire-header-line-option-off-leaves-it-alone ()
  "With `sommaire-header-line' nil, the header line stays what it was."
  (let ((sommaire-header-line nil))
    (sommaire-test-with-fixture "normal" "org"
      (should-not header-line-format)
      (ert-run-idle-timers)
      (should-not header-line-format)
      (should-not sommaire--segments)
      (sommaire-mode -1)
      (should-not header-line-format))))

(ert-deftest sommaire-header-follows-point-through-the-timer ()
  "The segment changes when point has moved and the idle timer has run, not before."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (ert-run-idle-timers)
    (should (equal (sommaire-test-header) "  Installation › § Requirements ▾2 › Emacs"))
    (sommaire-test--heading "Skins")
    (should (equal (sommaire-test-header) "  Installation › § Requirements ▾2 › Emacs"))
    (ert-run-idle-timers)
    (should (equal (sommaire-test-header) "  Usage › § Skins ▾2"))))

(ert-deftest sommaire-header-redraws-only-when-the-decision-changes ()
  "The timer asks for a redraw when the segment changed, and at no other time."
  (let ((redraws 0))
    (cl-letf* ((original (symbol-function 'force-mode-line-update))
               ((symbol-function 'force-mode-line-update)
                (lambda (&rest arguments)
                  (setq redraws (1+ redraws))
                  (apply original arguments))))
      (sommaire-test-with-fixture "normal" "org"
        (setq redraws 0)
        (sommaire-test--heading "Emacs")
        (ert-run-idle-timers)
        (should (= redraws 1))
        (ert-run-idle-timers)
        (should (= redraws 1))
        ;; In the body of the same heading, the decision is the same.
        (forward-line 1)
        (ert-run-idle-timers)
        (should (= redraws 1))
        (sommaire-test--heading "Pandoc")
        (ert-run-idle-timers)
        (should (= redraws 2))))))

(ert-deftest sommaire-header-is-per-emacs-window ()
  "Two Emacs windows on one buffer each name the section around their own point."
  (sommaire-test-with-fixture "normal" "org"
    (let ((first (selected-window))
          (second (split-window-vertically)))
      (sommaire-test--heading "Emacs")
      (ert-run-idle-timers)
      (select-window second)
      (sommaire-test--heading "Skins")
      (ert-run-idle-timers)
      (should (equal (sommaire-test-header) "  Usage › § Skins ▾2"))
      (select-window first)
      (sommaire-test--heading "Emacs")
      (should (equal (sommaire-test-header)
                     "  Installation › § Requirements ▾2 › Emacs"))
      (delete-window second)
      (sommaire-test--heading "Pandoc")
      (ert-run-idle-timers)
      (should (equal (mapcar #'car sommaire--segments) (list first))))))

;;; The jump

(defun sommaire-test--offered (keys)
  "Type KEYS, and return what `completing-read' offered and its default.
The reader answers with the default, so point moves there."
  (let* ((offered nil)
         (default nil)
         (completing-read-function
          (lambda (_prompt collection &optional _predicate _require-match _initial
                           _history def &rest _)
            (setq offered (all-completions "" collection)
                  default def)
            def)))
    (execute-kbd-macro (kbd keys))
    (cons default offered)))

(ert-deftest sommaire-acceptance-jump-to-an-entry-of-the-section ()
  "M-g m Pandoc RET, typed inside the Emacs section, moves to the Pandoc heading."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "Emacs")
        (forward-line 1)
        (execute-kbd-macro (kbd "M-g m Pandoc RET"))
        (should (looking-at "[*#]+ Pandoc"))))))

(ert-deftest sommaire-acceptance-jump-with-a-prefix-offers-the-document ()
  "C-u M-g m offers Usage, and goes to it, though the section does not list it."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "Emacs")
        (should-not (member "Usage" (sommaire-test--offered "M-g m")))
        (sommaire-test--heading "Emacs")
        (should (member "Usage" (sommaire-test--offered "C-u M-g m")))
        (sommaire-test--heading "Emacs")
        (execute-kbd-macro (kbd "C-u M-g m Usage RET"))
        (should (looking-at "[*#]+ \\(?:TODO \\[#A\\] \\)?Usage"))))))

(ert-deftest sommaire-jump-offers-the-scope-in-document-order ()
  "M-g m lists the buffer's scope, and the entry that holds point is the default."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Tree-sitter")
    (should (equal (sommaire-test--offered "M-g m") '("Emacs" "Emacs" "Pandoc")))
    (setq-local sommaire-scope '(document . 2))
    (sommaire-test--heading "Tree-sitter")
    (should (equal (sommaire-test--offered "M-g m")
                   '("Requirements" "Installation" "Requirements" "Nix" "straight.el"
                     "Usage" "Live preview" "Skins")))
    (setq-local sommaire-scope '(section . all))
    (sommaire-test--heading "Tree-sitter")
    (should (equal (sommaire-test--offered "M-g m")
                   '("Tree-sitter" "Emacs" "Native compilation" "Tree-sitter" "Pandoc")))))

(ert-deftest sommaire-jump-defaults-to-the-first-entry-without-a-current-one ()
  "On the section itself no entry holds point, so the first is the default."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Requirements")
    (should (equal (sommaire-test--offered "M-g m") '("Emacs" "Emacs" "Pandoc")))
    (should (looking-at "\\*+ Emacs"))))

(ert-deftest sommaire-jump-keeps-document-order-in-the-completions ()
  "The table of completions asks not to be sorted, so the outline stays an outline."
  (sommaire-test-with-fixture "normal" "org"
    (let* ((metadata nil)
           (completing-read-function
            (lambda (_prompt collection &optional _predicate _require-match _initial
                             _history def &rest _)
              (setq metadata (completion-metadata "" collection nil))
              def)))
      (execute-kbd-macro (kbd "C-u M-g m"))
      (should (eq (completion-metadata-get metadata 'display-sort-function) #'identity))
      (should (eq (completion-metadata-get metadata 'cycle-sort-function) #'identity)))))

(ert-deftest sommaire-jump-prefix-gives-one-depth-once ()
  "A numeric prefix gives that depth of the scope, and leaves the scope as it was."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (should (equal (sommaire-test--offered "M-2 M-g m")
                   '("Emacs" "Emacs" "Native compilation" "Tree-sitter" "Pandoc")))
    (should (equal sommaire-scope '(section . 1)))
    (should-not (local-variable-p 'sommaire-scope))
    (sommaire-test--heading "Emacs")
    (should (equal (sommaire-test--offered "M-g m") '("Emacs" "Emacs" "Pandoc")))
    ;; A prefix keeps the scope's root.
    (setq-local sommaire-scope '(document . 2))
    (sommaire-test--heading "Emacs")
    (should (equal (cdr (sommaire-test--offered "M-1 M-g m")) '("Installation" "Usage")))
    ;; A depth of no use reads the scope itself.
    (setq-local sommaire-scope '(section . 1))
    (sommaire-test--heading "Emacs")
    (should (equal (cdr (sommaire-test--offered "M-- M-1 M-g m")) '("Emacs" "Pandoc")))))

(ert-deftest sommaire-jump-tells-headings-of-one-title-apart ()
  "Headings of one title each get a name of their own, and each name its heading."
  (sommaire-test-with-org "* A\n** Notes\n** Other\n* B\n** Notes\n** Other\n"
    (should (equal (cdr (sommaire-test--offered "C-u M-g m"))
                   '("A" "Notes" "Other" "B" "Notes <2>" "Other <2>")))
    (goto-char (point-min))
    (let ((completing-read-function (lambda (&rest _) "Notes <2>")))
      (execute-kbd-macro (kbd "C-u M-g m")))
    (should (looking-at "\\*\\* Notes"))
    (should (save-excursion (forward-line -1) (looking-at "\\* B")))
    (goto-char (point-min))
    (execute-kbd-macro (kbd "C-u M-g m Notes RET"))
    (should (save-excursion (forward-line -1) (looking-at "\\* A")))))

(ert-deftest sommaire-jump-says-when-a-scope-is-empty ()
  "With nothing to offer it says so, offers nothing, and point stays."
  (sommaire-test-with-fixture "chain" "org"
    (sommaire-test--heading "Paragraph")
    (let ((start (point)))
      (should-error (sommaire-jump) :type 'user-error)
      (should (= (point) start))
      (should (equal (cdr (sommaire-test--offered "C-u M-g m"))
                     '("Subtitle" "Section" "Subsection" "Paragraph"))))))

(ert-deftest sommaire-jump-leaves-the-mark-behind ()
  "A jump can be undone by popping the mark."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (let ((start (point)))
      (execute-kbd-macro (kbd "M-g m Pandoc RET"))
      (should (= (mark t) start)))))

(ert-deftest sommaire-jump-stays-in-a-narrowed-part ()
  "Under narrowing the part's heading is the root: rule R6."
  (sommaire-test-with-fixture "narrowing" "org"
    (sommaire-test-narrow-to-usage "\\*")
    (should (equal (cdr (sommaire-test--offered "C-u M-g m"))
                   '("Live preview" "Skins" "XIX" "Folio" "Quarto" "Briefing")))))

(ert-deftest sommaire-jump-is-bound-in-the-mode-only ()
  "M-g m runs the jump in the mode's map, and nowhere else."
  (sommaire-test-with-fixture "normal" "org"
    (should (eq (key-binding (kbd "M-g m")) #'sommaire-jump))
    (should-not (lookup-key global-map (kbd "M-g m")))
    (sommaire-mode -1)
    (should-not (key-binding (kbd "M-g m")))))

;;; The buttons

(defun sommaire-test--overlays (property)
  "Return the overlays of this whole buffer that have PROPERTY, in order."
  (save-restriction
    (widen)
    (sort (seq-filter (lambda (overlay) (overlay-get overlay property))
                      (overlays-in (point-min) (point-max)))
          (lambda (one other) (< (overlay-start one) (overlay-start other))))))

(defun sommaire-test--buttons ()
  "Return the buttons of this buffer: pairs of a heading's line and its button."
  (mapcar (lambda (overlay)
            (cons (buffer-substring-no-properties (overlay-start overlay) (overlay-end overlay))
                  (substring-no-properties (overlay-get overlay 'after-string))))
          (sommaire-test--overlays 'after-string)))

(defun sommaire-test--fontify ()
  "Do what redisplay would do for the whole buffer, so `jit-lock' sees all the text."
  (let ((inhibit-modification-hooks t))
    (with-silent-modifications
      (remove-text-properties (point-min) (point-max) '(fontified nil))))
  (jit-lock-fontify-now))

(defmacro sommaire-test--with-lines-shown (lines &rest body)
  "Run BODY with an Emacs window showing LINES lines from its start.
In batch `window-end' gives the end of the buffer whatever its height."
  (declare (indent 1) (debug t))
  `(cl-letf (((symbol-function 'window-end)
              (lambda (&optional window _update)
                (save-excursion
                  (goto-char (window-start window))
                  (pos-bol (1+ ,lines))))))
     ,@body))

(defun sommaire-test--far-document ()
  "Insert a document whose second run anchor lies far beyond any Emacs window."
  (insert "* Near\n** One\n** Two\n")
  (dotimes (_ 500)
    (insert "Text.\n"))
  (insert "* Far\n** Three\n** Four\n")
  (org-mode)
  (goto-char (point-min)))

(ert-deftest sommaire-buttons-stand-at-run-anchors-only ()
  "A button \"▸ N\" stands at each run anchor, where N is its entries, and nowhere else."
  (sommaire-test-with-fixture "normal" "org"
    (ert-run-idle-timers)
    (sommaire-test--fontify)
    (should (equal (mapcar #'cdr (sommaire-test--buttons))
                   '(" ▸ 3" " ▸ 2" " ▸ 2" " ▸ 2")))
    (should (equal (mapcar #'car (sommaire-test--buttons))
                   '("* Installation" "** straight.el"
                     "* TODO [#A] Usage [1/2] :manual:" "** Skins"))))
  (sommaire-test-with-fixture "normal" "md"
    (ert-run-idle-timers)
    (sommaire-test--fontify)
    (should (equal (sommaire-test--buttons)
                   '(("Installation" . " ▸ 3") ("### straight.el" . " ▸ 2")
                     ("## Usage" . " ▸ 2") ("### Skins" . " ▸ 2"))))))

(ert-deftest sommaire-chain-has-no-button ()
  "A chain of single children has no anchor, so no button: acceptance 1."
  (dolist (extension '("org" "md"))
    (sommaire-test-with-fixture "chain" extension
      (ert-run-idle-timers)
      (sommaire-test--fontify)
      (should-not (sommaire-test--buttons)))))

(ert-deftest sommaire-buttons-come-as-text-comes-into-view ()
  "No button stands beyond what shows, until `jit-lock' gets there."
  (sommaire-test-with-buffer (sommaire-test--far-document)
    (sommaire-test--with-lines-shown 20
      (ert-run-idle-timers))
    (should (equal (sommaire-test--buttons) '(("* Near" . " ▸ 2"))))
    (search-forward "* Far")
    (let ((start (pos-bol)))
      (jit-lock-fontify-now start (+ start 10)))
    (should (equal (sommaire-test--buttons)
                   '(("* Near" . " ▸ 2") ("* Far" . " ▸ 2"))))
    ;; Asked again, it adds no second one.
    (sommaire-test--fontify)
    (should (= (length (sommaire-test--buttons)) 2))))

(ert-deftest sommaire-buttons-follow-a-scroll-through-the-timer ()
  "Text that `jit-lock' saw before gets its button when an Emacs window shows it."
  (sommaire-test-with-buffer (sommaire-test--far-document)
    (sommaire-test--with-lines-shown 20
      (ert-run-idle-timers)
      (should-not (member '("* Far" . " ▸ 2") (sommaire-test--buttons)))
      (search-forward "* Far")
      (set-window-start nil (pos-bol))
      (ert-run-idle-timers)
      (should (member '("* Far" . " ▸ 2") (sommaire-test--buttons))))))

(ert-deftest sommaire-buttons-wait-for-the-read-after-an-edit ()
  "Between an edit and the next read, places are old, and nothing goes on them."
  (sommaire-test-with-buffer (sommaire-test--far-document)
    (sommaire-test--with-lines-shown 20
      (ert-run-idle-timers))
    (goto-char (point-min))
    (insert "New first line.\n")
    (sommaire-test--fontify)
    (should-not (member '("* Far" . " ▸ 2") (sommaire-test--buttons)))
    (ert-run-idle-timers)
    (sommaire-test--fontify)
    (should (member '("* Far" . " ▸ 2") (sommaire-test--buttons)))))

(ert-deftest sommaire-buttons-stay-when-the-decision-stays ()
  "An edit elsewhere keeps the button itself, which has moved with the text."
  (sommaire-test-with-org "Text.\n* Near\n** One\n** Two\n"
    (ert-run-idle-timers)
    (let ((button (car (sommaire-test--overlays 'after-string))))
      (goto-char (point-min))
      (insert "More text.\n")
      (ert-run-idle-timers)
      (should (equal (sommaire-test--overlays 'after-string) (list button)))
      (should (equal (sommaire-test--buttons) '(("* Near" . " ▸ 2")))))))

(ert-deftest sommaire-buttons-stay-at-the-end-of-their-line ()
  "Text typed at a heading's end stays before its button, and a new line after it."
  (sommaire-test-with-org "* Near\n** One\n** Two\n"
    (ert-run-idle-timers)
    (goto-char (point-min))
    (end-of-line)
    (insert " and more")
    (should (equal (sommaire-test--buttons) '(("* Near and more" . " ▸ 2"))))
    (insert "\nA line of text.")
    (ert-run-idle-timers)
    (should (equal (sommaire-test--buttons) '(("* Near and more" . " ▸ 2"))))))

(ert-deftest sommaire-buttons-follow-a-changed-decision ()
  "A new anchor gets its button, a changed one a new number, and a lost one none."
  (sommaire-test-with-org "* One\n** A\n** B\n* Two\n** C\n"
    (ert-run-idle-timers)
    (should (equal (sommaire-test--buttons) '(("* One" . " ▸ 2"))))
    ;; A second child makes "Two" worth a minitoc.
    (goto-char (point-max))
    (insert "** D\n")
    (ert-run-idle-timers)
    (should (equal (sommaire-test--buttons) '(("* One" . " ▸ 2") ("* Two" . " ▸ 2"))))
    (insert "** E\n")
    (ert-run-idle-timers)
    (should (equal (sommaire-test--buttons) '(("* One" . " ▸ 2") ("* Two" . " ▸ 3"))))
    ;; "One" loses a child, and so its minitoc.
    (goto-char (point-min))
    (search-forward "** A\n")
    (delete-region (match-beginning 0) (match-end 0))
    (ert-run-idle-timers)
    (should (equal (sommaire-test--buttons) '(("* Two" . " ▸ 3"))))))

(ert-deftest sommaire-buttons-follow-narrowing ()
  "Under narrowing the anchors are those of the part: rule R6."
  (sommaire-test-with-fixture "narrowing" "org"
    (ert-run-idle-timers)
    (sommaire-test--fontify)
    (should (member "* Usage" (mapcar #'car (sommaire-test--buttons))))
    (sommaire-test-narrow-to-usage "\\*")
    (ert-run-idle-timers)
    ;; "Usage" is the root now, and the root is no anchor.
    (should-not (member "* Usage" (mapcar #'car (sommaire-test--buttons))))))

(ert-deftest sommaire-buttons-option-off-gives-none ()
  "With `sommaire-heading-buttons' nil, the mode leaves `jit-lock' alone."
  (let ((sommaire-heading-buttons nil))
    (sommaire-test-with-fixture "normal" "org"
      (should-not (memq #'sommaire--place-buttons jit-lock-functions))
      (ert-run-idle-timers)
      (should-not (sommaire-test--buttons)))))

(ert-deftest sommaire-buttons-work-in-an-indirect-buffer ()
  "`jit-lock' refuses an indirect buffer, so the timer places what its window shows."
  (sommaire-test-with-buffer
      (progn
        (insert "* Near\n** One\n** Two\n")
        (org-mode)
        (sommaire-mode -1))
    (let* ((messages nil)
           (clone (clone-indirect-buffer nil nil)))
      (unwind-protect
          (cl-letf* ((original (symbol-function 'message))
                     ((symbol-function 'message)
                      (lambda (format-string &rest arguments)
                        (push (apply #'format format-string arguments) messages)
                        (apply original format-string arguments))))
            (set-window-buffer nil clone)
            (with-current-buffer clone
              (sommaire-mode 1)
              (should-not messages)
              (ert-run-idle-timers)
              (should (equal (sommaire-test--buttons) '(("* Near" . " ▸ 2")))))
            (should-not (sommaire-test--buttons)))
        (kill-buffer clone)))))

(ert-deftest sommaire-mode-ends-without-a-trace-in-jit-lock ()
  "The buffer's `jit-lock' goes back to what it was when the mode ends."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-mode -1)
    (font-lock-mode 1)
    (let ((before (list jit-lock-mode jit-lock-functions)))
      (sommaire-mode 1)
      (should (memq #'sommaire--place-buttons jit-lock-functions))
      (sommaire-mode -1)
      (should (equal (list jit-lock-mode jit-lock-functions) before)))))

(ert-deftest sommaire-mode-ends-without-an-overlay ()
  "Ending the mode removes every overlay, whatever the narrowing."
  (sommaire-test-with-fixture "normal" "org"
    (ert-run-idle-timers)
    (sommaire-test--fontify)
    (sommaire-test--heading "Usage")
    (sommaire-toggle-inline)
    (should (sommaire-test--overlays 'after-string))
    (should (sommaire-test--overlays 'before-string))
    (narrow-to-region (point-min) (+ (point-min) 10))
    (sommaire-mode -1)
    (should-not (sommaire-test--overlays 'after-string))
    (should-not (sommaire-test--overlays 'before-string))))

;;; The inline minitoc

(defun sommaire-test--click (position &optional string)
  "Return a click in the selected Emacs window at POSITION, in STRING if given.
STRING is a pair of a string and an offset, as a real click on one has it."
  (list 'mouse-1 (list (selected-window) position '(0 . 0) 0 string position)))

(defun sommaire-test--hide-subtree (extension)
  "Fold the heading at point, in a buffer of EXTENSION, as a reader would.
Markdown folds through `outline-minor-mode', which the README shows in one line."
  (when (equal extension "md")
    (setq-local outline-regexp "#+ ")
    (outline-minor-mode 1))
  (outline-hide-subtree))

(ert-deftest sommaire-acceptance-inline-leaves-one-overlay-at-the-last-heading ()
  "Opening at A then at B leaves one overlay, of the selected Emacs window, at B's
first character after its metadata, and folding B makes it invisible."
  (pcase-dolist (`(,extension . ,first-after-metadata)
                 '(("org" . "This section starts") ("md" . "This section starts")))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "Skins")
        (sommaire-toggle-inline)
        (sommaire-test--heading "Usage")
        (sommaire-toggle-inline)
        (let ((overlays (sommaire-test--overlays 'before-string)))
          (should (= (length overlays) 1))
          (should (eq (overlay-get (car overlays) 'window) (selected-window)))
          (goto-char (overlay-start (car overlays)))
          (should (looking-at first-after-metadata))
          (should-not (invisible-p (overlay-start (car overlays))))
          (sommaire-test--heading "Usage")
          (sommaire-test--hide-subtree extension)
          (should (invisible-p (overlay-start (car overlays)))))))))

(ert-deftest sommaire-inline-sits-before-the-introduction ()
  "An inline minitoc goes after the metadata and before the introduction: rule R5."
  (sommaire-test-with-org "* Top\nDEADLINE: <2026-11-02 Mon>\n:PROPERTIES:\n:ID: a\n:END:\nIntro.\n** A\n** B\n"
    (sommaire-toggle-inline)
    (goto-char (overlay-start (car (sommaire-test--overlays 'before-string))))
    (should (looking-at "Intro\\."))))

(ert-deftest sommaire-inline-closes-at-its-own-heading ()
  "Asked again at the same heading, the inline minitoc closes."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Usage")
    (sommaire-toggle-inline)
    (should (sommaire-test--overlays 'before-string))
    (sommaire-toggle-inline)
    (should-not (sommaire-test--overlays 'before-string))))

(ert-deftest sommaire-inline-lists-the-decision ()
  "The minitoc lists its block, a merged heading with its own children below it."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Installation")
    (sommaire-toggle-inline)
    (should (equal (substring-no-properties
                    (overlay-get (car (sommaire-test--overlays 'before-string)) 'before-string))
                   "  Requirements\n    Emacs\n    Pandoc\n  Nix\n  straight.el\n"))))

(ert-deftest sommaire-inline-shows-a-percent-sign-as-it-is ()
  "A title in a buffer's overlay is no mode line, so it stays as the source has it."
  (sommaire-test-with-org "* Top\n** 100%-done\n** Other\n"
    (sommaire-toggle-inline)
    (should (equal (substring-no-properties
                    (overlay-get (car (sommaire-test--overlays 'before-string)) 'before-string))
                   "  100%-done\n  Other\n"))))

(ert-deftest sommaire-inline-dims-an-archived-entry ()
  "An archived entry is listed, dimmed: rule R1."
  (sommaire-test-with-fixture "archive" "org"
    (sommaire-test--heading "Usage")
    (sommaire-toggle-inline)
    (let* ((text (overlay-get (car (sommaire-test--overlays 'before-string)) 'before-string))
           (face (lambda (title)
                   (ensure-list (get-text-property (string-search title text) 'face text)))))
      (should (memq 'sommaire-archived (funcall face "Old skins")))
      (should-not (memq 'sommaire-archived (funcall face "Skins"))))))

(ert-deftest sommaire-inline-opens-at-the-anchor-of-a-merged-heading ()
  "From a heading with no button, the nearest anchor around point opens: rule R3."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Requirements")
    (sommaire-toggle-inline)
    (goto-char (overlay-start (car (sommaire-test--overlays 'before-string))))
    (should (looking-at "# A comment is no introduction"))
    (sommaire-toggle-inline)
    (sommaire-test--heading "A local clone")
    (sommaire-toggle-inline)
    (should (string-prefix-p
             "  The recipe\n"
             (overlay-get (car (sommaire-test--overlays 'before-string)) 'before-string)))))

(ert-deftest sommaire-inline-refuses-where-no-anchor-is ()
  "Where no anchor lies around point it says so, and opens nothing."
  (sommaire-test-with-fixture "chain" "org"
    (sommaire-test--heading "Paragraph")
    (should-error (sommaire-toggle-inline) :type 'user-error)
    (should-not (sommaire-test--overlays 'before-string)))
  (sommaire-test-with-fixture "normal" "org"
    (goto-char (point-min))
    (should-error (sommaire-toggle-inline) :type 'user-error)))

(ert-deftest sommaire-inline-needs-the-mode ()
  "Without the mode nothing would remove an overlay, so none is made."
  (with-temp-buffer
    (insert "* Top\n** A\n** B\n")
    (org-mode)
    (goto-char (point-min))
    (should-error (sommaire-toggle-inline) :type 'user-error)
    (should-not (sommaire-test--overlays 'before-string))))

(ert-deftest sommaire-inline-is-per-emacs-window ()
  "Each Emacs window holds at most one, and opening one leaves the other's alone."
  (sommaire-test-with-fixture "normal" "org"
    (let ((first (selected-window))
          (second (split-window-vertically)))
      (sommaire-test--heading "Usage")
      (sommaire-toggle-inline)
      (select-window second)
      (sommaire-test--heading "straight.el")
      (sommaire-toggle-inline)
      (let ((overlays (sommaire-test--overlays 'before-string)))
        (should (equal (mapcar (lambda (overlay) (overlay-get overlay 'window)) overlays)
                       (list second first))))
      (select-window first)
      (sommaire-test--heading "Skins")
      (sommaire-toggle-inline)
      (let ((overlays (sommaire-test--overlays 'before-string)))
        (should (= (length overlays) 2))
        (should (equal (overlay-get (nth 1 overlays) 'window) first)))
      (delete-window second))))

(ert-deftest sommaire-inline-goes-with-its-emacs-window ()
  "An overlay of a dead Emacs window goes at the next change of the outline."
  (sommaire-test-with-fixture "normal" "org"
    (let ((second (split-window-vertically)))
      (select-window second)
      (sommaire-test--heading "Usage")
      (sommaire-toggle-inline)
      (delete-window second)
      (insert "x")
      (ert-run-idle-timers)
      (should-not (sommaire-test--overlays 'before-string)))))

(ert-deftest sommaire-inline-follows-the-text ()
  "An open minitoc keeps its place and shows new entries, and goes with its anchor."
  (sommaire-test-with-org "* Top\nIntro.\n** A\n** B\n* Other\n"
    (sommaire-toggle-inline)
    (let ((overlay (car (sommaire-test--overlays 'before-string))))
      ;; Text above moves it along, and redraws nothing.
      (let ((text (overlay-get overlay 'before-string)))
        (goto-char (point-min))
        (insert "New first line.\n")
        (ert-run-idle-timers)
        (should (eq (overlay-get overlay 'before-string) text)))
      (goto-char (overlay-start overlay))
      (should (looking-at "Intro\\."))
      ;; Metadata typed at its place keep it after them: rule R5.
      (insert "DEADLINE: <2026-11-02 Mon>\n")
      (ert-run-idle-timers)
      (goto-char (overlay-start overlay))
      (should (looking-at "Intro\\."))
      ;; A new child is a new entry.
      (search-forward "** B\n")
      (insert "** C\n")
      (ert-run-idle-timers)
      (should (equal (substring-no-properties (overlay-get overlay 'before-string))
                     "  A\n  B\n  C\n"))
      ;; Its heading gone, it goes too.
      (goto-char (point-min))
      (search-forward "* Top\n")
      (delete-region (match-beginning 0) (match-end 0))
      (ert-run-idle-timers)
      (should-not (sommaire-test--overlays 'before-string)))))

(ert-deftest sommaire-a-click-on-a-button-opens-its-heading ()
  "The button is a string, so a click reaches its keymap, and acts on its heading."
  (sommaire-test-with-fixture "normal" "org"
    (ert-run-idle-timers)
    (sommaire-test--fontify)
    (goto-char (point-min))
    (let* ((button (seq-find (lambda (overlay)
                               (string-prefix-p "* TODO" (buffer-substring (overlay-start overlay)
                                                                           (overlay-end overlay))))
                             (sommaire-test--overlays 'after-string)))
           (string (overlay-get button 'after-string))
           (command (lookup-key (get-text-property 0 'keymap string) [mouse-1]))
           (last-command-event (sommaire-test--click (overlay-end button))))
      (should (eq command #'sommaire-toggle-inline))
      (call-interactively command)
      (goto-char (overlay-start (car (sommaire-test--overlays 'before-string))))
      (should (looking-at "This section starts")))))

(ert-deftest sommaire-a-click-on-an-entry-goes-to-its-heading ()
  "An inline minitoc's lines are a string, whose keymap takes a click to the heading."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Installation")
    (sommaire-toggle-inline)
    (let* ((text (overlay-get (car (sommaire-test--overlays 'before-string)) 'before-string))
           (offset (string-search "Pandoc" text))
           (command (lookup-key (get-text-property offset 'keymap text) [mouse-1])))
      (should (eq command #'sommaire-follow-inline))
      (funcall command (sommaire-test--click (point) (cons text offset)))
      (should (looking-at "\\*+ Pandoc")))))

;;; The reading

(defmacro sommaire-test--counting-reads (&rest body)
  "Run BODY, and return how many times it called either adapter."
  (declare (debug t))
  `(let* ((reads 0)
          (count (lambda (&rest _) (setq reads (1+ reads)))))
     (advice-add 'sommaire-org-outline :before count)
     (advice-add 'sommaire-markdown-outline :before count)
     (unwind-protect
         (progn ,@body reads)
       (advice-remove 'sommaire-org-outline count)
       (advice-remove 'sommaire-markdown-outline count))))

(ert-deftest sommaire-timer-reads-only-the-selected-buffer ()
  "A buffer with the mode that the selected Emacs window does not show is not read."
  (sommaire-test-with-fixture "normal" "org"
    (with-temp-buffer
      (set-window-buffer nil (current-buffer))
      (should (= (sommaire-test--counting-reads (ert-run-idle-timers)) 0)))
    (set-window-buffer nil sommaire-test--buffer)
    (should (= (sommaire-test--counting-reads (ert-run-idle-timers)) 1))))

(ert-deftest sommaire-a-pending-key-keeps-what-is-shown ()
  "With a key pending, the timer does not read, and what is shown stays."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (ert-run-idle-timers)
    (sommaire-test--heading "Skins")
    (should (= 0 (let ((unread-command-events (list ?a)))
                   (sommaire-test--counting-reads (ert-run-idle-timers)))))
    (should (equal (sommaire-test-header) "  Installation › § Requirements ▾2 › Emacs"))
    (ert-run-idle-timers)
    (should (equal (sommaire-test-header) "  Usage › § Skins ▾2"))))

(ert-deftest sommaire-a-key-during-the-read-keeps-what-is-shown ()
  "A key that arrives while the adapter reads ends the read, and what is shown stays.
A key sets `quit-flag' to `throw-on-input', which is non-nil only in
`while-no-input': without it, the read below would run to its end."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (ert-run-idle-timers)
    (let ((outline (sommaire-org-outline)))
      (sommaire-test--heading "Skins")
      (cl-letf (((symbol-function 'sommaire-org-outline)
                 (lambda ()
                   (setq quit-flag throw-on-input)
                   outline)))
        (ert-run-idle-timers)))
    (should-not quit-flag)
    (should (equal (sommaire-test-header) "  Installation › § Requirements ▾2 › Emacs"))))

(ert-deftest sommaire-a-part-too-large-is-said-once-and-not-read ()
  "Beyond the limit no adapter runs, and the reader hears of it once, until it ends."
  (let ((messages nil))
    (cl-letf* ((original (symbol-function 'message))
               ((symbol-function 'message)
                (lambda (format-string &rest arguments)
                  (let ((text (apply #'format format-string arguments)))
                    (when (string-prefix-p "sommaire:" text)
                      (push text messages)))
                  (apply original format-string arguments))))
      (sommaire-test-with-buffer
          (progn
            (insert "* Small\n** One\n** Two\n")
            (sommaire-test-insert-text sommaire-rules-largest-part)
            (org-mode)
            (goto-char (point-min)))
        (should (= (sommaire-test--counting-reads
                    (ert-run-idle-timers)
                    (insert "x")
                    (ert-run-idle-timers)
                    (delete-char -1)
                    (ert-run-idle-timers))
                   0))
        (should (= (length messages) 1))
        (should (equal (sommaire-test-header) "  "))
        ;; Narrowed, the part is small enough, and is read.
        (narrow-to-region (point-min) (+ (point-min) 22))
        (goto-char (point-min))
        (should (= (sommaire-test--counting-reads (ert-run-idle-timers)) 1))
        (should (equal (length messages) 1))
        (should (string-prefix-p "  § Small ▾2" (sommaire-test-header)))
        ;; Too large again, it is said again, once.
        (widen)
        (should (= (sommaire-test--counting-reads
                    (ert-run-idle-timers)
                    (ert-run-idle-timers))
                   0))
        (should (= (length messages) 2))))))

(ert-deftest sommaire-mode-reads-org-and-anything-else-as-markdown ()
  "An Org buffer goes to the Org adapter, and any other to the Markdown scanner."
  (sommaire-test-with-buffer
      (progn
        (insert "# Top\n\n## A\n\n## B\n")
        (goto-char (point-min)))
    (ert-run-idle-timers)
    (should (equal (sommaire-test-header) "  § Top ▾2")))
  (sommaire-test-with-org "* Top\n** A\n** B\n"
    (ert-run-idle-timers)
    (should (equal (sommaire-test-header) "  § Top ▾2"))))

;;; What the mode adds and removes

(ert-deftest sommaire-mode-has-one-timer-whatever-the-buffers ()
  "One idle timer serves all the buffers, and goes with the last of them."
  (let ((before (length timer-idle-list))
        (other (generate-new-buffer "sommaire-test-other")))
    (unwind-protect
        (sommaire-test-with-fixture "normal" "org"
          (should (= (length timer-idle-list) (1+ before)))
          (with-current-buffer other
            (sommaire-mode 1))
          (should (= (length timer-idle-list) (1+ before)))
          (sommaire-mode -1)
          (should (= (length timer-idle-list) (1+ before)))
          (with-current-buffer other
            (sommaire-mode -1))
          (should (= (length timer-idle-list) before))
          (should-not sommaire--timer))
      (kill-buffer other))))

(ert-deftest sommaire-mode-takes-its-timer-along-when-killed ()
  "Killing the last buffer with the mode ends the timer."
  (let ((before (length timer-idle-list))
        (buffer (generate-new-buffer "sommaire-test-other")))
    (with-current-buffer buffer
      (sommaire-mode 1))
    (should (= (length timer-idle-list) (1+ before)))
    (kill-buffer buffer)
    (should (= (length timer-idle-list) before))))

(ert-deftest sommaire-mode-ends-with-its-major-mode ()
  "A change of major mode wipes the buffer's variables, so the mode ends first."
  (let ((before (length timer-idle-list)))
    (sommaire-test-with-fixture "normal" "org"
      (text-mode)
      (should-not sommaire-mode)
      (should-not header-line-format)
      (should (= (length timer-idle-list) before)))))

(ert-deftest sommaire-mode-removes-its-hooks ()
  "The buffer's hooks and the global ones are what they were when the mode ends."
  (let ((global (list (default-value 'change-major-mode-hook)
                      (default-value 'kill-buffer-hook))))
    (sommaire-test-with-fixture "normal" "org"
      (should (memq #'sommaire--stop change-major-mode-hook))
      (should (memq #'sommaire--stop kill-buffer-hook))
      (sommaire-mode -1)
      (should-not (memq #'sommaire--stop change-major-mode-hook))
      (should-not (memq #'sommaire--stop kill-buffer-hook))
      (should (equal (list (default-value 'change-major-mode-hook)
                           (default-value 'kill-buffer-hook))
                     global)))))

(ert-deftest sommaire-mode-leaves-the-text-alone ()
  "The mode changes no character, and does not mark the buffer as modified."
  (sommaire-test-with-fixture "normal" "org"
    (set-buffer-modified-p nil)
    (let ((text (buffer-string))
          (tick (buffer-chars-modified-tick)))
      (sommaire-test--heading "Emacs")
      (ert-run-idle-timers)
      (sommaire-mode -1)
      (should (equal (buffer-string) text))
      (should (= (buffer-chars-modified-tick) tick))
      (should-not (buffer-modified-p)))))

(ert-deftest sommaire-load-reads-no-document-format ()
  "Loading sommaire loads neither Org nor its adapters, which only a buffer needs."
  (should (equal (repo-test-emacs
                  (list "-L" (expand-file-name "sommaire" repo-test-root)
                        "-l" "sommaire"
                        "--eval"
                        "(prin1 (seq-filter #'featurep '(org org-element sommaire-org sommaire-markdown)))"))
                 '(0 . "nil"))))

;;; sommaire-test.el ends here
