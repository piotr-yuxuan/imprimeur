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
(require 'url-parse)
(require 'url-util)

(defconst imprimeur-server-header-limit 16384
  "The largest request head, in bytes.")

(defconst imprimeur-server-body-limit 65536
  "The largest request body, in bytes.")

(defconst imprimeur-server-media-types
  '(("png" . "image/png") ("jpg" . "image/jpeg") ("jpeg" . "image/jpeg")
    ("gif" . "image/gif") ("webp" . "image/webp") ("avif" . "image/avif")
    ("svg" . "image/svg+xml") ("bmp" . "image/bmp") ("ico" . "image/x-icon")
    ("mp4" . "video/mp4") ("m4v" . "video/mp4") ("webm" . "video/webm")
    ("ogv" . "video/ogg") ("mov" . "video/quicktime") ("mp3" . "audio/mpeg")
    ("ogg" . "audio/ogg") ("oga" . "audio/ogg") ("opus" . "audio/ogg")
    ("wav" . "audio/wav") ("flac" . "audio/flac") ("m4a" . "audio/mp4"))
  "The file extensions served as media, with their media types.")

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
  (let* ((name (decode-coding-string (url-unhex-string relative) 'utf-8))
         (file (and root (not (string-empty-p name)) (not (string-search "\0" name))
                    (file-truename (expand-file-name name root)))))
    (and file
         (file-in-directory-p file (file-truename root))
         (file-regular-p file)
         (member (downcase (or (file-name-extension file) "")) extensions)
         file)))

(defun imprimeur-server-open-target (url port token root)
  "Decide where the link URL, followed in the page, may lead.
PORT and TOKEN identify the page; ROOT is the document's root.
Return (:visit FILE) for a document or a media file of the page's
own origin, (:browse URL) for an http, https or mailto address
elsewhere, and nil for anything else."
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
                                        (mapcar #'car imprimeur-server-media-types)))))
               (list :visit file))))
          ((member scheme '("http" "https" "mailto")) (list :browse url)))))

(provide 'imprimeur-server)

;;; imprimeur-server.el ends here
