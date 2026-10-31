;;; imprimeur-test-http.el --- A raw HTTP client for the tests  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; The tests speak to imprimeur's server byte by byte, so that they can
;; send what no browser would: a foreign Host, a missing Origin, oversized
;; heads, chunked bodies, connections that never finish.

;;; Code:

(require 'imprimeur-test-helpers)

(defun imprimeur-test-http-open (port)
  "Open a connection to PORT on the loopback address; return the process.
What the server sends accumulates in the process buffer."
  (make-network-process :name "imprimeur-test-http" :host "127.0.0.1" :service port
                        :buffer (generate-new-buffer " *imprimeur-test-http*")
                        :coding 'binary :noquery t :sentinel #'ignore))

(defun imprimeur-test-http (port request)
  "Send REQUEST, a string, to PORT; return the response once the server closes.
The response is (STATUS HEADERS BODY): HEADERS is an alist of
downcased names and values."
  (let ((process (imprimeur-test-http-open port)))
    (process-send-string process request)
    (imprimeur-test-wait-for (lambda () (not (process-live-p process))))
    (let ((response (with-current-buffer (process-buffer process) (buffer-string))))
      (kill-buffer (process-buffer process))
      (imprimeur-test-http-parse response))))

(defun imprimeur-test-http-parse (response)
  "Split RESPONSE into (STATUS HEADERS BODY), or (nil nil RESPONSE)."
  (if (not (string-match "\\`HTTP/1\\.1 \\([0-9]\\{3\\}\\) [^\r]*\r\n\\(\\(?:.*\r\n\\)*?\\)\r\n"
                         response))
      (list nil nil response)
    (let ((status (string-to-number (match-string 1 response)))
          (head (match-string 2 response))
          (body (substring response (match-end 0))))
      (list status
            (mapcar (lambda (line)
                      (let ((colon (string-search ": " line)))
                        (cons (downcase (substring line 0 colon)) (substring line (+ colon 2)))))
                    (split-string head "\r\n" t))
            body))))

(defun imprimeur-test-http-get (port path &rest headers)
  "GET PATH on PORT with Host 127.0.0.1:PORT and HEADERS, strings \"Name: value\".
Return the response as `imprimeur-test-http' does."
  (imprimeur-test-http port (concat (format "GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n" path port)
                                    (mapconcat (lambda (header) (concat header "\r\n")) headers "")
                                    "\r\n")))

(defun imprimeur-test-http-post (port path body)
  "POST BODY, a JSON string, to PATH on PORT from the page's own origin.
Return the response as `imprimeur-test-http' does."
  (imprimeur-test-http
   port (format (concat "POST %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nOrigin: http://127.0.0.1:%d\r\n"
                        "Content-Type: application/json\r\nContent-Length: %d\r\n\r\n%s")
                path port port (string-bytes body) body)))

(defun imprimeur-test-http-stream (port path)
  "Open the event stream at PATH on PORT; return the connection."
  (let ((process (imprimeur-test-http-open port)))
    (process-send-string process (format "GET %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n"
                                         path port))
    process))

(defun imprimeur-test-http-events (process)
  "Return the events received on the stream PROCESS, as (NAME . DATA) pairs."
  (let ((text (with-current-buffer (process-buffer process) (buffer-string)))
        (start 0)
        (events nil))
    (while (string-match "event: \\([^\n]*\\)\ndata: \\([^\n]*\\)\n\n" text start)
      (push (cons (match-string 1 text) (match-string 2 text)) events)
      (setq start (match-end 0)))
    (nreverse events)))

(provide 'imprimeur-test-http)

;;; imprimeur-test-http.el ends here
