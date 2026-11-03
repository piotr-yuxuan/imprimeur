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
(require 'ert-x)
(require 'cl-lib)
(require 'seq)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-http)
(require 'imprimeur-test-cdp)
(require 'imprimeur)
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

(defmacro imprimeur-xwidget-test-with (spec &rest body)
  "Run BODY with stand-ins, and BUFFER alone in the Emacs frame with its view.
SPEC is (BUFFER VIEW [TEXT PANDOC]): BUFFER visits an Org file holding TEXT,
in `imprimeur-mode', with the fake browser and PANDOC, by default the fake
one, and VIEW is its view."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,view ,text ,pandoc) spec))
    `(imprimeur-xwidget-test-fake
      (let* ((imprimeur-pandoc-program ,(or pandoc 'imprimeur-test-fake-pandoc))
             (imprimeur-browser-program imprimeur-test-fake-browser)
             (root (repo-test-git-tree (list (cons "doc.org" ,(or text "Text.\n")))))
             (,buffer (find-file-noselect (expand-file-name "doc.org" root))))
        (unwind-protect
            (save-window-excursion
              (delete-other-windows)
              (switch-to-buffer ,buffer)
              (imprimeur-mode 1)
              (let ((,view (imprimeur--session-view imprimeur--session)))
                ,@body))
          (when (buffer-live-p ,buffer)
            (with-current-buffer ,buffer (set-buffer-modified-p nil))
            (kill-buffer ,buffer)))))))

;;;; Where a page goes

(ert-deftest imprimeur-xwidget-target-decides ()
  (pcase-dolist (`(,target ,graphic ,built ,expected)
                 '((auto t t xwidget)
                   (auto t nil browser)
                   (auto nil t browser)
                   (auto nil nil browser)
                   (xwidget t t xwidget)
                   (xwidget t nil nil)
                   (xwidget nil t nil)
                   (xwidget nil nil nil)
                   (browser t t browser)
                   (browser t nil browser)
                   (browser nil t browser)
                   (browser nil nil browser)))
    (should (equal (list target graphic built (imprimeur--target-for target graphic built))
                   (list target graphic built expected)))))

(ert-deftest imprimeur-xwidget-target-where-it-cannot-run-creates-nothing ()
  ;; In batch no Emacs frame is graphic, with xwidgets built or not.
  (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
        (imprimeur-browser-program imprimeur-test-fake-browser)
        (imprimeur-target 'xwidget))
    (with-temp-buffer
      (org-mode)
      (let* ((buffers (buffer-list))
             (failure (cl-letf (((symbol-function 'imprimeur-server-start)
                                 (lambda () (ert-fail "A server started"))))
                        (should-error (imprimeur-mode 1) :type 'user-error))))
        (should (string-search "imprimeur-target" (cadr failure)))
        (should (string-search "browser" (cadr failure)))
        (should-not imprimeur-mode)
        (should-not imprimeur--session)
        (should-not imprimeur--sessions)
        (should-not (process-live-p imprimeur-server--process))
        (should (seq-set-equal-p (buffer-list) buffers))))))

(ert-deftest imprimeur-xwidget-auto-falls-back-to-the-browser ()
  (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
        (imprimeur-browser-program imprimeur-test-fake-browser)
        (imprimeur-target 'auto))
    (with-temp-buffer
      (org-mode)
      (imprimeur-mode 1)
      (should (process-live-p (imprimeur--session-viewer imprimeur--session)))
      (should-not (imprimeur--session-view imprimeur--session))
      (imprimeur-mode -1))))

(ert-deftest imprimeur-xwidget-an-xwidget-needs-no-browser ()
  (let ((imprimeur-browser-program "/nonexistent/imprimeur-browser"))
    (imprimeur-xwidget-test-fake
     (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc))
       (with-temp-buffer
         (org-mode)
         (imprimeur-mode 1)
         (should (buffer-live-p (imprimeur--session-view imprimeur--session)))
         (should-not (imprimeur--session-viewer imprimeur--session))
         (imprimeur-mode -1))))))

(ert-deftest imprimeur-xwidget-showing-needs-a-session ()
  (with-temp-buffer
    (should-error (imprimeur-show) :type 'user-error)))

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

(ert-deftest imprimeur-xwidget-reloads-once-then-offers-the-browser ()
  (let ((imprimeur-xwidget--wait 0.01))
    (imprimeur-xwidget-test-with (buffer view)
      (ert-with-message-capture messages
        ;; No page connects here, so that one is not rightly silent.
        (imprimeur-test-wait-for (lambda () (eq (buffer-local-value 'imprimeur-xwidget--state view) 'failed)))
        (should (string-search "imprimeur-browse" messages)))
      ;; The first load and one reload, and nothing is tried after that.
      (should (= (length (imprimeur-xwidget-test-called 'goto)) 2))
      (should-not (buffer-local-value 'imprimeur-xwidget--timer view))
      (should (buffer-local-value 'mode-line-process view))
      ;; A page late for all that still counts.
      (imprimeur-xwidget-note view 'ready)
      (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'live))
      (should-not (buffer-local-value 'mode-line-process view)))))

(ert-deftest imprimeur-xwidget-offers-what-works-from-the-view ()
  (let ((imprimeur-xwidget--wait 0.01))
    (imprimeur-xwidget-test-with (buffer view)
      (imprimeur-test-wait-for (lambda () (eq (buffer-local-value 'imprimeur-xwidget--state view) 'failed)))
      (with-current-buffer view (imprimeur-browse))
      (should (process-live-p (imprimeur--session-viewer (buffer-local-value 'imprimeur--session buffer)))))))

(ert-deftest imprimeur-xwidget-a-report-stops-the-watchdog ()
  (let ((imprimeur-xwidget--wait 0.01))
    (imprimeur-xwidget-test-with (buffer view)
      (imprimeur-xwidget-note view 'ready)
      (should-not (buffer-local-value 'imprimeur-xwidget--timer view))
      (accept-process-output nil 0.1)
      (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'live))
      (should (= (length (imprimeur-xwidget-test-called 'goto)) 1)))))

(ert-deftest imprimeur-xwidget-a-page-with-nothing-to-show-is-not-lost ()
  ;; Connected, its pandoc failing: no revision comes, by no fault of the page.
  (let ((imprimeur-xwidget--wait 0.01)
        (process-environment (cons "IMPRIMEUR_FAKE_PANDOC=fail" process-environment)))
    (imprimeur-xwidget-test-with (buffer view)
      (let* ((url (url-generic-parse-url (imprimeur-url buffer)))
             (token (nth 1 (split-string (url-filename url) "/")))
             (stream (imprimeur-test-http-stream (url-port url) (format "/%s/.imprimeur/events" token)))
             (session (buffer-local-value 'imprimeur--session buffer)))
        (imprimeur-test-wait-for (lambda () (imprimeur--session-clients session)))
        (imprimeur-test-wait-for (lambda () (imprimeur--session-error session)))
        (let ((loads (length (imprimeur-xwidget-test-called 'goto))))
          (accept-process-output nil 0.2)
          (should (= (length (imprimeur-xwidget-test-called 'goto)) loads))
          (should-not (eq (buffer-local-value 'imprimeur-xwidget--state view) 'failed))
          (should (buffer-local-value 'imprimeur-xwidget--timer view)))
        (delete-process stream)))))

(ert-deftest imprimeur-xwidget-hears-the-session ()
  (imprimeur-xwidget-test-with (buffer view)
    (let* ((url (url-generic-parse-url (imprimeur-url buffer)))
           (port (url-port url))
           (base (format "/%s/.imprimeur/" (nth 1 (split-string (url-filename url) "/"))))
           (session (buffer-local-value 'imprimeur--session buffer))
           (first (imprimeur-test-http-stream port (concat base "events")))
           (second (imprimeur-test-http-stream port (concat base "events"))))
      (imprimeur-test-wait-for (lambda () (= (length (imprimeur--session-clients session)) 2)))
      (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'loading))
      (should (equal (car (imprimeur-test-http-post port (concat base "post") "{\"type\":\"ready\",\"rev\":1}")) 204))
      (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'live))
      ;; A stream that closes beside another may be a browser's.
      (delete-process first)
      (imprimeur-test-wait-for (lambda () (= (length (imprimeur--session-clients session)) 1)))
      (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'live))
      (should (= (length (imprimeur-xwidget-test-called 'goto)) 1))
      ;; The last one is the page lost.
      (delete-process second)
      (imprimeur-test-wait-for (lambda () (not (imprimeur--session-clients session))))
      (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'loading))
      (should (= (length (imprimeur-xwidget-test-called 'goto)) 2))
      (should (equal (car (last (imprimeur-xwidget-test-called 'goto)))
                     (list 'fake-xwidget (imprimeur-url buffer)))))))

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

(ert-deftest imprimeur-xwidget-view-is-xwidgets-own-mode-with-ours ()
  (let ((last-session xwidget-webkit-last-session-buffer))
    (imprimeur-xwidget-test-with (buffer view)
      (with-current-buffer view
        (should (eq major-mode 'xwidget-webkit-mode))
        (should imprimeur-view-mode)
        (should-not header-line-format)
        (should-not vertical-scroll-bar))
      (should (equal (imprimeur-xwidget-test-called 'goto)
                     (list (list 'fake-xwidget (imprimeur-url buffer)))))
      (should (member '(fake-xwidget nil) (imprimeur-xwidget-test-called 'query-flag)))
      ;; Nothing of a reader's own xwidget sessions changes.
      (should (eq xwidget-webkit-last-session-buffer last-session)))))

(ert-deftest imprimeur-xwidget-view-keys-are-the-page-s ()
  (imprimeur-xwidget-test-with (buffer view)
    (with-current-buffer view
      (pcase-dolist (`(,key . ,command)
                     '(("C-v" . imprimeur-view-scroll-up)
                       ("SPC" . imprimeur-view-scroll-up)
                       ("<next>" . imprimeur-view-scroll-up)
                       ("M-v" . imprimeur-view-scroll-down)
                       ("S-SPC" . imprimeur-view-scroll-down)
                       ("DEL" . imprimeur-view-scroll-down)
                       ("<prior>" . imprimeur-view-scroll-down)
                       ("C-n" . imprimeur-view-next-line)
                       ("<down>" . imprimeur-view-next-line)
                       ("C-p" . imprimeur-view-previous-line)
                       ("<up>" . imprimeur-view-previous-line)
                       ("M-<" . imprimeur-view-top)
                       ("M->" . imprimeur-view-bottom)
                       ("M-g v" . imprimeur-jump)))
        (should (equal (cons key (key-binding (kbd key) t)) (cons key command))))
      ;; What it leaves to its major mode.
      (should (eq (key-binding (kbd "q")) 'quit-window)))
    (with-current-buffer buffer
      (should (eq (key-binding (kbd "C-v") t) 'scroll-up-command)))))

(ert-deftest imprimeur-xwidget-view-scrolls-by-what-each-command-says ()
  (imprimeur-xwidget-test-with (buffer view)
    (save-window-excursion
      (pop-to-buffer view)
      (let ((line (window-font-height))
            (page (- (window-body-height nil t) (* next-screen-context-lines (window-font-height)))))
        (pcase-dolist (`(,command ,argument ,pixels)
                       `((imprimeur-view-scroll-up nil ,page)
                         (imprimeur-view-scroll-up 3 ,(* 3 line))
                         (imprimeur-view-scroll-down nil ,(- page))
                         (imprimeur-view-scroll-down 3 ,(- (* 3 line)))
                         (imprimeur-view-next-line 2 ,(* 2 line))
                         (imprimeur-view-previous-line 2 ,(- (* 2 line)))))
          (setq imprimeur-xwidget-test-calls nil)
          (funcall command argument)
          (should (equal (list command argument (imprimeur-xwidget-test-called 'script))
                         (list command argument `((,(format "imprimeur.scrollBy(%d)" pixels)))))))
        (setq imprimeur-xwidget-test-calls nil)
        (imprimeur-view-top)
        (imprimeur-view-bottom)
        (pcase-let ((`((,top) (,bottom)) (imprimeur-xwidget-test-called 'script)))
          (should (string-match "\\`imprimeur\\.scrollBy(-\\([0-9]+\\))\\'" top))
          (should (> (string-to-number (match-string 1 top)) 1000000))
          (should (string-match "\\`imprimeur\\.scrollBy(\\([0-9]+\\))\\'" bottom))
          (should (> (string-to-number (match-string 1 bottom)) 1000000)))))))

(ert-deftest imprimeur-xwidget-a-new-xwidget-is-killed ()
  (imprimeur-xwidget-test-with (buffer view)
    (pcase-let ((`(,_ ,_ ,callback)
                 (seq-find (lambda (arguments) (eq (nth 1 arguments) 'display-callback))
                           (imprimeur-xwidget-test-called 'put))))
      (funcall callback 'new-xwidget 'fake-xwidget)
      (should (equal (imprimeur-xwidget-test-called 'kill) '((new-xwidget))))
      (should (seq-set-equal-p (list view buffer)
                               (seq-filter (lambda (each) (memq each (list view buffer))) (buffer-list)))))))

(ert-deftest imprimeur-xwidget-a-failure-leaves-no-buffer ()
  (imprimeur-xwidget-test-fake
   (cl-letf (((symbol-function 'xwidget-insert) (lambda (&rest _) (error "No widget"))))
     (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc))
       (with-temp-buffer
         (org-mode)
         (let ((buffers (buffer-list)))
           (should-error (imprimeur-mode 1))
           (should-not imprimeur-mode)
           (should-not imprimeur--sessions)
           (should-not (process-live-p imprimeur-server--process))
           (should (seq-set-equal-p (buffer-list) buffers))))))))

(ert-deftest imprimeur-xwidget-compiles-without-xwidgets ()
  ;; Without warnings, and on the suite's minimum Emacs its build has none.
  (should (equal (car (repo-test-emacs
                       (list "-L" (expand-file-name "imprimeur" repo-test-root)
                             "-l" (expand-file-name "scripts/lint.el" repo-test-root)
                             "-f" "repo-lint-compile"
                             (expand-file-name "imprimeur/imprimeur-xwidget.el" repo-test-root))))
                 0)))

;;;; Display

(ert-deftest imprimeur-xwidget-opens-on-the-right-with-the-source-selected ()
  (imprimeur-xwidget-test-with (buffer view)
    (let* ((source (get-buffer-window buffer))
           (right (window-in-direction 'right source)))
      (should (eq (selected-window) source))
      (should (eq (window-buffer right) view))
      (should (window-dedicated-p right))
      (should (<= (abs (- (window-total-width right) (window-total-width source))) 1))
      (should (equal (car (last (imprimeur-xwidget-test-called 'size))) (list 'fake-xwidget right)))
      ;; Asked again, nothing new.
      (with-current-buffer buffer (imprimeur-show))
      (should (eq (imprimeur--session-view (buffer-local-value 'imprimeur--session buffer)) view))
      (should (equal (get-buffer-window-list view) (list right)))
      (should (= (count-windows) 2)))))

(ert-deftest imprimeur-xwidget-display-goes-through-its-category ()
  (let ((display-buffer-alist '(((category . imprimeur) (display-buffer-below-selected)))))
    (imprimeur-xwidget-test-with (buffer view)
      (should (eq (window-buffer (window-in-direction 'below (get-buffer-window buffer))) view)))))

(ert-deftest imprimeur-xwidget-takes-the-same-window-when-asked ()
  (let ((imprimeur-display-buffer-action '((display-buffer-same-window))))
    (imprimeur-xwidget-test-with (buffer view)
      (should (one-window-p))
      (should (eq (window-buffer) view))
      (with-current-buffer view (quit-window))
      (should (eq (window-buffer) buffer))
      (should (buffer-live-p view)))))

(ert-deftest imprimeur-xwidget-a-second-window-gets-its-buffer-back ()
  (imprimeur-xwidget-test-with (buffer view)
    (let* ((first (get-buffer-window view))
           (other (generate-new-buffer "*other*"))
           (second (split-window (get-buffer-window buffer) nil 'below)))
      (unwind-protect
          (progn
            (set-window-buffer second other)
            (set-window-buffer second view)
            (with-current-buffer view (imprimeur-xwidget--one-window second))
            (should (eq (window-buffer second) other))
            ;; Alone, it stays.
            (with-current-buffer view (imprimeur-xwidget--one-window first))
            (should (eq (window-buffer first) view)))
        (kill-buffer other)))
    (should (memq #'imprimeur-xwidget--one-window
                  (buffer-local-value 'window-buffer-change-functions view)))))

;;;; Teardown

(ert-deftest imprimeur-xwidget-killing-the-view-keeps-the-session ()
  (imprimeur-xwidget-test-with (buffer view)
    (let ((session (buffer-local-value 'imprimeur--session buffer))
          (timer (buffer-local-value 'imprimeur-xwidget--timer view)))
      (should (memq timer timer-list))
      (kill-buffer view)
      (should-not (memq timer timer-list))
      (should (memq session imprimeur--sessions))
      (should (one-window-p))
      (with-current-buffer buffer
        (should imprimeur-mode)
        (imprimeur-show))
      (let ((again (imprimeur--session-view session)))
        (should (buffer-live-p again))
        (should-not (eq again view))
        (should (get-buffer-window again))))))

(ert-deftest imprimeur-xwidget-killing-the-source-kills-the-view ()
  (imprimeur-xwidget-test-with (buffer view)
    (let ((timer (buffer-local-value 'imprimeur-xwidget--timer view)))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (kill-buffer buffer)
      (should-not (buffer-live-p view))
      (should-not (memq timer timer-list)))))

(ert-deftest imprimeur-xwidget-ending-the-mode-kills-the-view ()
  (imprimeur-xwidget-test-with (buffer view)
    (with-current-buffer buffer (imprimeur-mode -1))
    (should-not (buffer-live-p view))))

;;;; Jumping

(ert-deftest imprimeur-xwidget-jump-shows-a-hidden-view ()
  (imprimeur-xwidget-test-with (buffer view)
    (delete-window (get-buffer-window view))
    (should-not (get-buffer-window view))
    (execute-kbd-macro (kbd "M-g v"))
    (should (get-buffer-window view))
    (should (eq (window-buffer) buffer))))

(ert-deftest imprimeur-xwidget-jump-makes-a-killed-view-anew ()
  (imprimeur-xwidget-test-with (buffer view)
    (kill-buffer view)
    (execute-kbd-macro (kbd "M-g v"))
    (let* ((session (buffer-local-value 'imprimeur--session buffer))
           (again (imprimeur--session-view session)))
      (should (buffer-live-p again))
      (should (get-buffer-window again))
      (should (eql (imprimeur--session-jump session) 1)))))

(ert-deftest imprimeur-xwidget-jump-from-the-view-goes-back ()
  (imprimeur-xwidget-test-with (buffer view)
    (select-window (get-buffer-window view))
    (execute-kbd-macro (kbd "M-g v"))
    (should (eq (window-buffer) buffer))
    (should (get-buffer-window view))
    (should (equal (imprimeur-xwidget-test-called 'script) '(("imprimeur.postTop()"))))))

(ert-deftest imprimeur-xwidget-jump-from-the-view-finds-the-source-s-window ()
  ;; An action that does not dedicate the view's Emacs window leaves it free to take
  ;; the source, which must not show twice while the page goes.
  (let ((imprimeur-display-buffer-action '((display-buffer-in-direction) (direction . right))))
    (imprimeur-xwidget-test-with (buffer view)
      (let ((source (get-buffer-window buffer))
            (right (get-buffer-window view)))
        (should-not (window-dedicated-p right))
        (select-window right)
        (execute-kbd-macro (kbd "M-g v"))
        (should (eq (selected-window) source))
        (should (eq (window-buffer right) view))))))

(ert-deftest imprimeur-xwidget-jump-from-the-view-brings-the-source-back ()
  (let ((imprimeur-display-buffer-action '((display-buffer-same-window))))
    (imprimeur-xwidget-test-with (buffer view)
      (should (eq (window-buffer) view))
      (execute-kbd-macro (kbd "M-g v"))
      (should (one-window-p))
      (should (eq (window-buffer) buffer))
      (should (buffer-live-p view)))))

;;;; The page's side

(defun imprimeur-xwidget-test-paragraphs (count)
  "Return Org text of COUNT paragraphs of 1 to 15 lines."
  (mapconcat (lambda (number)
               (concat (format "Paragraph %d.\n" number)
                       (apply #'concat (make-list (% (* 7 number) 15) "Another line of this paragraph.\n"))
                       "\n"))
             (number-sequence 1 count) ""))

(defmacro imprimeur-xwidget-test-with-page (spec &rest body)
  "Run BODY with a view whose scripts run in a page in a headless Chromium.
SPEC is (BUFFER VIEW BROWSER): as for `imprimeur-xwidget-test-with',
with the real pandoc, and BROWSER showing the page's first revision."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,view ,browser) spec))
    `(progn
       (imprimeur-test-require "pandoc")
       (imprimeur-xwidget-test-with (,buffer ,view (imprimeur-xwidget-test-paragraphs 80) "pandoc")
         (imprimeur-test-cdp-with-browser ,browser
           (setq imprimeur-xwidget-test-script
                 (lambda (script) (imprimeur-test-cdp-eval ,browser script)))
           (imprimeur-test-cdp-navigate ,browser (imprimeur-url ,buffer))
           (imprimeur-test-wait-for
            (lambda () (imprimeur-test-cdp-eval ,browser "document.documentElement.dataset.revision")))
           ,@body)))))

(defun imprimeur-xwidget-test-top-line (browser)
  "Return the line of the block at the top of BROWSER's page."
  (imprimeur-test-cdp-eval browser "(() => {
  const above = [...document.querySelectorAll('#imprimeur-main > [data-line]')]
    .filter((block) => block.getBoundingClientRect().top <= 0);
  return Number(above[above.length - 1].dataset.line);
})()"))

(ert-deftest imprimeur-xwidget-a-key-in-the-view-moves-the-source ()
  (imprimeur-xwidget-test-with-page (buffer view browser)
    (let ((source (get-buffer-window buffer)))
      (imprimeur-test-cdp-eval browser "imprimeur.scrollBy(2000)")
      (imprimeur-test-wait-for
       (lambda ()
         (> (with-current-buffer buffer (line-number-at-pos (window-start source) t)) 1)))
      (imprimeur-test-wait-for
       (lambda ()
         (eql (imprimeur-xwidget-test-top-line browser)
              (with-current-buffer buffer (line-number-at-pos (window-start source) t)))))
      ;; To its end by a key, and the source goes with it.
      (let ((before (window-start source)))
        (select-window (get-buffer-window view))
        (execute-kbd-macro (kbd "M->"))
        (select-window source)
        (imprimeur-test-wait-for (lambda () (> (window-start source) before)))))))

(ert-deftest imprimeur-xwidget-only-a-scroll-as-the-reader-s-reaches-emacs ()
  ;; What the keys of xwidget's own mode do is silent; the same move as the wheel's is not.
  (imprimeur-xwidget-test-with-page (buffer view browser)
    (imprimeur-test-cdp-eval browser "window.scrollBy(0, 2000)")
    (imprimeur-test-cdp-eval browser "new Promise((resolve) => setTimeout(resolve, 400))")
    (should-not (seq-filter (lambda (message) (equal (plist-get message :type) "scroll"))
                            (imprimeur-test-cdp-posted browser ".imprimeur/post")))
    (imprimeur-test-cdp-eval browser "imprimeur.scrollBy(100)")
    (imprimeur-test-wait-for
     (lambda () (seq-filter (lambda (message) (equal (plist-get message :type) "scroll"))
                            (imprimeur-test-cdp-posted browser ".imprimeur/post"))))))

(ert-deftest imprimeur-xwidget-going-back-puts-point-at-the-page-s-top ()
  (imprimeur-xwidget-test-with-page (buffer view browser)
    (imprimeur-test-cdp-eval browser "imprimeur.scrollBy(3000)")
    (imprimeur-test-wait-for (lambda () (> (imprimeur-xwidget-test-top-line browser) 1)))
    (let ((line (imprimeur-xwidget-test-top-line browser))
          (source (get-buffer-window buffer)))
      (select-window (get-buffer-window view))
      (execute-kbd-macro (kbd "M-g v"))
      (should (eq (selected-window) source))
      (imprimeur-test-wait-for
       (lambda () (eql (with-current-buffer buffer (line-number-at-pos nil t)) line))))))

;;; imprimeur-xwidget-test.el ends here
