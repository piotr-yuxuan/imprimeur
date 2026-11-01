;;; imprimeur-server.el --- The loopback HTTP server of imprimeur  -*- lexical-binding: t; -*-

;; Copyright (C) 2026 piotr-yuxuan
;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software: you can redistribute it and/or modify it
;; under the terms of the European Union Public Licence, version 1.2 (see
;; the file LICENSE), or under the terms of the GNU General Public License
;; as published by the Free Software Foundation, either version 3 of the
;; License, or (at your option) any later version (see the file COPYING).

;;; Commentary:

;; Everything that reaches the server is untrusted: another local user may
;; connect, a web page may try DNS rebinding, a hostile document may try to
;; make the page navigate or post.  The functions below parse and judge
;; requests, page messages, links and file names at that boundary; nothing
;; else reads a request.

;;; Code:

(require 'seq)
(require 'subr-x)
;; The URL libraries load auth-source, which adds hooks of its own: they are
;; loaded when first needed, not with this file.
(declare-function url-unhex-string "url-util" (str &optional allow-newlines))
(declare-function url-generic-parse-url "url-parse" (url))
(declare-function url-path-and-query "url-parse" (urlobj))
(declare-function url-type "url-parse" (cl-x))
(declare-function url-host "url-parse" (cl-x))
(declare-function url-port "url-parse" (urlobj))

(defconst imprimeur-server-header-limit 16384
  "The largest request head, in bytes.")

(defconst imprimeur-server-body-limit 65536
  "The largest request body, in bytes.")

(defconst imprimeur-server-range-limit 262144
  "The largest part of a file sent for one Range request, in bytes.")

(defconst imprimeur-server-media-types
  '(("png" . "image/png") ("jpg" . "image/jpeg") ("jpeg" . "image/jpeg")
    ("gif" . "image/gif") ("webp" . "image/webp") ("avif" . "image/avif")
    ("svg" . "image/svg+xml") ("bmp" . "image/bmp") ("ico" . "image/x-icon")
    ("mp4" . "video/mp4") ("m4v" . "video/mp4") ("webm" . "video/webm")
    ("ogv" . "video/ogg") ("mov" . "video/quicktime") ("mp3" . "audio/mpeg")
    ("ogg" . "audio/ogg") ("oga" . "audio/ogg") ("opus" . "audio/ogg")
    ("wav" . "audio/wav") ("flac" . "audio/flac") ("m4a" . "audio/mp4"))
  "The file extensions served as media, with their media types.")

(defconst imprimeur-server-unserved-video-extensions
  '("3g2" "3gp" "asf" "asx" "avi" "divx" "drc" "dvb" "evo" "f4p" "f4v" "flv" "h264" "h265"
    "hevc" "m2ts" "m2v" "mkv" "mpeg" "mpg" "mts" "mxf" "ogm" "qt" "rm" "rmvb" "vob" "wmv")
  "The extensions of videos that are not served but that a link may open.
The page cannot play such a file, so it offers a link, which Emacs
follows for a media package to play it.")

(defconst imprimeur-server-document-extensions
  '("org" "md" "markdown" "rst" "txt" "textile" "creole" "pod" "ipynb" "csv" "tsv"
    "adoc")
  "The extensions of the documents that a link in the page may open.")

