;;; imprimeur-menu-test.el --- Tests of the menu of skins  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 029).  `M-g s' opens a menu drawn from the registry: one key per
;; skin, derived from its name or named by its :menu-key, whatever the order of loading,
;; with the skin shown marked; below, one key per option of that skin, which cycles its
;; registered values.  A key changes the page at once, with no reload, and the menu stays
;; open and shows the new state, with the entry to keep in `imprimeur-skin-options'.  With
;; no session it says so rather than opening; a skin with no options shows none.  Loading
;; imprimeur does not load transient.  The two commands by completion stay.
;;
;; The expected keys of the seven skins are by hand: their names, and that XVII, XVIII and
;; XIX go by their century.  Keys are pressed through a keyboard macro, so transient's
;; own map and hooks run; its buffer is what a reader sees.

;;; Code:

(require 'ert)
(require 'seq)
(require 'imprimeur)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-http)
(require 'repo-test-helpers)

(defconst imprimeur-menu-test-buffer " *transient*"
  "The buffer of the menu.")

(defconst imprimeur-menu-test-tone
  '(tone :label "Tone" :default "soft"
         :choices (("soft" . "Soft") ("loud" . "Loud") ("dull" . "Dull")))
  "An option of three values, with labels that its identifiers are not.")

(defmacro imprimeur-menu-test-with (spec &rest body)
  "Run BODY in a source with a session, shown in the selected Emacs window.
SPEC is (STREAM): an open event stream of its page, which is shown in the skin
`base'.  The skins alpha, with the options tone and size, beta, with none, and
gamma, which names its key, are registered."
  (declare (indent 1))
  `(let* ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
          (imprimeur-skin 'base)
          (imprimeur-pandoc-program imprimeur-test-fake-pandoc)
          (imprimeur-browser-program imprimeur-test-fake-browser)
          (root (repo-test-git-tree '(("doc.org" . "Hello\n") ("skin.css" . "/* A file. */\n"))))
          (buffer (find-file-noselect (expand-file-name "doc.org" root))))
     (imprimeur-skin-define 'alpha :title "Alpha" :directory root :stylesheets '("skin.css")
                            :options (list imprimeur-menu-test-tone
                                           '(size :label "Size" :default "9"
                                                  :choices (("9" . "Nine") ("10" . "Ten")))))
     (imprimeur-skin-define 'beta :title "Beta" :directory root :stylesheets '("skin.css"))
     (imprimeur-skin-define 'gamma :title "Gamma" :directory root :stylesheets '("skin.css")
                            :menu-key "7")
     (unwind-protect
         (save-window-excursion
           (pop-to-buffer-same-window buffer)
           (imprimeur-mode 1)
           (let* ((url (url-generic-parse-url (imprimeur-url)))
                  (path (url-filename url))
                  (,(car spec) (imprimeur-test-http-stream
                                (url-port url)
                                (concat (substring path 0 (1+ (string-search "/" path 1)))
                                        ".imprimeur/events"))))
             (imprimeur-test-wait-for (lambda () (imprimeur--session-clients imprimeur--session)))
             (unwind-protect
                 (progn ,@body)
               (when (get-buffer-window imprimeur-menu-test-buffer)
                 (execute-kbd-macro (kbd "C-g")))
               (delete-process ,(car spec)))))
       (with-current-buffer buffer (set-buffer-modified-p nil))
       (kill-buffer buffer))))

(defun imprimeur-menu-test-text ()
  "Return what the open menu says."
  (should (get-buffer-window imprimeur-menu-test-buffer))
  (with-current-buffer imprimeur-menu-test-buffer
    (buffer-substring-no-properties (point-min) (point-max))))

(defun imprimeur-menu-test-press (key)
  "Press KEY, as `kbd' reads it, and return what the menu then says."
  (execute-kbd-macro (kbd key))
  (imprimeur-menu-test-text))

(defun imprimeur-menu-test-events (stream name)
  "Return the data of the events NAME that STREAM has received, parsed, oldest first."
  (mapcar (lambda (event) (json-parse-string (cdr event) :object-type 'plist :false-object nil))
          (seq-filter (lambda (event) (equal (car event) name)) (imprimeur-test-http-events stream))))

(defun imprimeur-menu-test-sorted (keys)
  "Return the alist KEYS sorted by name."
  (seq-sort-by #'car #'string< keys))

;; The manifests themselves: the three centuries are told apart by their digits.
(ert-deftest imprimeur-menu-keys-of-the-skins-here ()
  (let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
        (names '("base" "briefing" "ecrivain" "minitel" "tianlu" "xix" "xvii" "xviii")))
    (dolist (name (cdr names))
      (load (concat "imprimeur-skin-" name) nil t))
    (should (equal (imprimeur-menu-test-sorted
                    (imprimeur-skin-menu-keys
                     (mapcar (lambda (name) (cons name (plist-get (imprimeur-skin-get name) :menu-key)))
                             names)))
                   '(("base" . "b") ("briefing" . "r") ("ecrivain" . "e") ("minitel" . "m")
                     ("tianlu" . "t") ("xix" . "9") ("xvii" . "7") ("xviii" . "8"))))))

(ert-deftest imprimeur-menu-keys-hold-their-table-whatever-the-order ()
  (pcase-dolist (`(,entries . ,expected)
                 '(;; The core's page and the seven skins here.
                   ((("base") ("briefing") ("ecrivain") ("minitel") ("tianlu")
                     ("xvii" . "7") ("xviii" . "8") ("xix" . "9"))
                    . (("base" . "b") ("briefing" . "r") ("ecrivain" . "e") ("minitel" . "m")
                       ("tianlu" . "t") ("xix" . "9") ("xvii" . "7") ("xviii" . "8")))
                   (nil . nil)
                   ;; The first free letter of its own name, and then of the alphabet.
                   ((("ab") ("ba") ("aa")) . (("aa" . "a") ("ab" . "b") ("ba" . "c")))
                   ;; A digit or a hyphen of a name is no key.
                   ((("x1") ("x-2")) . (("x-2" . "x") ("x1" . "a")))
                   ;; A key asked for wins over a derivation that comes before it.
                   ((("base") ("zed" . "b")) . (("base" . "a") ("zed" . "b")))
                   ;; Two ask for one: the first by name has it, and the other derives.
                   ((("mid" . "7") ("low" . "7")) . (("low" . "7") ("mid" . "m")))))
    (dolist (order (list entries (reverse entries)))
      (ert-info ((format "%S" order))
        (should (equal (imprimeur-menu-test-sorted (imprimeur-skin-menu-keys order)) expected))))))

(ert-deftest imprimeur-menu-keys-leave-out-a-name-beyond-the-alphabet ()
  (let* ((names (mapcar (lambda (letter) (list (format "a%c" letter))) (number-sequence ?a ?z)))
         (keys (imprimeur-skin-menu-keys (cons '("zz") names))))
    ;; aa to az take the alphabet, as their names come first, and zz finds none.
    (should (= (length keys) 26))
    (should-not (assoc "zz" keys))
    (should (equal (length (seq-uniq (mapcar #'cdr keys))) 26))))

(ert-deftest imprimeur-menu-loading-imprimeur-leaves-transient-unloaded ()
  (should (equal (repo-test-emacs (list "-L" (expand-file-name "imprimeur" repo-test-root)
                                        "-l" "imprimeur"
                                        "--eval" "(princ (list (featurep 'transient)
                                                               (fboundp 'imprimeur-skin-menu)))"))
                 '(0 . "(nil t)"))))

(ert-deftest imprimeur-menu-without-a-session-says-so-and-does-not-open ()
  (with-temp-buffer
    (let ((failure (should-error (call-interactively #'imprimeur-skin-menu) :type 'user-error)))
      (should (equal (cadr failure) "No imprimeur session in this buffer")))
    (should-not (get-buffer-window imprimeur-menu-test-buffer))))

(ert-deftest imprimeur-menu-opens-on-the-mode-s-key-with-the-skin-marked ()
  (imprimeur-menu-test-with (_stream)
    (should (eq (key-binding (kbd "M-g s") t) 'imprimeur-skin-menu))
    (let ((text (imprimeur-menu-test-press "M-g s")))
      ;; A skin registered by the test is there, with no change to the core.
      (dolist (line '(" a   Alpha" " b * Plain" " e   Beta" " 7   Gamma"))
        (ert-info (line) (should (string-search line text))))
      ;; The skin `base' has no options, and nothing is chosen to keep.
      (should-not (string-search "Options of" text))
      (should-not (string-search "To keep" text)))))

(ert-deftest imprimeur-menu-a-skin-s-key-swaps-with-no-reload-and-stays-open ()
  (imprimeur-menu-test-with (stream)
    (let ((session imprimeur--session)
          (clients (copy-sequence (imprimeur--session-clients imprimeur--session))))
      (imprimeur-menu-test-press "M-g s")
      (let ((text (imprimeur-menu-test-press "a")))
        (should (string-search " a * Alpha" text))
        (should (string-search " b   Plain" text))
        (should (string-search "Options of Alpha" text)))
      (should (equal (imprimeur--session-skin session) "alpha"))
      (imprimeur-test-wait-for (lambda () (imprimeur-menu-test-events stream "skin")))
      (should (equal (plist-get (car (last (imprimeur-menu-test-events stream "skin"))) :name) "alpha"))
      ;; The same stream: the page has not loaded again.
      (should (equal (imprimeur--session-clients session) clients))
      ;; And on to a skin with no options, which shows none, from the same menu.
      (let ((text (imprimeur-menu-test-press "e")))
        (should (string-search " e * Beta" text))
        (should-not (string-search "Options of" text)))
      (should (equal (imprimeur--session-skin session) "beta"))
      ;; And to a skin by the key that its manifest names.
      (should (string-search " 7 * Gamma" (imprimeur-menu-test-press "7")))
      (should (equal (imprimeur--session-skin session) "gamma")))))

(ert-deftest imprimeur-menu-an-option-s-key-cycles-its-registered-values ()
  (imprimeur-menu-test-with (stream)
    (imprimeur-menu-test-press "M-g s")
    (let ((text (imprimeur-menu-test-press "a")))
      ;; Capitals, so that a skin's key cannot take an option's.
      (should (string-search " T Tone: Soft" text))
      (should (string-search " S Size: Nine" text)))
    (pcase-dolist (`(,label ,value ,attributes)
                   '(("Loud" "loud" [["data-alpha-tone" "loud"]])
                     ("Dull" "dull" [["data-alpha-tone" "dull"]])
                     ;; Round to the first, which is the default and has no attribute.
                     ("Soft" "soft" [])))
      (ert-info (label)
        (let ((text (imprimeur-menu-test-press "T"))
              (sent (length (imprimeur-menu-test-events stream "option"))))
          (should (string-search (concat " T Tone: " label) text))
          (should (string-search (format "To keep it: (alpha (tone . %S))" value) text))
          (should (equal (alist-get 'tone (cdr (assoc "alpha" (imprimeur--session-skin-choices
                                                               imprimeur--session))))
                         value))
          (imprimeur-test-wait-for
           (lambda ()
             (let ((events (imprimeur-menu-test-events stream "option")))
               (and (>= (length events) sent)
                    (equal (plist-get (car (last events)) :attributes) attributes))))))))
    ;; The other option keeps its value, and the line names both once it has one.
    (let ((text (imprimeur-menu-test-press "S")))
      (should (string-search " S Size: Ten" text))
      (should (string-search " T Tone: Soft" text))
      (should (string-search "To keep it: (alpha (size . \"10\") (tone . \"soft\"))" text)))))

(ert-deftest imprimeur-menu-cycles-on-from-the-configured-value ()
  (let ((imprimeur-skin-options '((alpha (tone . "loud")))))
    (imprimeur-menu-test-with (_stream)
      (imprimeur-menu-test-press "M-g s")
      (should (string-search " T Tone: Loud" (imprimeur-menu-test-press "a")))
      (should (string-search " T Tone: Dull" (imprimeur-menu-test-press "T"))))))

(ert-deftest imprimeur-menu-closes-and-leaves-the-commands-by-completion ()
  (imprimeur-menu-test-with (_stream)
    (imprimeur-menu-test-press "M-g s")
    (execute-kbd-macro (kbd "C-g"))
    (should-not (get-buffer-window imprimeur-menu-test-buffer))
    (should (commandp #'imprimeur-choose-skin))
    (should (eq (key-binding (kbd "M-g o") t) 'imprimeur-set-skin-option))))

;;; imprimeur-menu-test.el ends here
