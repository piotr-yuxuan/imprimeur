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
;; A document decides whether its page survives being drawn, so a page that reports
;; and then dies must not keep the reloads going: dying within a minute of reporting
;; spends a chance, as not answering does, and it has two (code review of plan 004).
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
;; package compiles on a build without xwidgets, for which a child Emacs stands with
;; their primitives unbound, as the one Emacs of these tests has them.
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

(defun imprimeur-xwidget-test-decide (decide graphic built)
  "Return what the function DECIDE says with a GRAPHIC Emacs frame and a BUILT Emacs.
BUILT says whether this Emacs has xwidgets.  This holds only while DECIDE
runs: the rest of Emacs asks the same, and in batch would fail on a yes."
  (let ((featurep (symbol-function 'featurep)))
    (cl-letf (((symbol-function 'display-graphic-p) (lambda (&rest _) graphic))
              ((symbol-function 'featurep)
               (lambda (feature &rest rest)
                 (if (eq feature 'xwidget-internal) built (apply featurep feature rest)))))
      (funcall decide))))

(defmacro imprimeur-xwidget-test-fake (&rest body)
  "Run BODY with stand-ins for xwidget's primitives, as if an xwidget could run here."
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
                 ((symbol-function 'imprimeur--target)
                  (let ((decide (symbol-function 'imprimeur--target)))
                    (lambda () (imprimeur-xwidget-test-decide decide t t)))))
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
  ;; The option, a graphic Emacs frame, a build with xwidgets, a browser on the path,
  ;; and where the page goes, or the option that a refusal tells the reader to look at.
  (pcase-dolist (`(,target ,graphic ,built ,browser ,expected)
                 '((auto t t t xwidget)
                   (auto t nil t browser)
                   (auto nil t t browser)
                   (auto nil nil t browser)
                   (xwidget t t t xwidget)
                   (xwidget t nil t "imprimeur-target")
                   (xwidget nil t t "imprimeur-target")
                   (xwidget nil nil t "imprimeur-target")
                   (browser t t t browser)
                   (browser t nil t browser)
                   (browser nil t t browser)
                   (browser nil nil t browser)
                   (auto t t nil xwidget)
                   (auto t nil nil "imprimeur-browser-program")
                   (auto nil t nil "imprimeur-browser-program")
                   (xwidget t t nil xwidget)
                   (xwidget t nil nil "imprimeur-target")
                   (browser t t nil "imprimeur-browser-program")))
    (let ((imprimeur-target target)
          (imprimeur-browser-program (if browser imprimeur-test-fake-browser "/nonexistent/imprimeur-browser"))
          (row (list target graphic built browser)))
      (should (equal (cons row
                           (condition-case failure
                               (imprimeur-xwidget-test-decide #'imprimeur--target graphic built)
                             (user-error
                              (seq-find (lambda (option) (string-search option (cadr failure)))
                                        '("imprimeur-target" "imprimeur-browser-program")))))
                     (cons row expected))))))

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
  ;; All this holds however long the page has lasted.
  (pcase-dolist (`(,state ,event ,next ,action)
                 '((loading timeout retrying reload)
                   (loading waiting loading nil)
                   (loading ready live nil)
                   (loading closed loading nil)
                   (retrying timeout failed offer)
                   (retrying waiting retrying nil)
                   (retrying ready revived nil)
                   (retrying closed retrying nil)
                   (live timeout live nil)
                   (live waiting live nil)
                   (live ready live nil)
                   (revived timeout revived nil)
                   (revived waiting revived nil)
                   (revived ready revived nil)
                   (failed timeout failed nil)
                   (failed waiting failed nil)
                   (failed ready revived nil)
                   (failed closed failed nil)))
    (dolist (lasted '(0 59 60 100000))
      (should (equal (list state event lasted (imprimeur-xwidget--next state event lasted))
                     (list state event lasted (cons next action)))))))

(ert-deftest imprimeur-xwidget-watchdog-judges-a-page-lost ()
  ;; Lost within a minute, a page has spent that chance; lost later, it has two again.
  (pcase-dolist (`(,state ,lasted ,next ,action)
                 '((live 0 retrying reload)
                   (live 59 retrying reload)
                   (live 60 loading reload)
                   (live 100000 loading reload)
                   (revived 0 failed offer)
                   (revived 59 failed offer)
                   (revived 60 loading reload)
                   (revived 100000 loading reload)))
    (should (equal (list state lasted (imprimeur-xwidget--next state 'closed lasted))
                   (list state lasted (cons next action))))))

(ert-deftest imprimeur-xwidget-watchdog-bounds-the-reloads ()
  ;; The events of five rounds, how long the page lasts in each state, how many
  ;; reloads that takes and the state it ends in.
  (pcase-dolist (`(,events ,lasted ,reloads ,end)
                 '(;; It reports and dies at once, as a document can have it do.
                   ((ready closed) 0 1 failed)
                   ;; The same, and it takes longer than the watchdog waits.
                   ((timeout timeout ready closed) 0 1 failed)
                   ;; A page that lasts is brought back as often as it is lost.
                   ((ready closed) 60 5 loading)))
    (let ((state 'loading)
          (count 0))
      (dotimes (_ 5)
        (dolist (event events)
          (pcase-let ((`(,next . ,action) (imprimeur-xwidget--next state event lasted)))
            (setq state next)
            (when (eq action 'reload) (setq count (1+ count))))))
      (should (equal (list events lasted count state) (list events lasted reloads end))))))

(ert-deftest imprimeur-xwidget-a-page-that-keeps-dying-is-given-up ()
  ;; Through the session's own streams, whose last one closing is the page lost.
  (let ((imprimeur-xwidget--quiet 1000000))
    (imprimeur-xwidget-test-with (buffer view)
      (let* ((url (url-generic-parse-url (imprimeur-url buffer)))
             (port (url-port url))
             (base (format "/%s/.imprimeur/" (nth 1 (split-string (url-filename url) "/"))))
             (session (buffer-local-value 'imprimeur--session buffer)))
        (ert-with-message-capture messages
          (dotimes (_ 5)
            (let ((stream (imprimeur-test-http-stream port (concat base "events"))))
              (imprimeur-test-wait-for (lambda () (imprimeur--session-clients session)))
              (should (equal (car (imprimeur-test-http-post port (concat base "post") "{\"type\":\"ready\",\"rev\":1}"))
                             204))
              (delete-process stream)
              (imprimeur-test-wait-for (lambda () (not (imprimeur--session-clients session))))))
          (should (string-search "imprimeur-browse" messages)))
        (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'failed))
        (should (buffer-local-value 'mode-line-process view))
        (should-not (buffer-local-value 'imprimeur-xwidget--timer view))
        ;; The first load and one reload, and nothing is tried after that.
        (should (= (length (imprimeur-xwidget-test-called 'goto)) 2))))))

(ert-deftest imprimeur-xwidget-a-page-s-time-runs-from-its-coming-up ()
  (let ((now 5000.0))
    (imprimeur-xwidget-test-with (buffer view)
      (cl-letf (((symbol-function 'float-time) (lambda (&rest _) now)))
        (imprimeur-xwidget-note view 'ready)
        ;; A later revision is no new start, as typing would keep a page young.
        (setq now (+ now 59))
        (imprimeur-xwidget-note view 'ready)
        (setq now (+ now 1))
        (imprimeur-xwidget-note view 'closed)
        (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'loading))
        ;; Having come up anew, it is young again.
        (setq now (+ now 1000))
        (imprimeur-xwidget-note view 'ready)
        (setq now (+ now 59))
        (imprimeur-xwidget-note view 'closed)
        (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'retrying))))))

(ert-deftest imprimeur-xwidget-a-page-revived-has-its-own-time ()
  (let ((now 5000.0))
    (imprimeur-xwidget-test-with (buffer view)
      (cl-letf (((symbol-function 'float-time) (lambda (&rest _) now)))
        (imprimeur-xwidget-note view 'ready)
        (setq now (+ now 30))
        (imprimeur-xwidget-note view 'closed)
        (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'retrying))
        (setq now (+ now 1))
        (imprimeur-xwidget-note view 'ready)
        (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'revived))
        ;; Lost 39 s after it came back, though 70 s after it first came up, it has
        ;; spent its second chance: nothing more is tried.
        (setq now (+ now 39))
        (let ((loads (length (imprimeur-xwidget-test-called 'goto))))
          (imprimeur-xwidget-note view 'closed)
          (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'failed))
          (should (= (length (imprimeur-xwidget-test-called 'goto)) loads)))
        ;; Back even so, a later revision is no new start here either, and lasting
        ;; a minute gives it its two chances again.
        (imprimeur-xwidget-note view 'ready)
        (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'revived))
        (setq now (+ now 59))
        (imprimeur-xwidget-note view 'ready)
        (setq now (+ now 1))
        (imprimeur-xwidget-note view 'closed)
        (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'loading))))))

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
      ;; A page late for all that still counts, with no chance left.
      (imprimeur-xwidget-note view 'ready)
      (should (eq (buffer-local-value 'imprimeur-xwidget--state view) 'revived))
      (should-not (buffer-local-value 'mode-line-process view)))))

(ert-deftest imprimeur-xwidget-offers-what-works-from-the-view ()
  (let ((imprimeur-xwidget--wait 0.01))
    (imprimeur-xwidget-test-with (buffer view)
      (imprimeur-test-wait-for (lambda () (eq (buffer-local-value 'imprimeur-xwidget--state view) 'failed)))
      (with-current-buffer view (imprimeur-browse))
      (should (process-live-p (imprimeur--session-viewer (buffer-local-value 'imprimeur--session buffer)))))))

(ert-deftest imprimeur-xwidget-what-it-offers-may-find-no-browser ()
  ;; Those with no browser are those whom `auto' gives an xwidget.  They are told so,
  ;; and each try leaves no profile behind.
  (let* ((cache (make-temp-file "imprimeur-cache" t))
         (process-environment (cons (concat "XDG_CACHE_HOME=" cache) process-environment)))
    (imprimeur-xwidget-test-with (buffer view)
      (let ((imprimeur-browser-program "/nonexistent/imprimeur-browser"))
        (with-current-buffer view
          (should (string-search "imprimeur-browser-program"
                                 (cadr (should-error (imprimeur-browse) :type 'user-error)))))
        (should-not (imprimeur--session-viewer (buffer-local-value 'imprimeur--session buffer)))
        (should-not (directory-files cache nil "\\`[^.]"))))))

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
  ;; A page that has lasted, so that its loss is a new one.
  (let ((imprimeur-xwidget--quiet 0))
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
                       (list 'fake-xwidget (imprimeur-url buffer))))))))

;;;; The callback

(defconst imprimeur-xwidget-test-home "http://127.0.0.1:8000/0123abc/doc.org"
  "The address of a page in the tests of the callback.")

(defmacro imprimeur-xwidget-test-with-callback (callback &rest body)
  "Run BODY with stand-ins and CALLBACK, what a new view registers on its xwidget.
The view shows `imprimeur-xwidget-test-home'.  Emacs calls CALLBACK with the
xwidget and the type of each event, the rest being in `last-input-event'.  The
calls recorded for BODY are its own, and not those of opening the view."
  (declare (indent 1))
  (let ((view (make-symbol "view")))
    `(imprimeur-xwidget-test-fake
      (let* ((,view (imprimeur-xwidget-open imprimeur-xwidget-test-home (current-buffer) #'ignore))
             (,callback (nth 2 (seq-find (lambda (arguments) (eq (nth 1 arguments) 'callback))
                                         (imprimeur-xwidget-test-called 'put)))))
        (setq imprimeur-xwidget-test-calls nil)
        (unwind-protect
            (cl-letf (((symbol-function 'xwidget-buffer) (lambda (_) ,view)))
              ,@body)
          (kill-buffer ,view))))))

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
    (imprimeur-xwidget-test-with-callback callback
      (cl-letf (((symbol-function 'xwidget-webkit-uri) (lambda (_) uri)))
        (let ((last-input-event (list 'xwidget-event 'load-changed 'fake-xwidget stage)))
          (funcall callback 'fake-xwidget 'load-changed))
        (should (equal (list stage uri (imprimeur-xwidget-test-called 'goto))
                       (list stage uri (and back `((fake-xwidget ,imprimeur-xwidget-test-home))))))))))

(ert-deftest imprimeur-xwidget-forwards-a-script-result-and-nothing-else ()
  (imprimeur-xwidget-test-with-callback callback
    (let ((results nil))
      (let ((last-input-event (list 'xwidget-event 'javascript-callback 'fake-xwidget
                                    (lambda (value) (push value results)) 42)))
        (funcall callback 'fake-xwidget 'javascript-callback))
      (should (equal results '(42))))
    ;; What would prompt, write a file, rename a buffer or run a script in xwidget's
    ;; own callback, which a view must not have registered.
    (let ((default-directory (make-temp-file "imprimeur-download" t)))
      (cl-letf (((symbol-function 'read-file-name) (lambda (&rest _) (ert-fail "A prompt")))
                ((symbol-function 'url-copy-file) (lambda (&rest _) (ert-fail "A file")))
                ((symbol-function 'rename-buffer) (lambda (&rest _) (ert-fail "A new name")))
                ((symbol-function 'xwidget-webkit-title) (lambda (_) "A title"))
                ((symbol-function 'xwidget-webkit-uri) (lambda (_) imprimeur-xwidget-test-home)))
        (pcase-dolist (`(,type . ,rest)
                       '((download-callback "http://127.0.0.1/x" "text/plain" "x")
                         (decide-policy "http://127.0.0.1/x#y")
                         (load-changed "load-finished")
                         (unknown)))
          (let ((last-input-event `(xwidget-event ,type fake-xwidget ,@rest)))
            (funcall callback 'fake-xwidget type))))
      (should-not (directory-files default-directory nil "\\`[^.]"))
      (should-not imprimeur-xwidget-test-calls))))

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

;; Plan 026, with plan 009's "Keys": a skin's keys go to the page by a map of the view's
;; own, rebuilt when the skin changes; a key that the page takes runs nothing more, and
;; one that it declines runs what it has without that map, with the prefix argument.
;; Nothing with a modifier is forwarded, so `C-g' and `M-x' stay Emacs's.

(defmacro imprimeur-xwidget-test-with-keys (spec &rest body)
  "Run BODY as `imprimeur-xwidget-test-with' does, with the skin keyed registered.
SPEC is (BUFFER VIEW ANSWER): ANSWER is a function given the callback of each
script that a view runs with one.  It declares letters, a digit and the three named keys."
  (declare (indent 1))
  (pcase-let ((`(,buffer ,view ,answer) spec))
    `(let ((imprimeur-skin--registry (copy-alist imprimeur-skin--registry))
           (directory (make-temp-file "skin" t)))
       (dolist (file '("skin.css" "page.mjs"))
         (write-region "/* A file. */\n" nil (expand-file-name file directory) nil 'silent))
       (imprimeur-skin-define 'keyed :title "Keyed" :directory directory :stylesheets '("skin.css")
                              :module "page.mjs" :keys '("s" "q" "?" "\"" "1" "Enter" "Backspace" "Escape"))
       (imprimeur-xwidget-test-with (,buffer ,view)
         (cl-letf* ((stand-in (symbol-function 'xwidget-webkit-execute-script))
                    ((symbol-function 'xwidget-webkit-execute-script)
                     (lambda (xwidget script &optional callback)
                       (funcall stand-in xwidget script)
                       (when callback (funcall ,answer callback)))))
           ,@body)))))

(defun imprimeur-xwidget-test-press (event &optional argument)
  "Run the forward of this view as the key EVENT runs it, with the prefix ARGUMENT."
  (let ((last-command-event event)
        (current-prefix-arg argument))
    (call-interactively (key-binding (vector event) t))))

(ert-deftest imprimeur-xwidget-a-view-forwards-a-skin-s-keys ()
  (imprimeur-xwidget-test-with-keys (buffer view #'ignore)
    (with-current-buffer view
      (should-not (eq (key-binding (kbd "s") t) 'imprimeur-view-forward-key)))
    (with-current-buffer buffer (imprimeur-choose-skin "keyed"))
    (with-current-buffer view
      (dolist (key '("s" "q" "?" "\"" "1" "RET" "DEL" "<escape>"))
        (ert-info (key)
          (should (eq (key-binding (kbd key) t) 'imprimeur-view-forward-key))))
      ;; What it does not take, by case or by a modifier, stays what it was.
      (should-not (eq (key-binding (kbd "S") t) 'imprimeur-view-forward-key))
      (should (eq (key-binding (kbd "C-g") t) 'keyboard-quit))
      (should (eq (key-binding (kbd "M-x") t) 'execute-extended-command))
      (should (eq (key-binding (kbd "SPC") t) 'imprimeur-view-scroll-up))
      (should (eq (key-binding (kbd "M-g v") t) 'imprimeur-jump))
      ;; It names each to the page as the page names it, and nothing else.
      (pcase-dolist (`(,event . ,name) '((?s . "\"s\"") (?? . "\"?\"") (?\" . "\"\\\"\"") (?1 . "\"1\"")
                                         (?\r . "\"Enter\"") (?\d . "\"Backspace\"") (escape . "\"Escape\"")))
        (ert-info (name)
          (setq imprimeur-xwidget-test-calls nil)
          (imprimeur-xwidget-test-press event)
          (should (equal (imprimeur-xwidget-test-called 'script)
                         `((,(format "window.imprimeur?.key(%s) === true" name))))))))
    ;; A swap gives them back.
    (with-current-buffer buffer (imprimeur-choose-skin "base"))
    (with-current-buffer view
      (should (eq (key-binding (kbd "DEL") t) 'imprimeur-view-scroll-down))
      (should (eq (key-binding (kbd "q") t) 'quit-window)))))

(ert-deftest imprimeur-xwidget-a-view-made-anew-forwards-its-skin-s-keys ()
  (imprimeur-xwidget-test-with-keys (buffer view #'ignore)
    (with-current-buffer buffer (imprimeur-choose-skin "keyed"))
    (kill-buffer view)
    (with-current-buffer buffer (imprimeur-show))
    (with-current-buffer (imprimeur--session-view (buffer-local-value 'imprimeur--session buffer))
      (should (eq (key-binding (kbd "q") t) 'imprimeur-view-forward-key)))))

(ert-deftest imprimeur-xwidget-a-declined-key-does-its-old-job ()
  (let ((answer t)
        (quit 0)
        (described 0))
    (imprimeur-xwidget-test-with-keys (buffer view (lambda (callback) (funcall callback answer)))
      (with-current-buffer buffer (imprimeur-choose-skin "keyed"))
      (save-window-excursion
        (pop-to-buffer view)
        (cl-letf (((symbol-function 'quit-window)
                   (lambda (&rest _)
                     (interactive)
                     ;; In the Emacs window of the view, whichever is selected by then.
                     (should (eq (window-buffer) view))
                     (setq quit (1+ quit))))
                  ((symbol-function 'describe-mode) (lambda (&rest _) (interactive) (setq described (1+ described)))))
          (let ((scrolled (lambda (event &optional argument)
                            (setq imprimeur-xwidget-test-calls nil)
                            (imprimeur-xwidget-test-press event argument)
                            (cdr (mapcar #'car (imprimeur-xwidget-test-called 'script)))))
                (page (- (window-body-height nil t) (* next-screen-context-lines (window-font-height)))))
            ;; A key taken runs nothing more.
            (should-not (funcall scrolled ?\d))
            (imprimeur-xwidget-test-press ?q)
            (should (= quit 0))
            (imprimeur-xwidget-test-press ??)
            (should (= described 0))
            (setq answer nil)
            ;; Declined, DEL scrolls back as the wheel does, by what its prefix says.
            (should (equal (funcall scrolled ?\d) (list (format "imprimeur.scrollBy(%d)" (- page)))))
            (should (equal (funcall scrolled ?\d 3)
                           (list (format "imprimeur.scrollBy(%d)" (- (* 3 (window-font-height)))))))
            (imprimeur-xwidget-test-press ?q)
            (should (= quit 1))
            (imprimeur-xwidget-test-press ??)
            (should (= described 1))
            ;; A digit is the start of a prefix, as it was.
            (let ((prefix-arg nil))
              (imprimeur-xwidget-test-press ?1)
              (should (equal prefix-arg 1)))
            ;; An answer that comes after the view has gone does nothing.
            (let ((late nil))
              (cl-letf (((symbol-function 'xwidget-webkit-execute-script)
                         (lambda (_xwidget _script callback) (setq late callback))))
                (imprimeur-xwidget-test-press ?q))
              (kill-buffer view)
              (funcall late nil)
              (should (= quit 1)))))))))

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
  (let* ((package (expand-file-name "imprimeur" repo-test-root))
         (compile (lambda (file)
                    ;; A build without xwidgets has no such primitive, and warnings are errors.
                    (repo-test-emacs
                     (list "-L" package
                           "--eval" (prin1-to-string
                                     '(mapatoms (lambda (symbol)
                                                  (when (and (primitive-function-p (symbol-function symbol))
                                                             (string-search "xwidget" (symbol-name symbol)))
                                                    (fmakunbound symbol)))))
                           "-l" (expand-file-name "scripts/lint.el" repo-test-root)
                           "-f" "repo-lint-compile" file)))))
    (dolist (file (directory-files package t "\\.el\\'"))
      (should (equal (cons file (car (funcall compile file))) (cons file 0))))
    ;; What stands for such a build refuses a primitive that nothing declares.
    (let ((result (funcall compile (expand-file-name
                                    "undeclared.el"
                                    (repo-test-tree
                                     '(("undeclared.el" . ";;; undeclared.el --- Undeclared  -*- lexical-binding: t; -*-
(defun undeclared-f (xwidget) (kill-xwidget xwidget))
;;; undeclared.el ends here
")))))))
      (should (equal (car result) 1))
      (should (string-search "kill-xwidget" (cdr result))))))

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

(ert-deftest imprimeur-xwidget-quitting-keeps-a-source-shown-twice ()
  ;; Emacs documents that it runs this hook with the view current for an Emacs window
  ;; that has just stopped showing the view too.  That Emacs window shows the source
  ;; now, as does another, and two Emacs windows may rightly do that.
  (let ((imprimeur-display-buffer-action '((display-buffer-same-window))))
    (imprimeur-xwidget-test-with (buffer view)
      (let* ((window (selected-window))
             (other (split-window window)))
        (set-window-buffer other buffer)
        (with-current-buffer view (quit-window))
        (should (eq (window-buffer window) buffer))
        (with-current-buffer view (imprimeur-xwidget--one-window window))
        (should (eq (window-buffer window) buffer))
        (should (eq (window-buffer other) buffer))))))

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

(ert-deftest imprimeur-xwidget-jump-shows-a-hidden-view-with-its-page ()
  ;; It hides with its page connected and showing the text, and goes there at once.
  (imprimeur-xwidget-test-with (buffer view)
    (let* ((url (url-generic-parse-url (imprimeur-url buffer)))
           (port (url-port url))
           (base (format "/%s/.imprimeur/" (nth 1 (split-string (url-filename url) "/"))))
           (session (buffer-local-value 'imprimeur--session buffer))
           (stream (imprimeur-test-http-stream port (concat base "events"))))
      (imprimeur-test-wait-for (lambda () (imprimeur--session-clients session)))
      (imprimeur-test-http-post port (concat base "post") "{\"type\":\"ready\",\"rev\":1}")
      (delete-window (get-buffer-window view))
      (execute-kbd-macro (kbd "M-g v"))
      (should (get-buffer-window view))
      (should (eq (window-buffer) buffer))
      (imprimeur-test-wait-for (lambda () (assoc "jump" (imprimeur-test-http-events stream))))
      (delete-process stream))))

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

(ert-deftest imprimeur-xwidget-copy-leaves-the-soft-hyphens-out ()
  ;; Plan 021, by plan 009's "Copying": xwidget's own command copies what the selection
  ;; says, which holds U+00AD in WebKit, so the view remaps it.
  (imprimeur-xwidget-test-with (_buffer view)
    (with-current-buffer view
      (should (eq (command-remapping 'xwidget-webkit-copy-selection-as-kill) #'imprimeur-view-copy-selection))
      (let ((kill-ring nil))
        (cl-letf (((symbol-function 'xwidget-webkit-execute-script)
                   (lambda (_xwidget script callback)
                     (should (string-search "getSelection()" script))
                     (funcall callback "Une ty\u00ADpo\u00ADgra\u00ADphie."))))
          (call-interactively #'imprimeur-view-copy-selection))
        (should (equal kill-ring '("Une typographie.")))))))

;;; imprimeur-xwidget-test.el ends here