(defun imprimeur-server-parse-head (head)
  "Parse HEAD, a request line and its header lines, or return nil.
Return a plist of :method, :path, :query, :headers, an alist of
downcased names and values, and :length, the Content-Length or 0.
Return nil when a line is malformed, when the Content-Length is not a
number, or when the Host header appears more than once."
  (let* ((lines (split-string head "\r\n"))
         (headers (mapcar (lambda (line)
                            (and (string-match "\\`\\([!#$%&'*+.^_`|~0-9A-Za-z-]+\\):[ \t]*\\(.*?\\)[ \t]*\\'"
                                               line)
                                 (cons (downcase (match-string 1 line)) (match-string 2 line))))
                          (cdr lines)))
         (length-header (cdr (assoc "content-length" headers))))
    (and (not (memq nil headers))
         (<= (seq-count (lambda (header) (equal (car header) "host")) headers) 1)
         (or (not length-header) (string-match-p "\\`[0-9]\\{1,9\\}\\'" length-header))
         (string-match "\\`\\([A-Z]+\\) \\(/[^ ?#]*\\)\\(?:\\?\\([^ #]*\\)\\)? HTTP/1\\.[01]\\'"
                       (car lines))
         (list :method (match-string 1 (car lines)) :path (match-string 2 (car lines))
               :query (match-string 3 (car lines)) :headers headers
               :length (if length-header (string-to-number length-header) 0)))))

