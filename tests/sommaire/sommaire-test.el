;;; sommaire-test.el --- The surfaces of sommaire  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: plan 005, acceptance 3, 4, and "For step 5" in its notes: what `sommaire-mode' draws from the decisions of
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
