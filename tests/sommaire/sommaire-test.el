;;; sommaire-test.el --- The surfaces of sommaire  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: plan 005, acceptance 3 to 5, 7 and 8, and "For step 5" in its
;; notes: what `sommaire-mode' draws from the decisions of
;; docs/minitoc-rules.md.  The expectations come from those rules and that
;; plan, on the fixtures written by hand from them.
;;
;; `format-mode-line' returns "" in batch, so a header line is compared as
;; structure and through `sommaire-test-header', which renders the constructs
;; that a header line can hold.  For acceptance 6, the tests of acceptance 3
;; and 4 run again in a child Emacs: their names start with
;; sommaire-acceptance-header- and sommaire-acceptance-jump-.

;;; Code:

(require 'ert)
(require 'ert-x)
(require 'cl-lib)
(require 'cus-edit)
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

(defun sommaire-test--current-in-segment ()
  "Return the part of the selected Emacs window's segment in the face of the current."
  (let* ((segment (alist-get (selected-window) sommaire--segments))
         (start (text-property-any 0 (length segment) 'face 'sommaire-current segment)))
    (and start
         (substring-no-properties
          segment start (or (next-single-property-change start 'face segment)
                            (length segment))))))

(defun sommaire-test--idle ()
  "Run the idle timers with `ert-run-idle-timers', and fail on an error in one.