(defun imprimeur-server-parse-request (bytes)
  "Parse BYTES, the start of an HTTP request, as received so far.
Return (:incomplete) while the request is incomplete, (:error STATUS)
when it is malformed (400), too large (431, 413) or uses a transfer
encoding (501), and otherwise the plist of `imprimeur-server-parse-head'
with :body."
  (let* ((end (string-search "\r\n\r\n" bytes))
         (head (and end (imprimeur-server-parse-head (substring bytes 0 end))))
         (body-start (and end (+ end 4))))
    (cond ((> (or end (length bytes)) imprimeur-server-header-limit) '(:error 431))
          ((not end) '(:incomplete))
          ((not head) '(:error 400))
          ((assoc "transfer-encoding" (plist-get head :headers)) '(:error 501))
          ((> (plist-get head :length) imprimeur-server-body-limit) '(:error 413))
          ((< (length bytes) (+ body-start (plist-get head :length))) '(:incomplete))
          (t (append head (list :body (substring bytes body-start
                                                  (+ body-start (plist-get head :length)))))))))

(defun imprimeur-server-check (request port)
  "Return nil when REQUEST may be served on PORT, else an HTTP status.
The Host header must name the loopback address or localhost with
PORT, which stops DNS rebinding; a POST must also come from the same
origin and carry JSON."
  (let* ((headers (plist-get request :headers))
         (host (cdr (assoc "host" headers)))
         (ours (list (format "127.0.0.1:%d" port) (format "localhost:%d" port)))
         (method (plist-get request :method)))
    (cond ((not host) 400)
          ((not (member host ours)) 403)
          ((member method '("GET" "HEAD")) nil)
          ((not (equal method "POST")) 405)
          ((not (member (cdr (assoc "origin" headers)) (mapcar (lambda (o) (concat "http://" o)) ours)))
           403)
          ((not (string-prefix-p "application/json" (or (cdr (assoc "content-type" headers)) "")))
           415))))

(defun imprimeur-server-parse-message (body)
  "Parse BODY, a message posted by the page, into a plist, or return nil.
The messages are {\"type\": \"ready\", \"rev\": N}, which reports the
revision shown, and {\"type\": \"open\", \"url\": URL}, which asks to
follow a link; a URL holds at most 4096 characters and no control
character."
  (let* ((message (ignore-errors
                    (json-parse-string (decode-coding-string body 'utf-8) :object-type 'plist
                                       :null-object nil :false-object nil)))
         (type (and (plistp message) (plist-get message :type)))
         (rev (and (plistp message) (plist-get message :rev)))
         (url (and (plistp message) (plist-get message :url))))
    (cond ((and (equal type "ready") (natnump rev)) (list :type 'ready :rev rev))
          ((and (equal type "open") (stringp url) (<= (length url) 4096)
                (not (string-match-p "[[:cntrl:]]" url)))
           (list :type 'open :url url)))))

(defun imprimeur-server-local-file (root relative extensions)
  "Return the true name of RELATIVE, a file name under ROOT, or nil.
RELATIVE is percent-decoded, then decoded as UTF-8.  The file must be
a regular file whose true name lies under ROOT's and whose extension
is one of EXTENSIONS: no traversal, no symbolic link pointing out, no
device."
  (require 'url-util)
  (let* ((name (decode-coding-string (url-unhex-string relative) 'utf-8))
         (file (and root (not (string-empty-p name)) (not (string-search "\0" name))
                    (file-truename (expand-file-name name root)))))
    (and file
         (file-in-directory-p file (file-truename root))
         (file-regular-p file)
         (member (downcase (or (file-name-extension file) "")) extensions)
         file)))

(defun imprimeur-server-parse-range (header size)
  "Parse HEADER, a Range header's value or nil, for a file of SIZE bytes.
Return nil when there is no HEADER or its unit is not bytes, which a
server ignores, or for a suffix -N, N above 0, of an empty file, which
RFC 9110 deems satisfiable although no 206 can hold it: the whole
file is wanted.  Return (START . END), the inclusive offsets of the
one range A-B, A- or -N, the last N bytes, cut at the end of the file
and to `imprimeur-server-range-limit' bytes.  Return `unsatisfiable'
for anything else in bytes: a range malformed, reversed, multiple,
with an offset of more than 20 digits, or starting at SIZE or after
it, as -0 does."
  ;; Range units are case-insensitive.
  (let ((case-fold-search t))
    (cond ((not (and header (string-match-p "\\`bytes=" header))) nil)
          ((not (string-match "\\`bytes=\\([0-9]\\{0,20\\}\\)-\\([0-9]\\{0,20\\}\\)\\'" header))
           'unsatisfiable)
          (t
           (let* ((first (match-string 1 header))
                  (last (match-string 2 header))
                  ;; A lone - reads as -0.
                  (start (if (string-empty-p first)
                             (- size (min size (string-to-number last)))
                           (string-to-number first)))
                  (end (min (1- size) (+ start imprimeur-server-range-limit -1)
                            (if (or (string-empty-p first) (string-empty-p last))
                                size
                              (string-to-number last)))))
             ;; END is below SIZE, so a START at SIZE or after fails too,
             ;; and a suffix above 0 fails only on an empty file.
             (cond ((<= start end) (cons start end))
                   ((and (string-empty-p first) (< 0 (string-to-number last))) nil)
                   (t 'unsatisfiable)))))))

(defun imprimeur-server-open-target (url port token root)
  "Decide where the link URL, followed in the page, may lead.
PORT and TOKEN identify the page; ROOT is the document's root.
Return (:visit FILE) for a document, a media file or a video of
`imprimeur-server-unserved-video-extensions' of the page's own origin,
\(:browse URL) for an http, https or mailto address elsewhere, and nil
for anything else."
  (require 'url-parse)
  (let* ((parsed (url-generic-parse-url url))
         (scheme (url-type parsed))
         (prefix (concat "/" token "/"))
         (ours (and (equal scheme "http") (member (url-host parsed) '("127.0.0.1" "localhost"))
                    (eql (url-port parsed) port))))
    (cond (ours
           (let ((path (car (url-path-and-query parsed))))
             (when-let* (((string-prefix-p prefix path))
                         (file (imprimeur-server-local-file
                                root (substring path (length prefix))
                                (append imprimeur-server-document-extensions
                                        imprimeur-server-unserved-video-extensions
                                        (mapcar #'car imprimeur-server-media-types)))))
               (list :visit file))))
          ((member scheme '("http" "https" "mailto")) (list :browse url)))))

;;;; The server

(defconst imprimeur-server-csp
  (concat "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
          "img-src 'self' data: blob:; media-src 'self'; font-src 'self'; "
          "connect-src 'self'; object-src 'none'; frame-src 'none'; base-uri 'none'; "
          "form-action 'none'; frame-ancestors 'none'")
  "The Content Security Policy of every response.")

(defconst imprimeur-server-csp-remote
  (replace-regexp-in-string
   "media-src 'self'" "media-src 'self' https:"
   (replace-regexp-in-string "img-src 'self' data: blob:" "img-src 'self' data: blob: https:"
                             imprimeur-server-csp t t)
   t t)
  "The policy of a trusted document's page that may show remote images.")

(defconst imprimeur-server-connection-limit 32
  "The most connections open at once; more are closed on arrival.")

(defvar imprimeur-server-request-deadline 10
  "Seconds a connection has to complete its request.
An event stream, once open, has no deadline.")

(defconst imprimeur-server--reasons
  '((200 . "OK") (204 . "No Content") (206 . "Partial Content") (400 . "Bad Request")
    (403 . "Forbidden") (404 . "Not Found") (405 . "Method Not Allowed")
    (413 . "Content Too Large") (415 . "Unsupported Media Type")
    (416 . "Range Not Satisfiable") (431 . "Request Header Fields Too Large")
    (500 . "Internal Server Error") (501 . "Not Implemented"))
  "The reason phrases of the statuses the server sends.")

(defvar imprimeur-server--process nil
  "The listening process, or nil.")

(defvar imprimeur-server--connections nil
  "The open connections.")

(defvar imprimeur-server--handlers nil
  "Alist from a session's token to the function that serves it.
The function receives the connection, the request plist and the path
after the token, and must respond.")

(defun imprimeur-log (format-string &rest arguments)
  "Log FORMAT-STRING with ARGUMENTS to the buffer \" *imprimeur-log*\".
The buffer keeps the last 1000 lines."
  (with-current-buffer (get-buffer-create " *imprimeur-log*")
    (goto-char (point-max))
    (insert (format-time-string "%F %T ") (apply #'format format-string arguments) "\n")
    (when (> (count-lines (point-min) (point-max)) 1000)
      (goto-char (point-min))
      (delete-region (point) (line-beginning-position 2)))))

(defun imprimeur-server-head (status &optional type length headers)
  "Return the head of a response of STATUS, as an encoded string.
TYPE is the media type, LENGTH the body's length in bytes, nil for an
event stream; HEADERS, an alist, overrides the security headers, which
every response carries."
  (let ((all (append headers
                     `(("Content-Security-Policy" . ,imprimeur-server-csp)
                       ("X-Content-Type-Options" . "nosniff")
                       ("Referrer-Policy" . "no-referrer")
                       ("Cross-Origin-Resource-Policy" . "same-origin")
                       ("Cache-Control" . "no-store")))))
    (encode-coding-string
     (concat (format "HTTP/1.1 %d %s\r\n" status (alist-get status imprimeur-server--reasons))
             (and type (format "Content-Type: %s\r\n" type))
             (mapconcat (lambda (name) (format "%s: %s\r\n" name (cdr (assoc name all))))
                        (seq-uniq (mapcar #'car all)) "")
             (if length (format "Content-Length: %d\r\nConnection: close\r\n" length) "")
             "\r\n")
     'utf-8)))

(defun imprimeur-server-respond (connection status &optional type body headers)
  "Send STATUS on CONNECTION with BODY of media TYPE, then close it.
BODY is a string, encoded as UTF-8 unless already unibyte; HEADERS is
as for `imprimeur-server-head'.  A HEAD request gets no body."
  (let ((bytes (if (multibyte-string-p (or body "")) (encode-coding-string body 'utf-8) (or body ""))))
    (when (process-live-p connection)
      (process-send-string connection (imprimeur-server-head status type (length bytes) headers))
      (unless (equal (process-get connection :method) "HEAD")
        (process-send-string connection bytes))
      (delete-process connection))))

(defun imprimeur-server-stream (connection &optional on-close)
  "Turn CONNECTION into an open event stream, without deadline.
ON-CLOSE, a function of the connection, runs when it closes."
  (cancel-timer (process-get connection :deadline))
  (process-put connection :on-close on-close)
  (process-send-string connection (imprimeur-server-head 200 "text/event-stream")))

(defun imprimeur-server-send-event (connection event data)
  "Send EVENT with DATA, serialised as JSON, on the stream CONNECTION.
A write that fails, as to a page closed before Emacs noticed, deletes
CONNECTION, which runs its closing function, and signals nothing."
  (when (process-live-p connection)
    (let ((bytes (encode-coding-string
                  (format "event: %s\ndata: %s\n\n" event (json-serialize data))
                  'utf-8)))
      (condition-case failure
          (process-send-string connection bytes)
        (error (imprimeur-log "Lost a page: %s" (error-message-string failure))
               (delete-process connection))))))

(defun imprimeur-server--dispatch (connection request)
  "Serve REQUEST, complete and checked, on CONNECTION."
  (let* ((path (plist-get request :path))
         (slash (string-search "/" path 1))
         (handler (and slash (cdr (assoc (substring path 1 slash) imprimeur-server--handlers)))))
    (process-put connection :method (plist-get request :method))
    (if (not handler)
        (imprimeur-server-respond connection 404)
      (condition-case failure
          (funcall handler connection request (substring path (1+ slash)))
        (error
         (imprimeur-log "Serving %s failed: %S" path failure)
         (imprimeur-server-respond connection 500))))))

(defun imprimeur-server--filter (connection bytes)
  "Collect BYTES from CONNECTION, and serve the request once complete."
  (unless (process-get connection :served)
    (let* ((data (concat (process-get connection :data) bytes))
           (request (imprimeur-server-parse-request data))
           (status (if (eq (car request) :error)
                       (cadr request)
                     (imprimeur-server-check request (process-contact imprimeur-server--process :service)))))
      (process-put connection :data data)
      (unless (eq (car request) :incomplete)
        (process-put connection :served t)
        (cancel-timer (process-get connection :deadline))
        (if status
            (imprimeur-server-respond connection status)
          (imprimeur-server--dispatch connection request))))))

(defun imprimeur-server--sentinel (connection _event)
  "Forget CONNECTION once closed, and run its closing function."
  (unless (process-live-p connection)
    (setq imprimeur-server--connections (delq connection imprimeur-server--connections))
    (when-let* ((timer (process-get connection :deadline))) (cancel-timer timer))
    (when-let* ((on-close (process-get connection :on-close)))
      (process-put connection :on-close nil)
      (funcall on-close connection))))

(defun imprimeur-server--accept (_server connection _message)
  "Admit CONNECTION, or close it at once when too many are open."
  (if (>= (length imprimeur-server--connections) imprimeur-server-connection-limit)
      (delete-process connection)
    (push connection imprimeur-server--connections)
    (set-process-query-on-exit-flag connection nil)
    (process-put connection :deadline
                 (run-at-time imprimeur-server-request-deadline nil #'delete-process connection))))

(defun imprimeur-server-start ()
  "Start the server on a free loopback port, unless it runs; return the port."
  (unless (process-live-p imprimeur-server--process)
    (setq imprimeur-server--process
          (make-network-process :name "imprimeur-server" :server 64 :host "127.0.0.1"
                                :family 'ipv4 :service t :coding 'binary :noquery t
                                :filter #'imprimeur-server--filter
                                :sentinel #'imprimeur-server--sentinel
                                :log #'imprimeur-server--accept)))
  (process-contact imprimeur-server--process :service))

(defun imprimeur-server-stop ()
  "Stop the server and close every connection."
  (mapc #'delete-process imprimeur-server--connections)
  (setq imprimeur-server--connections nil)
  (when imprimeur-server--process
    (delete-process imprimeur-server--process)
    (setq imprimeur-server--process nil)))

(defun imprimeur-server-register (token handler)
  "Serve the paths under /TOKEN/ with HANDLER; see `imprimeur-server--handlers'."
  (setf (alist-get token imprimeur-server--handlers nil nil #'equal) handler))

(defun imprimeur-server-unregister (token)
  "Stop serving the paths under /TOKEN/."
  (setf (alist-get token imprimeur-server--handlers nil t #'equal) nil))

(provide 'imprimeur-server)

;;; imprimeur-server.el ends here
