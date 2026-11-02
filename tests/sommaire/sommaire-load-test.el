;;; sommaire-load-test.el --- Loading sommaire has no side effect  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirement: loading a package prints nothing, leaves the other package
;; of the repository unloaded, and adds no timer, global hook or global key
;; (plan 001, acceptance 5).

;;; Code:

(require 'ert)
(require 'repo-test-helpers)

(ert-deftest sommaire-load-prints-nothing ()
  "Loading sommaire in batch prints nothing and succeeds."
  (should (equal (repo-test-emacs (list "-L" (expand-file-name "sommaire" repo-test-root)
                                        "-l" "sommaire"))
                 '(0 . ""))))

(ert-deftest sommaire-load-changes-no-global-state ()
  "Requiring sommaire adds no timer, hook or global key, and loads no imprimeur.
`define-minor-mode' lists the mode's map in `minor-mode-map-alist', and it does
nothing until the mode is on in a buffer, as the next test checks."
  (should (equal (repo-test-load-effects 'sommaire)
                 '(:timers 0 :hooks nil :global-map nil :minor-modes t
                   :auto-modes nil :sommaire t :imprimeur nil))))

(ert-deftest sommaire-load-binds-no-key ()
  "After loading sommaire, its key means nothing in any buffer."
  (should (equal (repo-test-emacs (list "-L" (expand-file-name "sommaire" repo-test-root)
                                        "-l" "sommaire"
                                        "--eval" "(prin1 (key-binding (kbd \"M-g m\")))"))
                 '(0 . "nil"))))

(ert-deftest sommaire-load-needs-neither-pandoc-nor-chromium ()
  "Plan 005, acceptance 6: acceptance 3 and 4 hold in a child `emacs -Q -L sommaire'.
Its PATH has neither pandoc nor Chromium, nor anything else, and imprimeur,
which is not on its load path either, stays unloaded."
  (let* ((path (make-temp-file "sommaire-test-path" t))
         (result (repo-test-emacs
                  (list "-L" (expand-file-name "sommaire" repo-test-root)
                        "-L" (expand-file-name "tests/helpers" repo-test-root)
                        "-l" (expand-file-name "tests/sommaire/sommaire-test.el" repo-test-root)
                        "--eval"
                        (prin1-to-string
                         '(let ((stats (ert-run-tests-batch
                                        "\\`sommaire-acceptance-\\(?:header\\|jump\\)-")))
                            (message "child: %S"
                                     (list :total (ert-stats-total stats)
                                           :unexpected (ert-stats-completed-unexpected stats)
                                           :tools (seq-filter #'executable-find
                                                              '("pandoc" "chromium"
                                                                "chromium-browser"))
                                           :imprimeur (featurep 'imprimeur))))))
                  (list (concat "PATH=" path)))))
    (delete-directory path)
    (should (eql (car result) 0))
    (should (string-match "^child: \\(.*\\)$" (cdr result)))
    ;; The tests of acceptance 3 in sommaire-test.el are 5, and of acceptance 4, 2.
    (should (equal (car (read-from-string (match-string 1 (cdr result))))
                   '(:total 7 :unexpected 0 :tools nil :imprimeur nil)))))

;;; sommaire-load-test.el ends here
