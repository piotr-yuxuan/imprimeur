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

;;; sommaire-load-test.el ends here
