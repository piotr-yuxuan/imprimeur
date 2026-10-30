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
  "Requiring sommaire adds no timer, hook or key, and loads no imprimeur."
  (should (equal (repo-test-load-effects 'sommaire)
                 '(:timers 0 :hooks nil :global-map nil :minor-modes nil
                   :auto-modes nil :sommaire t :imprimeur nil))))

;;; sommaire-load-test.el ends here
