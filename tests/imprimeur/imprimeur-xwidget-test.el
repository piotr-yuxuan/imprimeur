;;; imprimeur-xwidget-test.el --- Tests of the page in an Emacs window  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 004): the decisions "The view buffer", "Display", "Watchdog",
;; "Target" and "Teardown", with `imprimeur-jump' from a view.
;;
;; Acceptance 1: the xwidget target, where it cannot run, is a user error naming the
;; browser target that creates no buffer and no server; `auto' falls back to the
;; browser.  `auto' means an xwidget on a graphic frame of a build with xwidgets.
;; Acceptance 7: the watchdog's table of states and events holds: no `ready' in 3 s,
;; reload; again, fail and offer the browser; the stream closing while live, reload.
;;
;; A view's major mode is exactly `xwidget-webkit-mode', with `imprimeur-view-mode',
;; which makes the scrolling keys scroll the page as a user scroll, so that the source
;; follows, and `M-g v' go back to the source at the line of the page's top block.  A
;; load committed outside the session goes back to the page; a download prompts for
;; nothing and writes nothing; an xwidget that the page asks for is killed.  The view
;; opens on the right, half wide, dedicated, with the source still selected, through
;; the category `imprimeur'; `display-buffer-same-window' works and quitting restores
;; the source; a second Emacs window showing the view gets its previous buffer back.
;; Killing the view keeps the session, and `imprimeur-show' opens it again; killing the
;; source, or ending the mode, kills the view and its timer, without a question.  The
;; file compiles on a build without xwidgets, which the suite's run on Emacs 30.1 is.
;;
;; An xwidget needs a display, so here its primitives are stand-ins that record their
;; calls, and the rest is real: buffers, Emacs windows, the session, the server, and
;; where a test needs a page, Chromium running the view's scripts.  `make smoke-xwidget'
;; is what runs a real one.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-xwidget)
;; Before the stand-ins, which it would replace when it came with a first view.
(require 'xwidget)

(defvar imprimeur-xwidget-test-calls nil
  "The calls of the stand-ins for xwidget's primitives, newest first.")

(defvar imprimeur-xwidget-test-script nil
  "A function given each script that a view runs, or nil.")

(defun imprimeur-xwidget-test-called (name)
  "Return the arguments of the calls of the stand-in NAME, oldest first."
  (mapcar #'cdr (reverse (seq-filter (lambda (call) (eq (car call) name)) imprimeur-xwidget-test-calls))))

(defmacro imprimeur-xwidget-test-fake (&rest body)
  "Run BODY with stand-ins for xwidget's primitives, and with the target `xwidget'."
  `(let ((imprimeur-xwidget-test-calls nil)
         (imprimeur-xwidget-test-script nil))
     (cl-flet ((record (name)
                 (lambda (&rest arguments)
                   (push (cons name arguments) imprimeur-xwidget-test-calls)
                   nil)))
       (cl-letf (((symbol-function 'xwidget-insert) (lambda (&rest _) 'fake-xwidget))
                 ((symbol-function 'set-xwidget-query-on-exit-flag) (record 'query-flag))
                 ((symbol-function 'xwidget-put) (record 'put))
                 ((symbol-function 'xwidget-webkit-goto-uri) (record 'goto))
                 ((symbol-function 'xwidget-webkit-adjust-size-to-window) (record 'size))
                 ((symbol-function 'kill-xwidget) (record 'kill))
                 ((symbol-function 'xwidget-webkit-execute-script)
                  (lambda (_xwidget script &rest _)
                    (push (list 'script script) imprimeur-xwidget-test-calls)
                    (when imprimeur-xwidget-test-script
                      (funcall imprimeur-xwidget-test-script script))))
                 ((symbol-function 'imprimeur--target-for) (lambda (&rest _) 'xwidget)))
         ,@body))))

;;;; The watchdog

(ert-deftest imprimeur-xwidget-watchdog-decides ()
  (pcase-dolist (`(,state ,event ,next ,action)
                 '((loading timeout retrying reload)
                   (loading waiting loading nil)
                   (loading ready live nil)
                   (loading closed loading nil)
                   (retrying timeout failed offer)
                   (retrying waiting retrying nil)
                   (retrying ready live nil)
                   (retrying closed retrying nil)
                   (live timeout live nil)
                   (live waiting live nil)
                   (live ready live nil)
                   (live closed loading reload)
                   (failed timeout failed nil)
                   (failed waiting failed nil)
                   (failed ready live nil)
                   (failed closed failed nil)))
    (should (equal (list state event (imprimeur-xwidget--next state event))
                   (list state event (cons next action))))))

