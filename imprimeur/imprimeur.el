;;; imprimeur.el --- Typeset live previews of Org and Markdown  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; Author: piotr-yuxuan <piotr-yuxuan@users.noreply.github.com>
;; Maintainer: piotr-yuxuan <piotr-yuxuan@users.noreply.github.com>
;; URL: https://github.com/piotr-yuxuan/imprimeur
;; Version: 0.0.0
;; Package-Requires: ((emacs "30.1"))
;; Keywords: hypermedia, wp, tools

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the licences
;; for more details.

;;; Commentary:

;; imprimeur renders the current buffer, Org, Markdown or another format
;; that pandoc reads, into a typeset page shown in a browser's desktop
;; window, beside the Emacs frame.  The page follows the unsaved text
;; while you type.
;;
;; `imprimeur-mode' starts a session for the buffer and opens its page in
;; Chromium's own desktop window: a loopback HTTP server serves the page
;; under a random token, pandoc renders the text a moment after each
;; change, and the page fetches each new revision, sanitises it and shows
;; it.  Documents are untrusted unless `trusted-content-p' says otherwise;
;; see the README for the security model.

;;; Code:

(require 'cl-lib)
(require 'xdg)
(require 'imprimeur-palette)
(require 'imprimeur-render)
(require 'imprimeur-server)
(require 'imprimeur-sync)
;; Loaded when a session starts: see imprimeur-server.el.
(declare-function url-hexify-string "url-util" (string &optional allowed-chars))

(defcustom imprimeur-render-delay 0.3
  "Seconds of quiet after a change before the page is rendered again."
  :type 'number
  :group 'imprimeur)

(defcustom imprimeur-render-max-delay 2.0
  "Seconds after which a render happens even while typing continues."
  :type 'number
  :group 'imprimeur)

(defcustom imprimeur-remote-images 'trusted
  "Whether the page loads images from the network.
nil never; `trusted' for documents that `trusted-content-p' accepts;
t always, which lets a document track that you read it."
  :type '(choice (const :tag "Never" nil)
                 (const :tag "For trusted documents" trusted)
                 (const :tag "Always" t))
  :group 'imprimeur)

(defcustom imprimeur-browser-program "chromium"
  "The Chromium, or a browser that takes its options, showing the page.
Each session's desktop window has a profile of its own, under the user's
cache directory, deleted when that desktop window closes or the session
ends."
  :type 'string
  :group 'imprimeur)

(defcustom imprimeur-mermaid-script nil
  "The Mermaid script with which the page draws diagrams.
nil finds the copy beside the program mmdc, in the tree of mermaid-cli
as nixpkgs and npm install it; an absolute file name, or one under ~,
uses that file, which must be a classic script, not a module, that
sets the global mermaid, as mermaid.min.js does.  Without a script a
diagram shows as code: the page never fetches one from the network."
  :type '(choice (const :tag "Beside mmdc" nil)
                 (file :must-match t))
  :group 'imprimeur)

(cl-defstruct (imprimeur--session (:constructor imprimeur--session-create) (:copier nil))
  "The state of one buffer's preview."
  buffer token root page reader trusted
  (revision 0) html meta error warnings ready
  render (sent-tick -1) (rendered-tick -1) first-change last-change
  timer clients viewer palette)

(defvar imprimeur--sessions nil
  "The live sessions.")

(defvar-local imprimeur--session nil
  "The session of this buffer, or nil.")
(put 'imprimeur--session 'permanent-local t)

(defvar imprimeur--poll-timer nil
  "The timer that notices changes made without the change hooks.")

(defvar imprimeur--asset-version nil
  "The random part of the asset URLs, drawn when the server starts.")

(defconst imprimeur--assets
  '(("js/runtime.mjs" . "text/javascript; charset=utf-8")
    ("js/blocks.mjs" . "text/javascript; charset=utf-8")
    ("js/hash.mjs" . "text/javascript; charset=utf-8")
    ("js/line-map.mjs" . "text/javascript; charset=utf-8")
    ("js/sync.mjs" . "text/javascript; charset=utf-8")
    ("css/base.css" . "text/css; charset=utf-8")
    ("skins/minitel/skin.css" . "text/css; charset=utf-8")
    ("vendor/dompurify/purify.es.mjs" . "text/javascript; charset=utf-8")
    ("mermaid.js" . "text/javascript; charset=utf-8"))
  "The asset files the page may load, with their media types.")

(defconst imprimeur--media-limit (* 32 1024 1024)
  "The size, in bytes, from which a file is served by range only.")

(defun imprimeur--asset-file (name)
  "Return the file of the asset NAME, or nil when it has none.
Only the names in `imprimeur--assets' have one, among the package's
assets.  That of mermaid.js is the regular file that
`imprimeur-mermaid-script' names or, when that is nil, the copy found
from the true name of the program mmdc, if any."
  (let ((tree "lib/node_modules/@mermaid-js/mermaid-cli/node_modules/mermaid/dist/mermaid.min.js"))
    (cond ((not (equal name "mermaid.js"))
           (and (assoc name imprimeur--assets) (expand-file-name name imprimeur-render-assets)))
          (imprimeur-mermaid-script
           (and (file-regular-p imprimeur-mermaid-script)
                (expand-file-name imprimeur-mermaid-script)))
          (t
           (when-let* ((program (executable-find "mmdc"))
                       (prefix (locate-dominating-file (file-truename program) tree)))
             (expand-file-name tree prefix))))))

(defun imprimeur--schedule (state now)
  "Decide what a session does next, from STATE at time NOW.
STATE is a plist: :tick, the buffer's modification tick, and
:rendered-tick, the one last sent to pandoc; :rendering, non-nil while
pandoc runs; :clients, the number of open pages; :first-change and
:last-change, the times of the first and last change not yet
rendered, or nil; :delay and :max-delay, in seconds.  Return `idle',
`render', or the seconds to wait before deciding again."
  (let ((due (and (plist-get state :last-change)
                  (min (+ (plist-get state :last-change) (plist-get state :delay))
                       (+ (plist-get state :first-change) (plist-get state :max-delay))))))
    (cond ((or (zerop (plist-get state :clients)) (plist-get state :rendering)
               (= (plist-get state :tick) (plist-get state :rendered-tick)))
           'idle)
          ((or (not due) (>= now due)) 'render)
          (t (- due now)))))

(defun imprimeur--remote-images-p (session)
  "Return non-nil if the page of SESSION may load remote images."
  (pcase imprimeur-remote-images
    ('t t)
    ('trusted (imprimeur--session-trusted session))))

(defun imprimeur--broadcast (session event data)
  "Send EVENT with DATA to every page of SESSION."
  (dolist (client (imprimeur--session-clients session))
    (imprimeur-server-send-event client event data)))

(defun imprimeur--rendered (session outcome)
  "Record OUTCOME, a render's result, in SESSION, and tell its pages."
  (setf (imprimeur--session-render session) nil
        (imprimeur--session-rendered-tick session) (imprimeur--session-sent-tick session))
  (if (eq (car outcome) :ok)
      (progn
        (setf (imprimeur--session-revision session) (1+ (imprimeur--session-revision session))
              (imprimeur--session-html session) (nth 1 outcome)
              (imprimeur--session-meta session) (nth 2 outcome)
              (imprimeur--session-warnings session) (nth 3 outcome)
              (imprimeur--session-error session) nil)
        (imprimeur--broadcast session "revision" (list :rev (imprimeur--session-revision session))))
    (setf (imprimeur--session-error session) (nth 2 outcome))
    (imprimeur--broadcast session "error" (list :message (format "%s" (nth 2 outcome)))))
  (imprimeur--advance session))

(defun imprimeur--advance (session)
  "Act on the scheduling decision for SESSION: render, wait, or rest."
  (when-let* ((timer (imprimeur--session-timer session))) (cancel-timer timer))
  (setf (imprimeur--session-timer session) nil)
  (when (buffer-live-p (imprimeur--session-buffer session))
    (with-current-buffer (imprimeur--session-buffer session)
      ;; A change of text properties alone leaves the text as rendered.
      (when (= (buffer-chars-modified-tick) (imprimeur--session-rendered-tick session))
        (setf (imprimeur--session-first-change session) nil
              (imprimeur--session-last-change session) nil))
      (let ((decision (imprimeur--schedule
                       (list :tick (buffer-chars-modified-tick)
                             :rendered-tick (imprimeur--session-rendered-tick session)
                             :rendering (imprimeur--session-render session)
                             :clients (length (imprimeur--session-clients session))
                             :first-change (imprimeur--session-first-change session)
                             :last-change (imprimeur--session-last-change session)
                             :delay imprimeur-render-delay :max-delay imprimeur-render-max-delay)
                       (float-time))))
        (cond ((numberp decision)
               (setf (imprimeur--session-timer session)
                     (run-at-time decision nil #'imprimeur--advance session)))
              ((eq decision 'render)
               (let* ((reader (imprimeur--session-reader session))
                      (text (if (equal reader "org")
                                (imprimeur-sync-org-text)
                              (save-restriction (widen) (buffer-substring-no-properties
                                                         (point-min) (point-max)))))
                      (directory (if (file-remote-p default-directory) temporary-file-directory
                                   default-directory)))
                 ;; The slot and the tick are set before pandoc reads its
                 ;; input: writing it lets timers and sentinels run, which
                 ;; must see this render as under way.
                 (setf (imprimeur--session-sent-tick session) (buffer-chars-modified-tick)
                       (imprimeur--session-first-change session) nil
                       (imprimeur--session-last-change session) nil
                       (imprimeur--session-render session) t)
                 (let ((process (imprimeur-render-start
                                 (list :program imprimeur-pandoc-program :directory directory
                                       :text text
                                       :arguments (imprimeur-render-arguments
                                                   reader (imprimeur--session-trusted session)
                                                   (imprimeur--remote-images-p session)
                                                   (imprimeur-render-languages imprimeur-pandoc-program)))
                                 (lambda (outcome) (imprimeur--rendered session outcome)))))
                   ;; A render that ended while its input was written has
                   ;; called back already, and emptied the slot.
                   (when (eq (imprimeur--session-render session) t)
                     (setf (imprimeur--session-render session) process))))))))))

(defun imprimeur--after-change (&rest _)
  "Note a change of the buffer's text, and schedule a render."
  (when-let* ((session imprimeur--session)
              ((memq session imprimeur--sessions)))
    (let ((now (float-time)))
      (unless (imprimeur--session-first-change session)
        (setf (imprimeur--session-first-change session) now))
      (setf (imprimeur--session-last-change session) now)
      (imprimeur--advance session))))
(put 'imprimeur--after-change 'permanent-local-hook t)

(defun imprimeur--poll ()
  "Notice text changes that ran no change hook, in every session.
Such are the edits made in an indirect buffer, which share the text."
  (dolist (session imprimeur--sessions)
    (when (and (buffer-live-p (imprimeur--session-buffer session))
               (not (imprimeur--session-first-change session))
               (/= (buffer-chars-modified-tick (imprimeur--session-buffer session))
                   (imprimeur--session-rendered-tick session)))
      (setf (imprimeur--session-first-change session) (float-time)
            (imprimeur--session-last-change session) (float-time))
      (imprimeur--advance session))))

(defun imprimeur--palette (session &optional connection)
  "Send the palette of SESSION's buffer to its pages, if it changed.
The session remembers the palette its pages have.  CONNECTION, a page
that has just connected, gets the palette even when it is unchanged."
  (let ((palette (imprimeur-palette (imprimeur--session-buffer session))))
    (cond ((not (equal palette (imprimeur--session-palette session)))
           (setf (imprimeur--session-palette session) palette)
           (imprimeur--broadcast session "palette" palette))
          (connection (imprimeur-server-send-event connection "palette" palette)))))

(defun imprimeur--recolour ()
  "Send each session's palette to its pages, where it changed."
  (mapc #'imprimeur--palette imprimeur--sessions))

(defun imprimeur--connect (session connection)
  "Make CONNECTION an event stream of SESSION and send it the state."
  (imprimeur-server-stream connection
                           (lambda (closed)
                             (setf (imprimeur--session-clients session)
                                   (delq closed (imprimeur--session-clients session)))))
  (push connection (imprimeur--session-clients session))
  (imprimeur--palette session connection)
  (when (> (imprimeur--session-revision session) 0)
    (imprimeur-server-send-event connection "revision"
                                 (list :rev (imprimeur--session-revision session))))
  (when (imprimeur--session-error session)
    (imprimeur-server-send-event connection "error"
                                 (list :message (format "%s" (imprimeur--session-error session)))))
  (imprimeur--advance session))

(defun imprimeur--document (session)
  "Return the latest revision of SESSION, for the page, as JSON.
Its format is the reader's name without extensions, such as gfm."
  (json-serialize (list :rev (imprimeur--session-revision session)
                        :format (car (split-string (imprimeur--session-reader session) "[+-]"))
                        :html (or (imprimeur--session-html session) "")
                        :title (or (plist-get (imprimeur--session-meta session) :title) "")
                        :lang (or (plist-get (imprimeur--session-meta session) :lang) "")
                        :error (format "%s" (or (imprimeur--session-error session) ""))
                        :warnings (or (imprimeur--session-warnings session) ""))))

(defun imprimeur--receive (session body)
  "Act on the message BODY posted by a page of SESSION; return a status."
  (let ((message (imprimeur-server-parse-message body)))
    (pcase (plist-get message :type)
      ('ready
       (setf (imprimeur--session-ready session) (plist-get message :rev))
       (with-current-buffer (imprimeur--session-buffer session) (imprimeur-sync-page-ready))
       204)
      ('open
       (pcase (imprimeur-server-open-target (plist-get message :url) (imprimeur-server-start)
                                            (imprimeur--session-token session)
                                            (imprimeur--session-root session))
         (`(:browse ,url) (browse-url url) 204)
         (`(:visit ,file) (find-file-other-window file) 204)
         (_ (message "The page's link leads to no web address, and to no document or media file under the root")
            400)))
      (_ 400))))

(defun imprimeur--serve-file (connection file type headers &optional range)
  "Send FILE of media TYPE on CONNECTION, with HEADERS, as unibyte bytes.
RANGE is the value of a GET's Range header, or nil, which
`imprimeur-server-parse-range' reads: one range is answered 206 with
its bytes, the only ones read, and any other range in bytes 416.
Without a range, a file of `imprimeur--media-limit' bytes or more is
refused."
  (let* ((size (file-attribute-size (file-attributes file)))
         (part (imprimeur-server-parse-range range size)))
    (cond ((eq part 'unsatisfiable)
           (imprimeur-server-respond connection 416 nil nil
                                     (cons (cons "Content-Range" (format "bytes */%d" size)) headers)))
          ((and (not part) (>= size imprimeur--media-limit))
           (imprimeur-log "Refused %s whole, of %d bytes" file size)
           (imprimeur-server-respond connection 404))
          (t
           (imprimeur-server-respond
            connection (if part 206 200) type
            (with-temp-buffer
              (set-buffer-multibyte nil)
              (insert-file-contents-literally file nil (car part) (and part (1+ (cdr part))))
              (buffer-string))
            (if part
                (cons (cons "Content-Range" (format "bytes %d-%d/%d" (car part) (cdr part) size))
                      headers)
              headers))))))

(defconst imprimeur--routes
  (list (cons ".imprimeur/events"
              (lambda (session connection _request) (imprimeur--connect session connection)))
        (cons ".imprimeur/doc"
              (lambda (session connection _request)
                (imprimeur-server-respond connection 200 "application/json"
                                          (imprimeur--document session))))
        (cons ".imprimeur/post"
              (lambda (session connection request)
                (imprimeur-server-respond connection
                                          (imprimeur--receive session (plist-get request :body))))))
  "A session's fixed paths, each with the function that serves it.
The function receives the session, the connection and the request.")

(defun imprimeur--serve (session connection request rest)
  "Serve REST, the path after the token, of SESSION on CONNECTION.
REQUEST is the parsed request."
  (let* ((assets (concat ".imprimeur/a/" imprimeur--asset-version "/"))
         (name (and (string-prefix-p assets rest) (substring rest (length assets))))
         (asset (imprimeur--asset-file name))
         (route (cdr (assoc rest imprimeur--routes)))
         (media (imprimeur-server-local-file (imprimeur--session-root session) rest
                                             (mapcar #'car imprimeur-server-media-types))))
    (cond
     (route (funcall route session connection request))
     (asset
      (imprimeur--serve-file connection asset (cdr (assoc name imprimeur--assets))
                             '(("Cache-Control" . "max-age=31536000, immutable"))))
     ((equal rest (imprimeur--session-page session))
      (imprimeur-server-respond
       connection 200 "text/html; charset=utf-8"
       (with-temp-buffer
         (insert-file-contents (expand-file-name "page/index.html" imprimeur-render-assets))
         (replace-regexp-in-string
          "{{assets}}" (format "/%s/%s" (imprimeur--session-token session) assets)
          (string-replace "{{mermaid}}" (if (imprimeur--asset-file "mermaid.js") " data-mermaid" "")
                          (buffer-string))
          t t))
       (and (imprimeur--remote-images-p session)
            `(("Content-Security-Policy" . ,imprimeur-server-csp-remote)))))
     (media
      (imprimeur--serve-file connection media
                             (cdr (assoc (downcase (file-name-extension media))
                                         imprimeur-server-media-types))
                             '(("Accept-Ranges" . "bytes"))
                             ;; RFC 9110 defines ranges for GET alone.
                             (and (equal (plist-get request :method) "GET")
                                  (cdr (assoc "range" (plist-get request :headers))))))
     (t (imprimeur-log "Refused %s" rest)
        (imprimeur-server-respond connection 404)))))

(defun imprimeur--viewer-exited (viewer _event)
  "Delete the profile of the browser process VIEWER once it has exited.
The browser's helper processes write in it for a moment longer, so
the deletion is tried for a second, then given up with a log line."
  (let ((profile (process-get viewer :profile))
        (deadline (+ (float-time) 1))
        (failure nil))
    (unless (process-live-p viewer)
      (while (and (file-directory-p profile) (< (float-time) deadline))
        (condition-case error
            (delete-directory profile t)
          (file-error (setq failure error)
                      (sleep-for 0.05))))
      (when (file-directory-p profile)
        (imprimeur-log "Could not delete the profile %s: %S" profile failure)))))

(defun imprimeur--teardown (session)
  "End SESSION and what it owns; and the server, if SESSION was the last.
Its browser has a second to close after SIGTERM, then is killed."
  (when (processp (imprimeur--session-render session))
    (imprimeur-render-cancel (imprimeur--session-render session)))
  (when-let* ((timer (imprimeur--session-timer session))) (cancel-timer timer))
  (dolist (client (imprimeur--session-clients session))
    (imprimeur-server-send-event client "close" '(:reason "ended"))
    (delete-process client))
  (imprimeur-server-unregister (imprimeur--session-token session))
  (when-let* ((viewer (imprimeur--session-viewer session)))
    (when (process-live-p viewer)
      (signal-process viewer 'TERM)
      (let ((deadline (+ (float-time) 1)))
        (while (and (process-live-p viewer) (< (float-time) deadline))
          (accept-process-output viewer 0.05)))
      (delete-process viewer))
    (imprimeur--viewer-exited viewer nil))
  (setq imprimeur--sessions (delq session imprimeur--sessions))
  (unless imprimeur--sessions
    (imprimeur-server-stop)
    (when imprimeur--poll-timer (cancel-timer imprimeur--poll-timer))
    (setq imprimeur--poll-timer nil)
    (imprimeur-palette-unwatch #'imprimeur--recolour)
    (remove-hook 'kill-emacs-hook #'imprimeur-stop-all)))

(defun imprimeur--major-mode-changed ()
  "End the session when the new major mode has no reader; else keep it.
A session kept sends its pages the palette, if the new mode changes it."
  (when-let* ((session imprimeur--session))
    (if-let* ((reader (imprimeur-reader)))
        (progn
          (setf (imprimeur--session-reader session) reader)
          (imprimeur--palette session))
      (imprimeur-mode -1))))
(put 'imprimeur--major-mode-changed 'permanent-local-hook t)

(defun imprimeur--start ()
  "Start the session of the current buffer."
  (let ((reader (imprimeur-reader))
        (root (unless (file-remote-p default-directory)
                (expand-file-name (or (locate-dominating-file default-directory ".git")
                                      default-directory)))))
    (unless reader
      (user-error "No pandoc reader for this buffer; see `imprimeur-reader-alist'"))
    (unless (executable-find imprimeur-pandoc-program)
      (user-error "No pandoc program %s; see `imprimeur-pandoc-program'" imprimeur-pandoc-program))
    (unless (executable-find imprimeur-browser-program)
      (user-error "No browser program %s; see `imprimeur-browser-program'" imprimeur-browser-program))
    (require 'url-util)
    (unless (process-live-p imprimeur-server--process)
      (setq imprimeur--asset-version (format "%08x" (random #xffffffff))))
    (imprimeur-server-start)
    (let ((session (imprimeur--session-create
                    :buffer (current-buffer) :root root :reader reader
                    :trusted (trusted-content-p)
                    :page (if (and buffer-file-name root)
                              (mapconcat #'url-hexify-string
                                         (split-string (file-relative-name buffer-file-name root) "/")
                                         "/")
                            "untitled")
                    ;; 128 bits from the system's random source.
                    :token (with-temp-buffer
                             (set-buffer-multibyte nil)
                             (call-process "head" "/dev/urandom" t nil "-c" "16")
                             (mapconcat (lambda (byte) (format "%02x" byte)) (buffer-string) "")))))
      (imprimeur-server-register (imprimeur--session-token session)
                                 (lambda (connection request rest)
                                   (imprimeur--serve session connection request rest)))
      (push session imprimeur--sessions)
      (setq imprimeur--session session)
      (unless imprimeur--poll-timer
        (setq imprimeur--poll-timer (run-at-time 1 1 #'imprimeur--poll)))
      (add-hook 'kill-emacs-hook #'imprimeur-stop-all)
      (imprimeur-palette-watch #'imprimeur--recolour)
      (add-hook 'after-change-functions #'imprimeur--after-change nil t)
      (add-hook 'after-change-major-mode-hook #'imprimeur--major-mode-changed nil t)
      (add-hook 'kill-buffer-hook #'imprimeur--stop nil t)
      (imprimeur-sync-start (lambda (event data) (imprimeur--broadcast session event data)))
      (imprimeur-browse))))

(defun imprimeur--stop ()
  "End the session of the current buffer, if this buffer owns it.
An indirect buffer cloned from the owner shares its session, and only
forgets it."
  (imprimeur-sync-stop)
  (when (and imprimeur--session (eq (imprimeur--session-buffer imprimeur--session) (current-buffer)))
    (imprimeur--teardown imprimeur--session))
  (setq imprimeur--session nil)
  (remove-hook 'after-change-functions #'imprimeur--after-change t)
  (remove-hook 'after-change-major-mode-hook #'imprimeur--major-mode-changed t)
  (remove-hook 'kill-buffer-hook #'imprimeur--stop t))
(put 'imprimeur--stop 'permanent-local-hook t)

;;;###autoload
(define-minor-mode imprimeur-mode
  "Show this buffer typeset in a live page.
The page opens in a browser's desktop window and follows the unsaved
text; see `imprimeur-browse' and `imprimeur-copy-url'.  The mode
survives a change of major mode when the new mode has a reader in
`imprimeur-reader-alist', and ends otherwise."
  :lighter " Imprimeur"
  (if imprimeur-mode
      ;; Turned on again, by a mode hook after the major mode changed for
      ;; one, the buffer keeps its session.
      (unless (memq imprimeur--session imprimeur--sessions)
        (condition-case failure
            (imprimeur--start)
          (error (imprimeur--stop)
                 (setq imprimeur-mode nil)
                 (signal (car failure) (cdr failure)))))
    (imprimeur--stop)))
(put 'imprimeur-mode 'permanent-local t)

(defun imprimeur-url (&optional buffer)
  "Return the URL of the page of BUFFER, or of the current buffer."
  (let ((session (buffer-local-value 'imprimeur--session (or buffer (current-buffer)))))
    (unless session (user-error "No imprimeur session in this buffer"))
    (format "http://127.0.0.1:%d/%s/%s" (imprimeur-server-start)
            (imprimeur--session-token session) (imprimeur--session-page session))))

(defun imprimeur-browse ()
  "Open the page of this buffer in a desktop window of the browser.
The browser is `imprimeur-browser-program'.  It starts on a file in
its profile, readable by you only, which leads to the page: no
process's arguments show the session's token.  Profiles left by an
Emacs that no longer runs are deleted."
  (interactive)
  (let ((session (or imprimeur--session (user-error "No imprimeur session in this buffer")))
        (profiles (expand-file-name "imprimeur/" (xdg-cache-home))))
    (if (process-live-p (imprimeur--session-viewer session))
        (message "The page is open already; `imprimeur-copy-url' gives its address")
      (with-file-modes #o700 (make-directory profiles t))
      (dolist (stale (directory-files profiles t "\\`chromium-[0-9]+-[0-9a-f]+\\'" t))
        (unless (or (not (eq t (file-attribute-type (file-attributes stale))))
                    (process-attributes (string-to-number (nth 1 (split-string
                                                                  (file-name-nondirectory stale) "-")))))
          (delete-directory stale t)))
      (let* ((profile (expand-file-name (format "chromium-%d-%08x" (emacs-pid) (random #xffffffff))
                                        profiles))
             (start (expand-file-name "start.html" profile)))
        (with-file-modes #o700 (make-directory profile))
        (with-file-modes #o600
          (write-region (concat "<!doctype html>\n<meta charset=\"utf-8\">\n"
                                "<meta http-equiv=\"refresh\" content=\"0;url=" (imprimeur-url) "\">\n")
                        nil start nil 'silent))
        (setf (imprimeur--session-viewer session)
              (make-process :name "imprimeur-chromium" :buffer nil :noquery t
                            :connection-type 'pipe :sentinel #'imprimeur--viewer-exited
                            :command (list imprimeur-browser-program
                                           (concat "--user-data-dir=" profile)
                                           (concat "--app=file://"
                                                   (mapconcat #'url-hexify-string
                                                              (split-string start "/") "/"))
                                           "--no-first-run" "--no-default-browser-check"
                                           "--disable-background-networking"
                                           "--disable-component-update" "--disable-sync")))
        (process-put (imprimeur--session-viewer session) :profile profile)))))

(defun imprimeur-copy-url ()
  "Copy the URL of this buffer's page; anyone with it can read the page."
  (interactive)
  (kill-new (imprimeur-url))
  (message "Copied the page's URL"))

(defun imprimeur-stop-all ()
  "End every imprimeur session."
  (interactive)
  (dolist (session (copy-sequence imprimeur--sessions))
    (if (buffer-live-p (imprimeur--session-buffer session))
        (with-current-buffer (imprimeur--session-buffer session)
          (imprimeur-mode -1))
      (imprimeur--teardown session))))

(provide 'imprimeur)

;;; imprimeur.el ends here
