;;; readme-config-test.el --- The README's configuration loads  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement (plan 028): the README holds a complete configuration of imprimeur,
;; sommaire and the skins, every option at its default.  This test takes the `elisp'
;; fences of its section "Configuration" from the README itself and loads them unchanged,
;; in a scratch Emacs with the real straight.el, against a copy of this tree.
;;
;; So that the recipes stand as a reader copies them, a scratch git configuration rewrites
;; their address to that copy.  Nothing reaches the network: git may use the file protocol
;; alone, straight.el and package.el have no list of recipes or archive, and what goes
;; through a proxy goes to a closed port of the loopback interface.  As a page opens with a
;; stand-in for the browser, no desktop window opens.

;;; Code:

(require 'ert)
(require 'seq)
(require 'repo-test-helpers)

(defconst readme-config-test-harness
  '(progn
     (setq straight-recipe-repositories nil
           straight-check-for-modifications nil
           straight-vc-git-default-clone-depth 'full
           straight-disable-native-compile t
           native-comp-jit-compilation nil
           package-archives nil)
     (require 'straight)
     (straight-use-package-mode 1)
     (require 'use-package)
     (load (getenv "README_CONFIG_FILE") nil nil t)
     (require 'imprimeur)
     (let ((options nil)
           (document (expand-file-name "doc.org" (getenv "README_CONFIG_DIRECTORY"))))
       (with-temp-file document (insert "#+TITLE: Test\n\n* One\n\nText.\n"))
       (find-file document)
       (let ((imprimeur-browser-program (getenv "README_CONFIG_BROWSER")))
         (imprimeur-mode 1))
       (let ((initial (imprimeur--session-skin imprimeur--session)))
         (imprimeur-choose-skin "xix")
         ;; Once the hook has loaded sommaire.
         (mapatoms (lambda (symbol)
                     (when (and (custom-variable-p symbol)
                                (string-match-p "\\`\\(?:imprimeur\\|sommaire\\)-" (symbol-name symbol))
                                (not (string-suffix-p "-hook" (symbol-name symbol))))
                       (push symbol options))))
         (let ((report
                (list
                 :options (mapcar #'symbol-name options)
                 :away (seq-remove (lambda (option)
                                     (or (eq option 'imprimeur-skin-options)
                                         (equal (symbol-value option)
                                                (eval (car (get option 'standard-value)) t))))
                                   options)
                 :features (mapcar (lambda (name) (cons name (locate-library name)))
                                   (append '("imprimeur" "sommaire")
                                           (mapcar (lambda (skin) (concat "imprimeur-skin-" skin))
                                                   (remove "base" (imprimeur-skin-names)))))
                 :skins (imprimeur-skin-names)
                 :initial initial
                 :chosen (imprimeur--session-skin imprimeur--session)
                 :sommaire sommaire-mode
                 :keys (mapcar (lambda (key) (key-binding (kbd key)))
                               '("C-c i" "C-c m" "C-c M" "M-g v" "M-g s" "M-g o" "M-g m"))
                 :defaults (mapcar (lambda (skin)
                                     (cons skin (mapcar (lambda (option)
                                                          (list (car option)
                                                                (plist-get (cdr option) :default)
                                                                (alist-get (car option)
                                                                           (alist-get (intern skin) imprimeur-skin-options))))
                                                        (plist-get (imprimeur-skin-get skin) :options))))
                                   (remove "base" (imprimeur-skin-names)))
                 :choices (mapcan (lambda (skin)
                                    (mapcan (lambda (option)
                                              (let ((choices (mapcar #'car (plist-get (cdr option) :choices))))
                                                (and (<= (length choices) 16) (copy-sequence choices))))
                                            (plist-get (imprimeur-skin-get skin) :options)))
                                  (remove "base" (imprimeur-skin-names)))
                 :warnings (and (get-buffer "*Warnings*")
                                (with-current-buffer "*Warnings*" (buffer-string))))))
           (imprimeur-stop-all)
           (prin1 report)))))
  "What the scratch Emacs runs: the harness, then the configuration, then its report.")

(defun readme-config-test-fences ()
  "Return the text of the `elisp' fences of the README's section \"Configuration\"."
  (let ((coding-system-for-read 'utf-8))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "README.md" repo-test-root))
      (re-search-forward "^## Configuration$")
      (let ((end (save-excursion (re-search-forward "^## ") (point)))
            (fences nil))
        (while (re-search-forward "^```elisp\n\\(\\(?:.*\n\\)*?\\)```$" end t)
          (push (match-string 1) fences))
        (string-join (nreverse fences) "\n")))))

(defun readme-config-test-load (fences)
  "Load FENCES as an init file in a scratch Emacs; return (STATUS . REPORT).
REPORT is what `readme-config-test-harness' prints, or the Emacs's output."
  (let* ((scratch (file-name-as-directory (make-temp-file "readme-config" t)))
         (repository (expand-file-name "repository/" scratch))
         (init (expand-file-name "init.el" scratch))
         (git-config (expand-file-name "gitconfig" scratch)))
    (make-directory repository)
    ;; What a clone holds, and nothing else of this tree.
    (dolist (file (split-string (repo-test-git repo-test-root "ls-files" "--" "imprimeur" "sommaire"
                                               ":(glob)imprimeur-skin-*/**")
                                "\n" t))
      (make-directory (file-name-directory (expand-file-name file repository)) t)
      (copy-file (expand-file-name file repo-test-root) (expand-file-name file repository)))
    (repo-test-git repository "init" "-q" "-b" "main")
    (repo-test-git repository "add" "-A")
    (repo-test-git repository "commit" "-q" "-m" "The tree under test")
    (with-temp-file init
      (insert ";;; init.el --- A reader's init  -*- lexical-binding: t; -*-\n" fences))
    (with-temp-file git-config
      (insert (format "[url \"file://%s\"]\n\tinsteadOf = https://github.com/piotr-yuxuan/imprimeur.git\n"
                      (directory-file-name repository))))
    (make-directory (expand-file-name "home" scratch))
    (let* ((repo-test-timeout 300)
           (result (repo-test-emacs
                    (list "--eval" (prin1-to-string readme-config-test-harness))
                    (list (concat "HOME=" (expand-file-name "home" scratch))
                          (concat "GIT_CONFIG_GLOBAL=" git-config)
                          "GIT_CONFIG_NOSYSTEM=1"
                          "GIT_ALLOW_PROTOCOL=file"
                          "http_proxy=http://127.0.0.1:9"
                          "https_proxy=http://127.0.0.1:9"
                          "ALL_PROXY=http://127.0.0.1:9"
                          "no_proxy"
                          "NO_PROXY"
                          (concat "README_CONFIG_FILE=" init)
                          (concat "README_CONFIG_DIRECTORY=" scratch)
                          (concat "README_CONFIG_BROWSER=" (expand-file-name "tests/bin/fake-browser" repo-test-root)))
                    scratch))
           (start (string-match "(:options" (cdr result))))
      (cons (car result)
            (if start
                (car (read-from-string (cdr result) start))
              (cdr result))))))

(ert-deftest readme-config-loads-and-chooses-a-skin ()
  (let* ((fences (readme-config-test-fences))
         (result (readme-config-test-load fences))
         (report (cdr result)))
    (should (equal (car result) 0))
    (should (consp report))
    ;; Every package is the one built from the recipe, by a clone that the rewrite made.
    (should (length> (plist-get report :features) 8))
    (dolist (feature (plist-get report :features))
      (ert-info ((car feature))
        (should (string-search "/straight/build/" (or (cdr feature) "")))))
    (should (equal (plist-get report :skins)
                   '("base" "briefing" "dubai" "ecrivain" "minitel" "tianlu" "xix" "xvii" "xviii"
                     "yaqut")))
    ;; It chooses a skin: Minitel by `auto', then another by the command.
    (should (equal (plist-get report :initial) "minitel"))
    (should (equal (plist-get report :chosen) "xix"))
    (should (plist-get report :sommaire))
    (should-not (plist-get report :warnings))
    ;; Complete, and straight: every option there, at its default.
    (should (equal (plist-get report :keys)
                   '(imprimeur-mode sommaire-panel sommaire-toggle-inline imprimeur-jump
                                    imprimeur-skin-menu imprimeur-set-skin-option sommaire-jump)))
    (should-not (seq-remove (lambda (option)
                              (string-match-p (concat "^ *(" (regexp-quote option) "[ \n]") fences))
                            (plist-get report :options)))
    (should-not (plist-get report :away))
    (pcase-dolist (`(,skin . ,options) (plist-get report :defaults))
      (ert-info (skin)
        (pcase-dolist (`(,_id ,default ,value) options)
          (should (equal value default)))))
    (should-not (seq-remove (lambda (choice) (string-search (format "\"%s\"" choice) fences))
                            (plist-get report :choices)))))

;;; readme-config-test.el ends here