;;;; The callback

(defconst imprimeur-xwidget-test-home "http://127.0.0.1:8000/0123abc/doc.org"
  "The address of a page in the tests of the callback.")

(ert-deftest imprimeur-xwidget-a-foreign-load-goes-back ()
  (pcase-dolist (`(,stage ,uri ,back)
                 `(("load-committed" ,imprimeur-xwidget-test-home nil)
                   ("load-committed" ,(concat imprimeur-xwidget-test-home "#id") nil)
                   ("load-committed" "http://127.0.0.1:8000/0123abc/" nil)
                   ("load-committed" "http://example.invalid/" t)
                   ("load-committed" "http://127.0.0.1:8000/" t)
                   ("load-committed" "http://127.0.0.1:8000/0123abc" t)
                   ("load-committed" "http://127.0.0.1:8000/0123abcd/doc.org" t)
                   ("load-committed" "http://127.0.0.1:8001/0123abc/doc.org" t)
                   ("load-committed" "file:///etc/passwd" t)
                   ("load-committed" "about:blank" t)
                   ("load-committed" nil t)
                   ;; What has not been committed is not there yet, or has gone.
                   ("load-started" "http://example.invalid/" nil)
                   ("load-redirected" "http://example.invalid/" nil)
                   ("load-finished" "http://example.invalid/" nil)))
    (imprimeur-xwidget-test-fake
     (cl-letf (((symbol-function 'xwidget-webkit-uri) (lambda (_) uri)))
       (let ((last-input-event (list 'xwidget-event 'load-changed 'fake-xwidget stage)))
         (imprimeur-xwidget--event imprimeur-xwidget-test-home 'fake-xwidget 'load-changed))
       (should (equal (list stage uri (imprimeur-xwidget-test-called 'goto))
                      (list stage uri (and back `((fake-xwidget ,imprimeur-xwidget-test-home))))))))))

(ert-deftest imprimeur-xwidget-forwards-a-script-result-and-nothing-else ()
  (let ((results nil))
    (let ((last-input-event (list 'xwidget-event 'javascript-callback 'fake-xwidget
                                  (lambda (value) (push value results)) 42)))
      (imprimeur-xwidget--event imprimeur-xwidget-test-home 'fake-xwidget 'javascript-callback))
    (should (equal results '(42))))
  ;; What would prompt, write a file or rename a buffer in xwidget's own callback.
  (let ((default-directory (make-temp-file "imprimeur-download" t)))
    (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) (ert-fail "A prompt")))
              ((symbol-function 'url-copy-file) (lambda (&rest _) (ert-fail "A file")))
              ((symbol-function 'rename-buffer) (lambda (&rest _) (ert-fail "A new name"))))
      (pcase-dolist (`(,type . ,rest)
                     '((download-callback "http://127.0.0.1/x" "text/plain" "x")
                       (decide-policy "http://127.0.0.1/x#y")
                       (unknown)))
        (let ((last-input-event `(xwidget-event ,type fake-xwidget ,@rest)))
          (imprimeur-xwidget--event imprimeur-xwidget-test-home 'fake-xwidget type))))
    (should-not (directory-files default-directory nil "\\`[^.]"))))

;;;; The view buffer

(ert-deftest imprimeur-xwidget-compiles-without-xwidgets ()
  ;; Without warnings, and on the suite's minimum Emacs its build has none.
  (should (equal (car (repo-test-emacs
                       (list "-L" (expand-file-name "imprimeur" repo-test-root)
                             "-l" (expand-file-name "scripts/lint.el" repo-test-root)
                             "-f" "repo-lint-compile"
                             (expand-file-name "imprimeur/imprimeur-xwidget.el" repo-test-root))))
                 0)))

;;; imprimeur-xwidget-test.el ends here