`timer-event-handler' catches such an error and only says so."
  (let ((errors nil))
    (cl-letf* ((original (symbol-function 'message))
               ((symbol-function 'message)
                (lambda (format-string &rest arguments)
                  (when (string-prefix-p "Error running timer" format-string)
                    (push arguments errors))
                  (apply original format-string arguments))))
      (ert-run-idle-timers))
    (should-not errors)))

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
        (sommaire-test--idle)
        (should (member "BREAD" header-line-format))
        (should (equal (sommaire-test-header) "BREAD  § Requirements ▾2 › Emacs"))
        (should (equal (sommaire-test--current-in-segment) "Emacs"))))))

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
          (sommaire-test--idle)
          (should (eq (car header-line-format) crumb))
          (should (equal (sommaire-test-header) "CRUMB  § Requirements ▾2 › Emacs"))
          (should (equal (sommaire-test--current-in-segment) "Emacs")))))))

(ert-deftest sommaire-header-follows-any-other-construct ()
  "A single construct, which appending would break, stays one."
  (dolist (construct (list '(:eval "BREAD") 'sommaire-test--bread))
    (ert-info ((format "%S" construct))
      (sommaire-test-with-fixture "normal" "org"
        (sommaire-mode -1)
        (setq header-line-format construct)
        (sommaire-mode 1)
        (sommaire-test--heading "Emacs")
        (sommaire-test--idle)
        (should (equal (sommaire-test-header) "BREAD  § Requirements ▾2 › Emacs"))
        (sommaire-mode -1)
        (should (equal header-line-format construct))))))

(ert-deftest sommaire-acceptance-header-alone-shows-the-path ()
  "With no header line, the segment shows the heading path."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "Emacs")
        (sommaire-test--idle)
        (should (equal (sommaire-test-header)
                       "  Installation › § Requirements ▾2 › Emacs"))))))

(ert-deftest sommaire-header-row-stays-whatever-the-section ()
  "The header line is non-nil and the same from the start, wherever point moves."
  (sommaire-test-with-fixture "chain" "org"
    (let ((row header-line-format))
      (should row)
      (sommaire-test--idle)
      (should (eq header-line-format row))
      (should (equal (sommaire-test-header) "  "))
      (sommaire-test--heading "Paragraph")
      (sommaire-test--idle)
      (should (eq header-line-format row))
      (should (equal (sommaire-test-header)
                     "  Subtitle › Section › Subsection › Paragraph")))))

(ert-deftest sommaire-acceptance-header-escapes-a-title ()
  "A heading \"100%-done\" reaches the header line escaped, and shows as it is."
  (sommaire-test-with-org "* 100%-done\n** Emacs\n** Pandoc\n* Other\n"
    (sommaire-test--heading "Emacs")
    (sommaire-test--idle)
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
        (sommaire-test--idle)
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
      (sommaire-test--idle)
      (should (equal (sommaire-test-header)
                     "  Installation › § Requirements ▾2 › Emacs"))
      ;; Something else now shows where point is, so the path gives way.
      (add-to-list 'header-line-format crumb)
      (sommaire-test--idle)
      (should (equal (sommaire-test-header) "CRUMB  § Requirements ▾2 › Emacs"))
      (setq header-line-format (delete crumb header-line-format))
      (sommaire-test--idle)
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
      (sommaire-test--idle)
      (should-not header-line-format)
      (should-not sommaire--segments)
      (sommaire-mode -1)
      (should-not header-line-format))))

(ert-deftest sommaire-header-follows-point-through-the-timer ()
  "The segment changes when point has moved and the idle timer has run, not before."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-test--idle)
    (should (equal (sommaire-test-header) "  Installation › § Requirements ▾2 › Emacs"))
    (sommaire-test--heading "Skins")
    (should (equal (sommaire-test-header) "  Installation › § Requirements ▾2 › Emacs"))
    (sommaire-test--idle)
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
        (sommaire-test--idle)
        (should (= redraws 1))
        (sommaire-test--idle)
        (should (= redraws 1))
        ;; In the body of the same heading, the decision is the same.
        (forward-line 1)
        (sommaire-test--idle)
        (should (= redraws 1))
        (sommaire-test--heading "Pandoc")
        (sommaire-test--idle)
        (should (= redraws 2))))))

(ert-deftest sommaire-header-is-per-emacs-window ()
  "Two Emacs windows on one buffer each name the section around their own point."
  (sommaire-test-with-fixture "normal" "org"
    (let ((first (selected-window))
          (second (split-window-vertically)))
      (sommaire-test--heading "Emacs")
      (sommaire-test--idle)
      (select-window second)
      (sommaire-test--heading "Skins")
      (sommaire-test--idle)
      (should (equal (sommaire-test-header) "  Usage › § Skins ▾2"))
      (select-window first)
      (sommaire-test--heading "Emacs")
      (should (equal (sommaire-test-header)
                     "  Installation › § Requirements ▾2 › Emacs"))
      (delete-window second)
      (sommaire-test--heading "Pandoc")
      (sommaire-test--idle)
      (should (equal (mapcar #'car sommaire--segments) (list first))))))

(ert-deftest sommaire-header-names-the-section-in-a-window-never-selected ()
  "An Emacs window names the section around its own point, without ever being selected.
Each view shows one local minitoc by itself, and an edit through another Emacs
window reaches it too."
  (sommaire-test-with-org "* One\n** A\n** B\n* Two\n** C\n** D\n"
    (let ((first (selected-window))
          (second (split-window-vertically)))
      (sommaire-test--heading "A")
      (set-window-point second (save-excursion
                                 (sommaire-test--heading "D")
                                 (point)))
      (sommaire-test--idle)
      (should (eq (selected-window) first))
      (should (equal (sommaire-test-header) "  § One ▾2 › A"))
      (should (equal (with-selected-window second (sommaire-test-header)) "  § Two ▾2 › D"))
      (save-excursion
        (goto-char (point-max))
        (insert "** E\n"))
      (sommaire-test--idle)
      (should (eq (selected-window) first))
      (should (equal (sommaire-test-header) "  § One ▾2 › A"))
      (should (equal (with-selected-window second (sommaire-test-header)) "  § Two ▾3 › D")))))

(ert-deftest sommaire-header-names-the-section-of-another-buffer-never-selected ()
  "A buffer with the mode has its segment as soon as an Emacs window shows it."
  (let ((other (generate-new-buffer "sommaire-test-other")))
    (unwind-protect
        (sommaire-test-with-org "* One\n** A\n** B\n"
          (let ((first (selected-window))
                (second (split-window-vertically)))
            (with-current-buffer other
              (insert "# Top\n\n## C\n\n## D\n")
              (sommaire-mode 1))
            (set-window-buffer second other)
            (set-window-point second (with-current-buffer other (point-max)))
            (sommaire-test--idle)
            (should (eq (selected-window) first))
            (should (equal (with-selected-window second (sommaire-test-header))
                           "  § Top ▾2 › D"))))
      (kill-buffer other))))

(ert-deftest sommaire-header-takes-a-window-point-outside-the-narrowing ()
  "Narrowing through one Emacs window can leave another's point outside the part.
Redisplay moves that point back, and until then it counts as the nearest end."
  (sommaire-test-with-org "* One\n** A\n** B\n* Two\n** C\n** D\n"
    (let ((second (split-window-vertically)))
      (set-window-point second (point-max))
      (sommaire-test--heading "Two")
      (narrow-to-region (point-min) (point))
      (goto-char (point-min))
      (sommaire-test--idle)
      (should (equal (with-selected-window second (sommaire-test-header)) "  § One ▾2 › B"))
      (widen)
      (set-window-point second (point-min))
      (sommaire-test--heading "Two")
      (narrow-to-region (point) (point-max))
      (sommaire-test--idle)
      (should (equal (with-selected-window second (sommaire-test-header)) "  § Two ▾2")))))

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

(ert-deftest sommaire-jump-refuses-headings-that-change-during-the-reading ()
  "A revert or a process may change the headings while the reader chooses one.
Then the choice moves nothing, and no mark is left behind."
  (sommaire-test-with-org "* A\n** B\n** C\n"
    (let ((completing-read-function
           (lambda (&rest _)
             (save-excursion
               (goto-char (point-min))
               (insert "* Z\n** Y\n** X\n"))
             "C"))
          (start (point)))
      (should-error (sommaire-jump) :type 'user-error)
      (should (= (point) start))
      (should-not (mark t)))))

(ert-deftest sommaire-jump-survives-a-deep-document ()
  "A document chooses its depth, so comparing what two reads gave must not overflow.
The edit makes the second read another outline, and leaves the headings alone."
  (sommaire-test-with-buffer
      (progn
        (dotimes (level 200)
          (insert (make-string (1+ level) ?*) (format " H%d\n" level)))
        (org-mode)
        (goto-char (point-min)))
    (let ((completing-read-function
           (lambda (&rest _)
             (save-excursion
               (goto-char (point-max))
               (insert "Text.\n"))
             "H150")))
      (sommaire-jump '(4)))
    (should (looking-at "\\*+ H150"))))

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
    (sommaire-test--idle)
    (sommaire-test--fontify)
    (should (equal (mapcar #'cdr (sommaire-test--buttons))
                   '(" ▸ 3" " ▸ 2" " ▸ 2" " ▸ 2")))
    (should (equal (mapcar #'car (sommaire-test--buttons))
                   '("* Installation" "** straight.el"
                     "* TODO [#A] Usage [1/2] :manual:" "** Skins"))))
  (sommaire-test-with-fixture "normal" "md"
    (sommaire-test--idle)
    (sommaire-test--fontify)
    (should (equal (sommaire-test--buttons)
                   '(("Installation" . " ▸ 3") ("### straight.el" . " ▸ 2")
                     ("## Usage" . " ▸ 2") ("### Skins" . " ▸ 2"))))))

(ert-deftest sommaire-chain-has-no-button ()
  "A chain of single children has no anchor, so no button: acceptance 1."
  (dolist (extension '("org" "md"))
    (sommaire-test-with-fixture "chain" extension
      (sommaire-test--idle)
      (sommaire-test--fontify)
      (should-not (sommaire-test--buttons)))))

(ert-deftest sommaire-buttons-come-as-text-comes-into-view ()
  "No button stands beyond what shows, until `jit-lock' gets there."
  (sommaire-test-with-buffer (sommaire-test--far-document)
    (sommaire-test--with-lines-shown 20
      (sommaire-test--idle))
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
      (sommaire-test--idle)
      (should-not (member '("* Far" . " ▸ 2") (sommaire-test--buttons)))
      (search-forward "* Far")
      (set-window-start nil (pos-bol))
      (sommaire-test--idle)
      (should (member '("* Far" . " ▸ 2") (sommaire-test--buttons))))))

(ert-deftest sommaire-buttons-come-in-every-emacs-window-of-the-buffer ()
  "The timer places the buttons of what any Emacs window shows, selected or not."
  (sommaire-test-with-buffer (sommaire-test--far-document)
    (let ((near (selected-window))
          (far (split-window-vertically)))
      (set-window-start far (save-excursion
                              (search-forward "* Far")
                              (pos-bol)))
      (sommaire-test--with-lines-shown 20
        (sommaire-test--idle))
      (should (eq (selected-window) near))
      (should (equal (sommaire-test--buttons)
                     '(("* Near" . " ▸ 2") ("* Far" . " ▸ 2")))))))

(ert-deftest sommaire-buttons-wait-for-the-read-after-an-edit ()
  "Between an edit and the next read, places are old, and nothing goes on them."
  (sommaire-test-with-buffer (sommaire-test--far-document)
    (sommaire-test--with-lines-shown 20
      (sommaire-test--idle))
    (goto-char (point-min))
    (insert "New first line.\n")
    (sommaire-test--fontify)
    (should (= (length (sommaire-test--buttons)) 1))
    (sommaire-test--idle)
    (sommaire-test--fontify)
    (should (equal (mapcar #'cdr (sommaire-test--buttons)) '(" ▸ 2" " ▸ 2")))
    (should (member '("* Far" . " ▸ 2") (sommaire-test--buttons)))))

(ert-deftest sommaire-buttons-stay-out-of-what-is-not-asked ()
  "Text above what an Emacs window shows, or `jit-lock' asks for, gets no button."
  (sommaire-test-with-buffer (sommaire-test--far-document)
    (search-forward "* Far")
    (set-window-start nil (pos-bol))
    (sommaire-test--with-lines-shown 20
      (sommaire-test--idle))
    (should (equal (sommaire-test--buttons) '(("* Far" . " ▸ 2"))))))

(ert-deftest sommaire-buttons-stay-when-the-decision-stays ()
  "An edit elsewhere keeps the button itself, which has moved with the text."
  (sommaire-test-with-org "Text.\n* Near\n** One\n** Two\n"
    (sommaire-test--idle)
    (let ((button (car (sommaire-test--overlays 'after-string))))
      (goto-char (point-min))
      (insert "More text.\n")
      (sommaire-test--idle)
      (should (equal (sommaire-test--overlays 'after-string) (list button)))
      (should (equal (sommaire-test--buttons) '(("* Near" . " ▸ 2")))))))

(ert-deftest sommaire-buttons-stay-at-the-end-of-their-line ()
  "Text typed at a heading's end stays before its button, and a new line after it."
  (sommaire-test-with-org "* Near\n** One\n** Two\n"
    (sommaire-test--idle)
    (goto-char (point-min))
    (end-of-line)
    (insert " and more")
    (should (equal (sommaire-test--buttons) '(("* Near and more" . " ▸ 2"))))
    (insert "\nA line of text.")
    (sommaire-test--idle)
    (should (equal (sommaire-test--buttons) '(("* Near and more" . " ▸ 2"))))))

(ert-deftest sommaire-buttons-stay-on-their-heading ()
  "A line typed at a heading's start leaves the button on the heading alone."
  (sommaire-test-with-org "* Near\n** One\n** Two\n"
    (sommaire-test--idle)
    (goto-char (point-min))
    (insert "A line.\n")
    (sommaire-test--idle)
    (should (equal (sommaire-test--buttons) '(("* Near" . " ▸ 2"))))))

(ert-deftest sommaire-buttons-go-with-their-line-at-once ()
  "A button whose line is emptied goes then, and does not wait for the timer."
  (sommaire-test-with-org "* Near\n** One\n** Two\n"
    (sommaire-test--idle)
    (goto-char (point-min))
    (delete-region (point) (pos-eol))
    (should-not (sommaire-test--buttons))))

(ert-deftest sommaire-buttons-follow-a-changed-decision ()
  "A new anchor gets its button, a changed one a new number, and a lost one none."
  (sommaire-test-with-org "* One\n** A\n** B\n* Two\n** C\n"
    (sommaire-test--idle)
    (should (equal (sommaire-test--buttons) '(("* One" . " ▸ 2"))))
    ;; A second child makes "Two" worth a minitoc.
    (goto-char (point-max))
    (insert "** D\n")
    (sommaire-test--idle)
    (should (equal (sommaire-test--buttons) '(("* One" . " ▸ 2") ("* Two" . " ▸ 2"))))
    (insert "** E\n")
    (sommaire-test--idle)
    (should (equal (sommaire-test--buttons) '(("* One" . " ▸ 2") ("* Two" . " ▸ 3"))))
    ;; "One" loses a child, and so its minitoc.
    (goto-char (point-min))
    (search-forward "** A\n")
    (delete-region (match-beginning 0) (match-end 0))
    (sommaire-test--idle)
    (should (equal (sommaire-test--buttons) '(("* Two" . " ▸ 3"))))))

(ert-deftest sommaire-buttons-follow-narrowing ()
  "Under narrowing the anchors are those of the part: rule R6."
  (sommaire-test-with-fixture "narrowing" "org"
    (sommaire-test--idle)
    (sommaire-test--fontify)
    (should (member "* Usage" (mapcar #'car (sommaire-test--buttons))))
    (sommaire-test-narrow-to-usage "\\*")
    (sommaire-test--idle)
    ;; "Usage" is the root now, and the root is no anchor.
    (should-not (member "* Usage" (mapcar #'car (sommaire-test--buttons))))))

(ert-deftest sommaire-buttons-option-off-gives-none ()
  "With `sommaire-heading-buttons' nil, the mode leaves `jit-lock' alone."
  (let ((sommaire-heading-buttons nil))
    (sommaire-test-with-fixture "normal" "org"
      (should-not (memq #'sommaire--place-buttons jit-lock-functions))
      (sommaire-test--idle)
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
              (sommaire-test--idle)
              (should (equal (sommaire-test--buttons) '(("* Near" . " ▸ 2")))))
            (should-not (sommaire-test--buttons)))
        (kill-buffer clone)))))

(ert-deftest sommaire-mode-ends-without-a-trace-in-jit-lock ()
  "The buffer's `jit-lock' goes back to what it was when the mode ends."
  (with-temp-buffer
    (insert "* Top\n** A\n** B\n")
    (org-mode)
    (dolist (font-lock '(nil t))
      (ert-info ((format "font-lock %S" font-lock))
        (font-lock-mode (if font-lock 1 -1))
        (let ((before (list jit-lock-mode jit-lock-functions)))
          (should-not (memq #'sommaire--place-buttons jit-lock-functions))
          (sommaire-mode 1)
          (should (memq #'sommaire--place-buttons jit-lock-functions))
          (should jit-lock-mode)
          (sommaire-mode -1)
          (should (equal (list jit-lock-mode jit-lock-functions) before)))))))

(ert-deftest sommaire-mode-ends-without-an-overlay ()
  "Ending the mode removes every overlay, whatever the narrowing."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--idle)
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

(ert-deftest sommaire-inline-refuses-under-a-fold ()
  "A minitoc under a folded heading would not show, so opening one says so.
Org 9.6 on Emacs 29.1 leaves the button of a folded heading in view, so a click
on it would seem to do nothing, and redisplay is not there to see in batch.
What is open elsewhere stays open, and what is open there can still close."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "straight.el")
        (sommaire-toggle-inline)
        (let ((elsewhere (sommaire-test--overlays 'before-string)))
          (sommaire-test--heading "Usage")
          (sommaire-test--hide-subtree extension)
          (should-error (sommaire-toggle-inline) :type 'user-error)
          (should (equal (sommaire-test--overlays 'before-string) elsewhere))
          (goto-char (overlay-start (car elsewhere)))
          (should-not (invisible-p (point))))
        (outline-show-all)
        (sommaire-test--heading "Usage")
        (sommaire-toggle-inline)
        (sommaire-test--heading "Usage")
        (outline-hide-subtree)
        (sommaire-toggle-inline)
        (should-not (sommaire-test--overlays 'before-string))))))

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
    (should-error (sommaire-toggle-inline) :type 'user-error))
  ;; An anchor before point is not around it.
  (sommaire-test-with-org "* One\n** A\n** B\n* Two\n"
    (sommaire-test--heading "Two")
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
      (sommaire-test--idle)
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
        (sommaire-test--idle)
        (should (eq (overlay-get overlay 'before-string) text)))
      (goto-char (overlay-start overlay))
      (should (looking-at "Intro\\."))
      ;; Metadata typed at its place keep it after them: rule R5.
      (insert "DEADLINE: <2026-11-02 Mon>\n")
      (sommaire-test--idle)
      (goto-char (overlay-start overlay))
      (should (looking-at "Intro\\."))
      ;; A new child is a new entry.
      (search-forward "** B\n")
      (insert "** C\n")
      (sommaire-test--idle)
      (should (equal (substring-no-properties (overlay-get overlay 'before-string))
                     "  A\n  B\n  C\n"))
      ;; Its heading gone, it goes too.
      (goto-char (point-min))
      (search-forward "* Top\n")
      (delete-region (match-beginning 0) (match-end 0))
      (sommaire-test--idle)
      (should-not (sommaire-test--overlays 'before-string)))))

(ert-deftest sommaire-a-click-on-a-button-opens-its-heading ()
  "The button is a string, so a click reaches its keymap, and acts on its heading."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--idle)
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

(ert-deftest sommaire-a-click-on-an-entry-acts-in-its-emacs-window ()
  "A click in an Emacs window that is not selected moves point there, and selects it."
  (sommaire-test-with-fixture "normal" "org"
    (let ((clicked (selected-window))
          (other (split-window-vertically)))
      (sommaire-test--heading "Installation")
      (sommaire-toggle-inline)
      (let* ((text (overlay-get (car (sommaire-test--overlays 'before-string)) 'before-string))
             (click (sommaire-test--click (point) (cons text (string-search "Pandoc" text)))))
        (select-window other)
        (let ((start (point)))
          (sommaire-follow-inline click)
          (should (eq (selected-window) clicked))
          (should (looking-at "\\*+ Pandoc"))
          (should (= (window-point other) start)))))))

(ert-deftest sommaire-a-click-on-an-entry-refuses-an-old-list ()
  "A click after an edit that no read has seen moves nothing, and says so.
The minitoc then lists the new headings, and a click on it goes to its heading."
  (sommaire-test-with-org "* A\n** B\n** C\n"
    (sommaire-toggle-inline)
    (let* ((overlay (car (sommaire-test--overlays 'before-string)))
           (click-on-c (lambda ()
                         (let ((text (overlay-get overlay 'before-string)))
                           (sommaire-test--click (point) (cons text (string-search "C" text))))))
           (old-click (funcall click-on-c)))
      (insert "* Z\n** Y\n** X\n")
      (let ((start (point)))
        (should-error (sommaire-follow-inline old-click) :type 'user-error)
        (should (= (point) start)))
      (sommaire-follow-inline (funcall click-on-c))
      (should (= (line-number-at-pos) 6))
      (should (looking-at "\\*\\* C")))))

;;; The panel

(defun sommaire-test--panel-window ()
  "Return the side Emacs window of the selected frame, if there is one."
  (seq-find (lambda (window) (window-parameter window 'window-side))
            (window-list nil 'never)))

(defun sommaire-test--panel-buffers ()
  "Return the live buffers in the major mode of a panel."
  (seq-filter (lambda (buffer)
                (eq (buffer-local-value 'major-mode buffer) 'sommaire-panel-mode))
              (buffer-list)))

(defun sommaire-test--panel-lines ()
  "Return the lines that the side Emacs window shows."
  (with-current-buffer (window-buffer (sommaire-test--panel-window))
    (split-string (buffer-substring-no-properties (point-min) (point-max)) "\n" t)))

(defun sommaire-test--in-panel (keys)
  "Type KEYS in the side Emacs window, whose buffer is then the current one."
  (with-selected-window (sommaire-test--panel-window)
    (execute-kbd-macro (kbd keys))))

(defun sommaire-test--panel-row (title)
  "Select the side Emacs window, with point on its row of TITLE."
  (select-window (sommaire-test--panel-window))
  (goto-char (point-min))
  (re-search-forward (format "^[ ›]+%s$" (regexp-quote title)))
  (goto-char (pos-bol)))

(ert-deftest sommaire-acceptance-panel-shows-one-side-window ()
  "The panel is one narrow, dedicated side Emacs window, and the source stays selected."
  (sommaire-test-with-fixture "normal" "org"
    (let ((source (selected-window))
          (buffer (current-buffer)))
      (should-not (sommaire-test--panel-window))
      (should (= (length (window-list nil 'never)) 1))
      (sommaire-panel)
      (let ((panel (sommaire-test--panel-window)))
        (should (= (length (window-list nil 'never)) 2))
        (should (eq (selected-window) source))
        (should (eq (current-buffer) buffer))
        (should (window-dedicated-p panel))
        (should (eq (window-parameter panel 'window-side) 'right))
        (should (< (window-width panel) (window-width source))))
      (sommaire-test--idle)
      (should (eq (selected-window) source)))))

(ert-deftest sommaire-acceptance-panel-is-off-by-default ()
  "Off, nothing shows: no Emacs window, no buffer."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--idle)
    (should-not (sommaire-test--panel-window))
    (should-not (sommaire-test--panel-buffers))))

(ert-deftest sommaire-acceptance-panel-leaves-the-segment-as-it-is ()
  "The header-line segment is the same with the panel on as off, in any scope."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-test--idle)
    (let ((off (sommaire-test-header)))
      (sommaire-panel)
      (sommaire-test--idle)
      (should (equal (sommaire-test-header) off))
      (sommaire-test--in-panel "r +")
      (sommaire-test--idle)
      (should (equal (sommaire-test-header) off))
      (sommaire-panel)
      (sommaire-test--idle)
      (should (equal (sommaire-test-header) off)))))

(ert-deftest sommaire-panel-lists-the-scope-and-marks-the-current-entry ()
  "The panel names its root and scope, and lists the entries, the current one marked."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "Emacs")
        (sommaire-panel)
        (should (equal (sommaire-test--panel-lines)
                       '("Requirements" "section · depth 1" "› Emacs" "  Pandoc")))
        (with-current-buffer (window-buffer (sommaire-test--panel-window))
          (goto-char (point-min))
          (search-forward "Emacs")
          (should (eq (get-text-property (1- (point)) 'face) 'sommaire-current))
          (should (= (window-point (sommaire-test--panel-window)) (pos-bol)))
          (search-forward "Pandoc")
          (should-not (get-text-property (1- (point)) 'face)))))))

(ert-deftest sommaire-panel-indents-by-relative-depth ()
  "Each row sits as deep as it lies below the scope's root."
  (let ((sommaire-scope '(section . all)))
    (sommaire-test-with-fixture "normal" "org"
      (sommaire-test--heading "Native compilation")
      (sommaire-panel)
      (should (equal (cddr (sommaire-test--panel-lines))
                     '("  Emacs" "  › Native compilation" "    Tree-sitter" "  Pandoc"))))))

(ert-deftest sommaire-panel-says-when-there-is-no-section ()
  "With no section there is nothing to list in that scope."
  (sommaire-test-with-fixture "chain" "org"
    (sommaire-test--heading "Paragraph")
    (sommaire-panel)
    (should (equal (sommaire-test--panel-lines) '("No section here" "section · depth 1")))))

(ert-deftest sommaire-panel-names-a-root-without-a-title ()
  "A document with no title still has a root to name."
  (let ((sommaire-scope '(document . 1)))
    (sommaire-test-with-fixture "untitled" "org"
      (sommaire-panel)
      (should (equal (car (sommaire-test--panel-lines)) "Document")))))

(ert-deftest sommaire-panel-dims-an-archived-entry ()
  "An archived entry is listed, dimmed, and has nothing below it."
  (let ((sommaire-scope '(document . all)))
    (sommaire-test-with-fixture "archive" "org"
      (sommaire-panel)
      (with-current-buffer (window-buffer (sommaire-test--panel-window))
        (goto-char (point-min))
        (search-forward "Attic")
        (should (eq (get-text-property (1- (point)) 'face) 'sommaire-archived))
        (forward-line 1)
        (should (looking-at "  Only archives"))))))

(ert-deftest sommaire-acceptance-panel-follows-point-through-the-timer ()
  "A section scope lists the section's direct children, then the next section's."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "Requirements")
        (sommaire-panel)
        (should (equal (cddr (sommaire-test--panel-lines)) '("  Emacs" "  Pandoc")))
        (sommaire-test--heading "Skins")
        (should (equal (cddr (sommaire-test--panel-lines)) '("  Emacs" "  Pandoc")))
        (sommaire-test--idle)
        (should (equal (cddr (sommaire-test--panel-lines)) '("  XIX" "  Briefing")))))))

(ert-deftest sommaire-panel-redraws-only-when-the-decision-changes ()
  "The panel's text changes when what it lists or marks does, and at no other time."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-panel)
    (let* ((panel (window-buffer (sommaire-test--panel-window)))
           (tick (buffer-modified-tick panel)))
      (sommaire-test--idle)
      (should (= (buffer-modified-tick panel) tick))
      ;; Deeper in the same entry, what the panel shows is the same.
      (sommaire-test--heading "Native compilation")
      (sommaire-test--idle)
      (should (= (buffer-modified-tick panel) tick))
      (should (equal (sommaire-test--panel-lines)
                     '("Requirements" "section · depth 1" "› Emacs" "  Pandoc")))
      (sommaire-test--heading "Pandoc")
      (sommaire-test--idle)
      (should-not (= (buffer-modified-tick panel) tick))
      (should (equal (cddr (sommaire-test--panel-lines)) '("  Emacs" "› Pandoc")))
      ;; Its Emacs window, not selected, goes to the new current entry.
      (with-current-buffer panel
        (goto-char (window-point (sommaire-test--panel-window)))
        (should (looking-at "› Pandoc"))))))

(ert-deftest sommaire-acceptance-panel-keys-change-the-scope ()
  "+, - and r change what the panel lists, in document order."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (sommaire-test--heading "Emacs")
        (sommaire-panel)
        (sommaire-test--in-panel "+")
        (should (equal (sommaire-test--panel-lines)
                       '("Requirements" "section · depth all"
                         "› Emacs" "    Native compilation" "    Tree-sitter" "  Pandoc")))
        (sommaire-test--in-panel "-")
        (should (equal (cdr (sommaire-test--panel-lines))
                       '("section · depth 1" "› Emacs" "  Pandoc")))
        (sommaire-test--in-panel "r")
        (should (equal (cdr (sommaire-test--panel-lines))
                       '("document · depth 1" "› Installation" "  Usage")))
        (sommaire-test--in-panel "+")
        (should (equal (cdr (sommaire-test--panel-lines))
                       '("document · depth 2"
                         "  Installation" "  › Requirements" "    Nix" "    straight.el"
                         "  Usage" "    Live preview" "    Skins")))
        (sommaire-test--in-panel "r")
        (should (equal (cdr (sommaire-test--panel-lines))
                       '("section · depth 2"
                         "› Emacs" "    Native compilation" "    Tree-sitter" "  Pandoc")))))))

(ert-deftest sommaire-panel-label-follows-the-scope ()
  "A new scope shows in the panel, even when it lists the same entries."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "straight.el")
    (sommaire-panel)
    (should (equal (cdr (sommaire-test--panel-lines))
                   '("section · depth 1" "  The recipe" "  A local clone")))
    (sommaire-test--in-panel "+")
    (should (equal (cdr (sommaire-test--panel-lines))
                   '("section · depth all" "  The recipe" "  A local clone")))))

(ert-deftest sommaire-panel-is-quiet ()
  "The panel has no mode line and no cursor of its own, and does not wrap its lines."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-panel)
    (with-current-buffer (window-buffer (sommaire-test--panel-window))
      (should truncate-lines)
      (should-not mode-line-format)
      (should-not cursor-in-non-selected-windows)
      (should buffer-read-only))))

(ert-deftest sommaire-panel-depth-stops-at-both-ends ()
  "The depth stays at 1 going down, and turns to `all' at the deepest level."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-panel)
    (sommaire-test--in-panel "-")
    (should (equal sommaire-scope '(section . 1)))
    (sommaire-test--in-panel "+ +")
    (should (equal sommaire-scope '(section . all)))
    (sommaire-test--in-panel "-")
    (should (equal sommaire-scope '(section . 1)))
    (setq-local sommaire-scope '(document . 1))
    (dolist (depth '(2 3 all all))
      (sommaire-test--in-panel "+")
      (should (equal sommaire-scope (cons 'document depth))))
    (dolist (depth '(3 2 1 1))
      (sommaire-test--in-panel "-")
      (should (equal sommaire-scope (cons 'document depth))))
    ;; A depth beyond the deepest level counts from it.
    (setq-local sommaire-scope '(document . 9))
    (sommaire-test--in-panel "-")
    (should (equal sommaire-scope '(document . 3)))))

(ert-deftest sommaire-panel-depth-moves-by-itself-when-nothing-is-listed ()
  "With no section there is no deepest level, so the depth stays a number.
It waits for the next section, or the document that `r' goes to, and lists that
many levels there: one `+' never means every level."
  (sommaire-test-with-fixture "chain" "org"
    (sommaire-test--heading "Paragraph")
    (sommaire-panel)
    (sommaire-test--in-panel "-")
    (should (equal sommaire-scope '(section . 1)))
    (sommaire-test--in-panel "+")
    (should (equal sommaire-scope '(section . 2)))
    (should (equal (sommaire-test--panel-lines) '("No section here" "section · depth 2")))
    (sommaire-test--in-panel "+")
    (should (equal sommaire-scope '(section . 3)))
    (sommaire-test--in-panel "-")
    (should (equal sommaire-scope '(section . 2)))
    (sommaire-test--in-panel "r")
    (should (equal sommaire-scope '(document . 2)))
    (should (equal (cdr (sommaire-test--panel-lines))
                   '("document · depth 2" "  Subtitle" "  › Section")))
    ;; `all' has no number to count from: nothing lists more, and one fewer is the least.
    (sommaire-test--in-panel "r")
    (setq-local sommaire-scope '(section . all))
    (sommaire-test--in-panel "+")
    (should (equal sommaire-scope '(section . all)))
    (sommaire-test--in-panel "-")
    (should (equal sommaire-scope '(section . 1)))))

(ert-deftest sommaire-acceptance-panel-scope-is-remembered-for-that-buffer ()
  "What the keys choose holds in that buffer, through closing, and in no other."
  (let ((other (generate-new-buffer "sommaire-test-other")))
    (unwind-protect
        (sommaire-test-with-fixture "normal" "org"
          (sommaire-test--heading "Emacs")
          (sommaire-panel)
          (sommaire-test--in-panel "r +")
          (should (equal sommaire-scope '(document . 2)))
          (should (equal (buffer-local-value 'sommaire-scope other) '(section . 1)))
          (should (equal (default-value 'sommaire-scope) '(section . 1)))
          (sommaire-test--in-panel "q")
          (should (equal sommaire-scope '(document . 2)))
          (sommaire-panel)
          (should (equal (cadr (sommaire-test--panel-lines)) "document · depth 2"))
          ;; The jump reads the same scope.
          (should (member "Usage" (sommaire-test--offered "M-g m"))))
      (kill-buffer other))))

(ert-deftest sommaire-panel-scope-is-the-option-until-changed ()
  "Until the reader changes it, a buffer has the option's scope."
  (let ((sommaire-scope '(document . 1)))
    (sommaire-test-with-fixture "normal" "org"
      (sommaire-panel)
      (should (equal (cdr (sommaire-test--panel-lines))
                     '("document · depth 1" "  Installation" "  Usage"))))))

(ert-deftest sommaire-indirect-clones-have-their-own-scope ()
  "A clone starts from the scope of its base, and each keeps its own from then on."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-panel)
    (sommaire-test--in-panel "r")
    (let ((clone (clone-indirect-buffer nil nil))
          (base (current-buffer))
          (panel (window-buffer (sommaire-test--panel-window))))
      (unwind-protect
          (progn
            (with-current-buffer clone
              (should sommaire-mode)
              (should (equal sommaire-scope '(document . 1)))
              ;; It has no panel, though it has the variable.
              (should-not (sommaire--own-panel))
              (setq-local sommaire-scope '(section . 2))
              (sommaire--stop))
            (should (buffer-live-p panel))
            (should (equal sommaire-scope '(document . 1)))
            (should (eq (current-buffer) base)))
        (kill-buffer clone)))))

(ert-deftest sommaire-acceptance-panel-return-moves-point-in-the-source ()
  "RET on an entry moves point in the source, which it leaves selected."
  (dolist (extension '("org" "md"))
    (ert-info (extension)
      (sommaire-test-with-fixture "normal" extension
        (let ((source (selected-window)))
          (sommaire-test--heading "Emacs")
          (sommaire-panel)
          (select-window (sommaire-test--panel-window))
          (goto-char (point-min))
          (search-forward "Pandoc")
          (execute-kbd-macro (kbd "RET"))
          (should (eq (selected-window) source))
          (should (eq (current-buffer) sommaire-test--buffer))
          (should (looking-at "[*#]+ Pandoc")))))))

(ert-deftest sommaire-panel-return-on-its-title-does-nothing ()
  "RET where no entry is moves nothing, and stays where it is."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (let ((start (point)))
      (sommaire-panel)
      (let ((panel (sommaire-test--panel-window)))
        (select-window panel)
        (goto-char (point-min))
        (execute-kbd-macro (kbd "RET"))
        (should (eq (selected-window) panel))
        (select-window (next-window panel 'never)))
      (should (= (point) start)))))

(ert-deftest sommaire-panel-a-click-goes-to-the-entry ()
  "A click on an entry goes to its heading, though the panel is not selected."
  (sommaire-test-with-fixture "normal" "org"
    (let ((source (selected-window)))
      (sommaire-test--heading "Emacs")
      (sommaire-panel)
      (let* ((panel (sommaire-test--panel-window))
             (position (with-current-buffer (window-buffer panel)
                         (save-excursion
                           (goto-char (point-min))
                           (search-forward "Pandoc")
                           (1- (point)))))
             (last-command-event
              (list 'mouse-1 (list panel position '(0 . 0) 0 nil position))))
        (with-current-buffer (window-buffer panel)
          (should (eq (key-binding [mouse-1]) #'sommaire-panel-jump))
          (call-interactively #'sommaire-panel-jump)))
      (should (eq (selected-window) source))
      (should (looking-at "\\*+ Pandoc")))))

(ert-deftest sommaire-panel-return-shows-a-source-that-no-window-shows ()
  "RET finds an Emacs window for a source that none shows, selects it, and goes there."
  (let ((other (generate-new-buffer "sommaire-test-other")))
    (unwind-protect
        (sommaire-test-with-fixture "normal" "org"
          (let ((source (selected-window)))
            (sommaire-test--heading "Emacs")
            (sommaire-panel)
            (set-window-buffer source other)
            (should-not (get-buffer-window sommaire-test--buffer))
            (sommaire-test--panel-row "Pandoc")
            (execute-kbd-macro (kbd "RET"))
            (should (eq (window-buffer (selected-window)) sommaire-test--buffer))
            (should (eq (current-buffer) sommaire-test--buffer))
            (should (looking-at "\\*+ Pandoc"))))
      (kill-buffer other))))

(ert-deftest sommaire-panel-return-refuses-rows-of-other-headings ()
  "RET after an edit that no read has seen moves nothing, and says so.
The timer waits for idle time, and an id counts headings.  The panel stays
selected, redrawn, and its rows then hold."
  (sommaire-test-with-org "* A\n** B\n** C\n"
    (let ((source (selected-window)))
      (sommaire-panel)
      (insert "* Z\n** Y\n** X\n")
      (let ((start (point)))
        (sommaire-test--panel-row "C")
        (let ((panel (selected-window)))
          (should-error (execute-kbd-macro (kbd "RET")) :type 'user-error)
          (should (eq (selected-window) panel))
          (should (= (window-point source) start))
          (should (equal (cddr (sommaire-test--panel-lines)) '("  B" "  C")))))
      (sommaire-test--panel-row "C")
      (execute-kbd-macro (kbd "RET"))
      (should (eq (selected-window) source))
      (should (= (line-number-at-pos) 6))
      (should (looking-at "\\*\\* C")))))

(ert-deftest sommaire-panel-return-refuses-when-headings-are-gone ()
  "With fewer headings, an old row's id may be no id at all."
  (sommaire-test-with-org "* A\n** B\n** C\n** D\n"
    (sommaire-panel)
    (search-forward "** B\n")
    (delete-region (match-beginning 0) (match-end 0))
    (sommaire-test--panel-row "D")
    (should-error (execute-kbd-macro (kbd "RET")) :type 'user-error)
    (should (equal (cddr (sommaire-test--panel-lines)) '("› C" "  D")))))

(ert-deftest sommaire-panel-return-refuses-after-a-heading-moved ()
  "Moving a heading keeps their number, and an old row's id names another one."
  (sommaire-test-with-org "* A\n** B\n** C\n"
    (sommaire-panel)
    (save-excursion
      (search-forward "** B\n")
      (delete-region (match-beginning 0) (match-end 0))
      (goto-char (point-max))
      (insert "** B\n"))
    (sommaire-test--panel-row "C")
    (should-error (execute-kbd-macro (kbd "RET")) :type 'user-error)
    (should (equal (cddr (sommaire-test--panel-lines)) '("  C" "  B")))
    (sommaire-test--panel-row "C")
    (execute-kbd-macro (kbd "RET"))
    (should (= (line-number-at-pos) 2))))

(ert-deftest sommaire-panel-return-tells-a-heading-from-its-copy ()
  "A copy above gives an old row's id the same title, and still another heading."
  (sommaire-test-with-org "* A\n** B\n** C\n"
    (sommaire-panel)
    (insert "* A\n** B\n** C\n")
    (sommaire-test--panel-row "C")
    (should-error (execute-kbd-macro (kbd "RET")) :type 'user-error)
    (sommaire-test--panel-row "C")
    (execute-kbd-macro (kbd "RET"))
    (should (= (line-number-at-pos) 6))))

(ert-deftest sommaire-panel-return-follows-an-edit-of-the-text ()
  "An edit that leaves the headings alone moves no id, so RET goes at once."
  (sommaire-test-with-org "* A\nText.\n** B\n** C\n"
    (sommaire-panel)
    (forward-line 1)
    (insert "More text.\n")
    (sommaire-test--panel-row "C")
    (execute-kbd-macro (kbd "RET"))
    (should (looking-at "\\*\\* C"))))

(ert-deftest sommaire-panel-return-holds-when-the-rows-stayed-the-same ()
  "A new heading below changes no row: a read makes the rows good again, drawn or not."
  (sommaire-test-with-org "* A\n** B\n** C\n"
    (let ((source (selected-window))
          (add-heading (lambda ()
                         (save-excursion
                           (goto-char (point-max))
                           (insert "* New\n")))))
      (sommaire-panel)
      (funcall add-heading)
      (sommaire-test--panel-row "C")
      (should-error (execute-kbd-macro (kbd "RET")) :type 'user-error)
      (execute-kbd-macro (kbd "RET"))
      (should (eq (selected-window) source))
      (should (looking-at "\\*\\* C"))
      ;; Seen by the timer, an edit needs no refusal at all.
      (goto-char (point-min))
      (funcall add-heading)
      (sommaire-test--idle)
      (sommaire-test--panel-row "C")
      (execute-kbd-macro (kbd "RET"))
      (should (eq (selected-window) source))
      (should (looking-at "\\*\\* C")))))

(ert-deftest sommaire-a-click-on-the-segment-shows-the-panel ()
  "The segment's keymap takes a click to the panel, and a second click closes it."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-test--idle)
    (let* ((segment (cdr (assq (selected-window) sommaire--segments)))
           (command (lookup-key (get-text-property 0 'keymap segment) [header-line mouse-1])))
      (should (eq command #'sommaire-panel))
      ;; A click on another Emacs window's header line acts on that window.
      (should (equal (interactive-form command) '(interactive "@")))
      (call-interactively command)
      (should (sommaire-test--panel-window))
      (call-interactively command)
      (should-not (sommaire-test--panel-window))
      (should-not (sommaire-test--panel-buffers)))))

(ert-deftest sommaire-acceptance-panel-q-leaves-nothing ()
  "q leaves no Emacs window, no buffer and no extra timer, and the source selected."
  (sommaire-test-with-fixture "normal" "org"
    (let ((timers (length timer-idle-list))
          (source (selected-window)))
      (sommaire-panel)
      (should (= (length timer-idle-list) timers))
      (select-window (sommaire-test--panel-window))
      (execute-kbd-macro (kbd "q"))
      (should (eq (selected-window) source))
      (should-not (sommaire-test--panel-window))
      (should-not (sommaire-test--panel-buffers))
      (should (= (length timer-idle-list) timers))
      (should sommaire-mode))))

(ert-deftest sommaire-acceptance-panel-ends-with-the-mode ()
  "Ending the mode leaves no Emacs window, no buffer and no timer of its own."
  (let ((timers (length timer-idle-list)))
    (sommaire-test-with-fixture "normal" "org"
      (sommaire-panel)
      (sommaire-mode -1)
      (should-not (sommaire-test--panel-window))
      (should-not (sommaire-test--panel-buffers))
      (should (= (length timer-idle-list) timers)))))

(ert-deftest sommaire-panel-ends-with-its-source ()
  "Killing the source takes the panel along."
  (let ((buffer (generate-new-buffer "sommaire-test-other")))
    (save-window-excursion
      (set-window-buffer nil buffer)
      (with-current-buffer buffer
        (insert "* Top\n** A\n** B\n")
        (org-mode)
        (sommaire-mode 1)
        (sommaire-panel))
      (should (sommaire-test--panel-window))
      (kill-buffer buffer)
      (should-not (sommaire-test--panel-window))
      (should-not (sommaire-test--panel-buffers)))))

(ert-deftest sommaire-panel-opens-again-after-its-window-is-gone ()
  "When the reader deleted its Emacs window, the command shows it again, not a second."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-panel)
    (delete-window (sommaire-test--panel-window))
    (should (= (length (sommaire-test--panel-buffers)) 1))
    (sommaire-panel)
    (should (sommaire-test--panel-window))
    (should (= (length (sommaire-test--panel-buffers)) 1))))

(ert-deftest sommaire-panel-opens-again-after-its-buffer-is-killed ()
  "When the reader killed its buffer, the mode goes on, and the command makes a new one."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-panel)
    (kill-buffer (window-buffer (sommaire-test--panel-window)))
    (should-not (sommaire-test--panel-window))
    (sommaire-test--heading "Emacs")
    (sommaire-test--idle)
    (should-not (sommaire-test--panel-buffers))
    (sommaire-panel)
    (should (= (length (sommaire-test--panel-buffers)) 1))))

(ert-deftest sommaire-panel-says-when-there-is-no-room ()
  "When no side window can be made, it says so and leaves no buffer behind."
  (sommaire-test-with-fixture "normal" "org"
    (cl-letf (((symbol-function 'display-buffer) (lambda (&rest _) nil)))
      (should-error (sommaire-panel) :type 'user-error))
    (should-not (sommaire-test--panel-buffers))))

(ert-deftest sommaire-panel-leaves-another-side-window-alone ()
  "Another tool's Emacs window on the same side shows its buffer before, during and after."
  (dolist (slot '(-1 0 1))
    (ert-info ((format "slot %d" slot))
      (let ((foreign (generate-new-buffer "sommaire-test-foreign")))
        (unwind-protect
            (sommaire-test-with-fixture "normal" "org"
              (let ((window (display-buffer foreign `(display-buffer-in-side-window
                                                      (side . right) (slot . ,slot)))))
                (sommaire-panel)
                (let ((panel (get-buffer-window (car (sommaire-test--panel-buffers)))))
                  (should panel)
                  (should-not (eq panel window))
                  (should (eq (window-parameter panel 'window-side) 'right)))
                (should (eq (window-buffer window) foreign))
                (sommaire-panel)
                (should-not (sommaire-test--panel-buffers))
                (should (window-live-p window))
                (should (eq (window-buffer window) foreign))))
          (kill-buffer foreign))))))

(ert-deftest sommaire-panel-needs-the-mode ()
  "Without the mode no timer would follow point, so no panel is made."
  (with-temp-buffer
    (should-error (sommaire-panel) :type 'user-error)
    (should-not (sommaire-test--panel-buffers))))

;;; A scope set by hand

(defconst sommaire-test--no-scopes
  '((section . 0) (section . -1) (section . 1.5) (section . "1") (section)
    (document . 0) (other . 1) (1 . section) section 3 nil)
  "Values that `sommaire-scope' can hold and that are no scope.")

(ert-deftest sommaire-scope-option-takes-only-scopes ()
  "Customize takes a root and a positive depth, or `all', and nothing else."
  (let ((type (widget-convert (custom-variable-type 'sommaire-scope))))
    (dolist (scope '((section . 1) (section . 7) (document . 2) (section . all) (document . all)))
      (ert-info ((format "%S" scope))
        (should (widget-apply type :match scope))))
    (dolist (scope sommaire-test--no-scopes)
      (ert-info ((format "%S" scope))
        (should-not (widget-apply type :match scope))))))

(ert-deftest sommaire-commands-refuse-what-is-no-scope ()
  "The jump and the panel say so and leave nothing behind, and the timer stays quiet.
C-u gives a scope of its own, so it needs none."
  (dolist (scope sommaire-test--no-scopes)
    (ert-info ((format "%S" scope))
      (sommaire-test-with-fixture "normal" "org"
        (sommaire-test--heading "Emacs")
        (setq-local sommaire-scope scope)
        (should-error (sommaire-jump) :type 'user-error)
        (should-error (sommaire-jump 2) :type 'user-error)
        (should-error (sommaire-panel) :type 'user-error)
        (should-not (sommaire-test--panel-buffers))
        (should-not (sommaire-test--panel-window))
        (sommaire-test--idle)
        (should (member "Usage" (sommaire-test--offered "C-u M-g m")))))))

(ert-deftest sommaire-panel-keeps-what-it-shows-under-what-is-no-scope ()
  "The timer stays quiet and the panel as it was, its keys say why, and q still closes."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-panel)
    (let ((lines (sommaire-test--panel-lines)))
      (setq-local sommaire-scope '(section . 0))
      (sommaire-test--heading "Skins")
      (sommaire-test--idle)
      (should (equal (sommaire-test--panel-lines) lines))
      (dolist (key '("+" "-" "r"))
        (ert-info (key)
          (should-error (sommaire-test--in-panel key) :type 'user-error)
          (should (equal sommaire-scope '(section . 0)))))
      (sommaire-test--in-panel "q")
      (should-not (sommaire-test--panel-window))
      (should-not (sommaire-test--panel-buffers)))))

(ert-deftest sommaire-timer-hides-only-a-refusal ()
  "Any other error in the panel's drawing is a defect, and reaches the timer's handler."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-panel)
    (cl-letf (((symbol-function 'sommaire-rules-panel) (lambda (&rest _) (error "A defect"))))
      (should-error (sommaire--tick)))))

(ert-deftest sommaire-panel-leaves-no-buffer-when-its-first-read-fails ()
  "An error while the panel is made leaves no hidden buffer for the mode to carry."
  (sommaire-test-with-fixture "normal" "org"
    (cl-letf (((symbol-function 'sommaire-org-outline) (lambda () (error "Unreadable"))))
      (should-error (sommaire-panel)))
    (should-not (sommaire-test--panel-buffers))
    (should-not (sommaire-test--panel-window))
    (sommaire-panel)
    (should (= (length (sommaire-test--panel-buffers)) 1))))

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

(ert-deftest sommaire-timer-reads-only-what-an-emacs-window-shows ()
  "A buffer with the mode that no Emacs window shows is not read."
  (sommaire-test-with-fixture "normal" "org"
    (with-temp-buffer
      (set-window-buffer nil (current-buffer))
      (should (= (sommaire-test--counting-reads (sommaire-test--idle)) 0)))
    (set-window-buffer nil sommaire-test--buffer)
    (should (= (sommaire-test--counting-reads (sommaire-test--idle)) 1))))

(ert-deftest sommaire-timer-reads-each-buffer-once ()
  "However many Emacs windows show a buffer it is read once, and a key stops them all."
  (let ((other (generate-new-buffer "sommaire-test-other")))
    (unwind-protect
        (sommaire-test-with-fixture "normal" "org"
          (split-window-vertically)
          (let ((third (split-window-vertically)))
            (should (= (sommaire-test--counting-reads (sommaire-test--idle)) 1))
            (with-current-buffer other
              (sommaire-mode 1))
            (set-window-buffer third other)
            (should (= (sommaire-test--counting-reads (sommaire-test--idle)) 2))
            (should (= 0 (let ((unread-command-events (list ?a)))
                           (sommaire-test--counting-reads (sommaire-test--idle)))))))
      (kill-buffer other))))

(ert-deftest sommaire-timer-reads-the-selected-buffer-first ()
  "A key stops the reads, so what the reader looks at comes before the rest."
  (let* ((other (generate-new-buffer "sommaire-test-other"))
         (read nil)
         (note (lambda (&rest _) (push (current-buffer) read))))
    (advice-add 'sommaire-org-outline :before note)
    (advice-add 'sommaire-markdown-outline :before note)
    (unwind-protect
        (sommaire-test-with-fixture "normal" "org"
          (let ((second (split-window-vertically)))
            (with-current-buffer other
              (sommaire-mode 1))
            (set-window-buffer second other)
            (sommaire-test--idle)
            (should (equal read (list other sommaire-test--buffer)))
            (setq read nil)
            (select-window second)
            (sommaire-test--idle)
            (should (equal read (list sommaire-test--buffer other)))))
      (advice-remove 'sommaire-org-outline note)
      (advice-remove 'sommaire-markdown-outline note)
      (kill-buffer other))))

(ert-deftest sommaire-panel-stays-true-while-the-reader-is-in-it ()
  "The timer reads what Emacs windows show, whichever is selected, so rows stay good."
  (sommaire-test-with-org "* A\n** B\n** C\n"
    (sommaire-panel)
    (sommaire-test--panel-row "C")
    (with-current-buffer sommaire-test--buffer
      (save-excursion
        (goto-char (point-max))
        (insert "** D\n")))
    (sommaire-test--idle)
    (should (equal (cddr (sommaire-test--panel-lines)) '("  B" "  C" "  D")))))

(ert-deftest sommaire-a-pending-key-keeps-what-is-shown ()
  "With a key pending, the timer does not read, and what is shown stays."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-test--idle)
    (sommaire-test--heading "Skins")
    (let ((buttons (sommaire-test--buttons)))
      (should buttons)
      (should (= 0 (let ((unread-command-events (list ?a)))
                     (sommaire-test--counting-reads (sommaire-test--idle)))))
      (should (equal (sommaire-test--buttons) buttons)))
    (should (equal (sommaire-test-header) "  Installation › § Requirements ▾2 › Emacs"))
    (sommaire-test--idle)
    (should (equal (sommaire-test-header) "  Usage › § Skins ▾2"))))

(ert-deftest sommaire-a-key-during-the-read-keeps-what-is-shown ()
  "A key that arrives while the adapter reads ends the read, and what is shown stays.
A key sets `quit-flag' to `throw-on-input', which is non-nil only in
`while-no-input': without it, the read below would run to its end."
  (sommaire-test-with-fixture "normal" "org"
    (sommaire-test--heading "Emacs")
    (sommaire-test--idle)
    (let ((outline (sommaire-org-outline)))
      (sommaire-test--heading "Skins")
      (cl-letf (((symbol-function 'sommaire-org-outline)
                 (lambda ()
                   (setq quit-flag throw-on-input)
                   outline)))
        (sommaire-test--idle)))
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
                    (sommaire-test--idle)
                    (insert "x")
                    (sommaire-test--idle)
                    (delete-char -1)
                    (sommaire-test--idle))
                   0))
        (should (= (length messages) 1))
        ;; The timer may be speaking of a buffer that is not the selected one.
        (should (string-search (buffer-name) (car messages)))
        (should (equal (sommaire-test-header) "  "))
        ;; Narrowed, the part is small enough, and is read.
        (narrow-to-region (point-min) (+ (point-min) 22))
        (goto-char (point-min))
        (should (= (sommaire-test--counting-reads (sommaire-test--idle)) 1))
        (should (equal (length messages) 1))
        (should (string-prefix-p "  § Small ▾2" (sommaire-test-header)))
        ;; Too large again, it is said again, once.
        (widen)
        (should (= (sommaire-test--counting-reads
                    (sommaire-test--idle)
                    (sommaire-test--idle))
                   0))
        (should (= (length messages) 2))))))

(ert-deftest sommaire-commands-blame-the-size-of-a-part-too-large ()
  "After the notice, what finds no heading says that the buffer is too large, and to narrow.
It blames no scope, as C-u would fail the same way, and no heading: rule R1 has
not looked.  Once the part is small enough, the size is no longer the reason."
  (pcase-dolist (`(,text . ,mode) '(("* Small\n** One\n** Two\n" . org-mode)
                                    ("# Small\n\n## One\n\n## Two\n\n" . fundamental-mode)))
    (ert-info ((symbol-name mode))
      (sommaire-test-with-buffer
          (progn
            (insert text)
            (sommaire-test-insert-text sommaire-rules-largest-part)
            (funcall mode)
            (goto-char (point-min)))
        (sommaire-test--idle)
        (let ((refusal (lambda (function &rest arguments)
                         (error-message-string
                          (should-error (apply function arguments) :type 'user-error))))
              (too-large (concat "\\`" (regexp-quote (buffer-name))
                                 " is too large to read; narrow to a part of it\\'")))
          (dolist (argument '(nil (4) 2))
            (ert-info ((format "%S" argument))
              (should (string-match-p too-large (funcall refusal #'sommaire-jump argument)))))
          (should (string-match-p too-large (funcall refusal #'sommaire-toggle-inline)))
          (sommaire-panel)
          (should (equal (sommaire-test--panel-lines)
                         '("Too large: narrow to a part" "section · depth 1")))
          (sommaire-test--in-panel "r")
          (should (equal (sommaire-test--panel-lines)
                         '("Too large: narrow to a part" "document · depth 1")))
          (sommaire-test--in-panel "r")
          ;; A small part with no heading has the same decision, but not the same reason.
          (narrow-to-region (+ (point-min) (length text)) (+ (point-min) (length text) 5))
          (sommaire-test--idle)
          (should (equal (car (sommaire-test--panel-lines)) "No section here"))
          (should (string-prefix-p "No heading in this scope"
                                   (funcall refusal #'sommaire-jump)))
          (should (string-prefix-p "No heading around point"
                                   (funcall refusal #'sommaire-toggle-inline)))
          (widen)
          (narrow-to-region (point-min) (+ (point-min) (length text)))
          (goto-char (point-min))
          (sommaire-test--idle)
          (should (equal (car (sommaire-test--panel-lines)) "Small")))))))

(ert-deftest sommaire-mode-reads-org-and-anything-else-as-markdown ()
  "An Org buffer goes to the Org adapter, and any other to the Markdown scanner."
  (sommaire-test-with-buffer
      (progn
        (insert "# Top\n\n## A\n\n## B\n")
        (goto-char (point-min)))
    (sommaire-test--idle)
    (should (equal (sommaire-test-header) "  § Top ▾2")))
  (sommaire-test-with-org "* Top\n** A\n** B\n"
    (sommaire-test--idle)
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

(ert-deftest sommaire-mode-timer-waits-as-the-option-says ()
  "The timer repeats when idle, after `sommaire-idle-delay', by default 0.4 s."
  (should (equal (default-value 'sommaire-idle-delay) 0.4))
  (let ((sommaire-idle-delay 7))
    (sommaire-test-with-fixture "normal" "org"
      (should (memq sommaire--timer timer-idle-list))
      (should (= (time-convert (timer--time sommaire--timer) 'integer) 7))
      (should (timer--repeat-delay sommaire--timer)))))

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
      (sommaire-test--idle)
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
