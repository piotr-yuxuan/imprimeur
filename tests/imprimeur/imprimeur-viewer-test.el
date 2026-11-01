;;; imprimeur-viewer-test.el --- Tests of the browser's desktop window  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 002, acceptance 9, and the umbrella plan's table of
;; resources): the browser reaches the page although no process's command
;; line holds the token; its profile is readable by the user only, under
;; the user's cache directory; ending the mode ends the browser and deletes
;; the profile, and so does closing its desktop window, after which the page
;; can open again; profiles left by an Emacs that no longer runs are deleted,
;; and nothing else; a missing browser is a user error naming its option,
;; which starts nothing; a failure after the session started ends it.

;;; Code:

(require 'ert)
(require 'seq)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur)

(defmacro imprimeur-viewer-test-with (buffer browser &rest body)
  "Run BODY with BUFFER visiting a scratch Org file in `imprimeur-mode'.
BROWSER is the browser program, and pandoc the fake one.  The buffer
is killed afterwards."
  (declare (indent 2))
  `(let* ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
          (imprimeur-browser-program ,browser)
          (,buffer (find-file-noselect
                    (expand-file-name "doc.org" (repo-test-git-tree '(("doc.org" . "Hello\n")))))))
     (unwind-protect
         (progn (with-current-buffer ,buffer (imprimeur-mode 1)) ,@body)
       (with-current-buffer ,buffer (set-buffer-modified-p nil))
       (kill-buffer ,buffer))))

(defun imprimeur-viewer-test-command-lines (text)
  "Return the command lines, of the processes readable here, that hold TEXT."
  (seq-filter (lambda (line) (string-search text line))
              (delq nil (mapcar (lambda (file)
                                  (ignore-errors
                                    (with-temp-buffer
                                      (insert-file-contents-literally file)
                                      (buffer-string))))
                                (file-expand-wildcards "/proc/[0-9]*/cmdline")))))

(ert-deftest imprimeur-viewer-reaches-the-page-without-showing-the-token ()
  (imprimeur-test-require "chromium")
  (with-current-buffer (get-buffer-create " *imprimeur-log*") (erase-buffer))
  (imprimeur-viewer-test-with buffer imprimeur-test-headless-chromium
    (let* ((session (buffer-local-value 'imprimeur--session buffer))
           (viewer (imprimeur--session-viewer session))
           (profile (process-get viewer :profile)))
      (imprimeur-test-wait-for (lambda () (eql (imprimeur--session-ready session) 1)) 30)
      (should-not (imprimeur-viewer-test-command-lines (imprimeur--session-token session)))
      (should (imprimeur-viewer-test-command-lines profile))
      (should (file-in-directory-p profile (getenv "XDG_CACHE_HOME")))
      (should (= (file-modes profile) #o700))
      (should (= (file-modes (expand-file-name "start.html" profile)) #o600))
      (with-current-buffer buffer (imprimeur-mode -1))
      (should-not (process-live-p viewer))
      (should-not (file-exists-p profile))
      (imprimeur-test-wait-for (lambda () (not (imprimeur-viewer-test-command-lines profile))))
      (should (equal (with-current-buffer " *imprimeur-log*" (buffer-string)) "")))))

(ert-deftest imprimeur-viewer-closing-the-desktop-window-deletes-its-profile ()
  (imprimeur-viewer-test-with buffer imprimeur-test-fake-browser
    (let* ((session (buffer-local-value 'imprimeur--session buffer))
           (first (imprimeur--session-viewer session))
           (profile (process-get first :profile)))
      (should (file-directory-p profile))
      (signal-process first 'TERM)
      (imprimeur-test-wait-for (lambda () (not (file-exists-p profile))))
      (should (buffer-local-value 'imprimeur-mode buffer))
      (with-current-buffer buffer (imprimeur-browse))
      (should (process-live-p (imprimeur--session-viewer session)))
      (should-not (eq (imprimeur--session-viewer session) first)))))

(ert-deftest imprimeur-viewer-sweeps-the-profiles-of-ended-emacs-processes ()
  (let* ((profiles (expand-file-name "imprimeur/" (getenv "XDG_CACHE_HOME")))
         (ended (make-process :name "test-ended" :command '("true") :noquery t :sentinel #'ignore))
         (dead (progn (imprimeur-test-wait-for (lambda () (not (process-live-p ended))))
                      (delete-process ended)
                      (process-id ended)))
         (stale (expand-file-name (format "chromium-%d-0badcafe" dead) profiles))
         (link (expand-file-name (format "chromium-%d-11111111" dead) profiles))
         (target (make-temp-file "target" t))
         (alive (expand-file-name (format "chromium-%d-00c0ffee" (emacs-pid)) profiles))
         (other (expand-file-name "other" profiles)))
    (dolist (directory (list stale alive other)) (make-directory directory t))
    (write-region "kept" nil (expand-file-name "file" target))
    (make-symbolic-link target link)
    (imprimeur-viewer-test-with _buffer imprimeur-test-fake-browser
      (should-not (file-exists-p stale))
      (should (file-symlink-p link))
      (should (file-exists-p (expand-file-name "file" target)))
      (should (file-directory-p alive))
      (should (file-directory-p other)))))

(ert-deftest imprimeur-viewer-needs-its-browser ()
  (let ((imprimeur-pandoc-program imprimeur-test-fake-pandoc)
        (imprimeur-browser-program "imprimeur-no-such-browser"))
    (with-temp-buffer
      (org-mode)
      (should (string-search "imprimeur-browser-program"
                             (cadr (should-error (imprimeur-mode 1) :type 'user-error))))
      (should-not imprimeur-mode)
      (should-not imprimeur--session)
      (should-not (process-live-p imprimeur-server--process)))))

(ert-deftest imprimeur-viewer-failing-to-open-ends-the-session ()
  (let ((process-environment (cons (concat "XDG_CACHE_HOME=" (make-temp-file "not-a-directory"))
                                   process-environment))
        (imprimeur-pandoc-program imprimeur-test-fake-pandoc)
        (imprimeur-browser-program imprimeur-test-fake-browser))
    (with-temp-buffer
      (org-mode)
      (should-error (imprimeur-mode 1) :type 'file-error)
      (should-not imprimeur-mode)
      (should-not imprimeur--session)
      (should-not imprimeur--sessions)
      (should-not (process-live-p imprimeur-server--process))
      (should-not (memq #'imprimeur--after-change after-change-functions)))))

;;; imprimeur-viewer-test.el ends here
