;;; imprimeur-serve-test.el --- Tests of the running server  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 002, acceptance 4; the umbrella plan's security
;; section): every response, an error included, carries the security
;; headers verbatim; unknown tokens get 404, foreign hosts 403, POSTs
;; without our origin 403, oversized or chunked requests 413, 431 or 501;
;; at most 32 connections are open; a request still incomplete after the
;; deadline is closed, an open event stream is not.

;;; Code:

(require 'ert)
(require 'imprimeur-test-helpers)
(require 'imprimeur-test-http)
(require 'imprimeur-server)

(defconst imprimeur-serve-test-headers
  `(("content-security-policy"
     . ,(concat "default-src 'none'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
                "img-src 'self' data: blob:; media-src 'self'; font-src 'self'; "
                "connect-src 'self'; object-src 'none'; frame-src 'none'; base-uri 'none'; "
                "form-action 'none'; frame-ancestors 'none'"))
    ("x-content-type-options" . "nosniff")
    ("referrer-policy" . "no-referrer")
    ("cross-origin-resource-policy" . "same-origin"))
  "The security headers every response must carry, as the plan writes them.")

(defmacro imprimeur-serve-test-with-server (port handler &rest body)
  "Run BODY with the server started, PORT bound to its port.
HANDLER serves the token \"tok\"."
  (declare (indent 2))
  `(let ((,port (imprimeur-server-start)))
     (unwind-protect
         (progn (imprimeur-server-register "tok" ,handler) ,@body)
       (imprimeur-server-unregister "tok")
       (imprimeur-server-stop))))

(defun imprimeur-serve-test-hello (connection _request _rest)
  "Answer hello on CONNECTION."
  (imprimeur-server-respond connection 200 "text/plain" "hello"))

(ert-deftest imprimeur-serve-answers-with-the-security-headers ()
  (imprimeur-serve-test-with-server port #'imprimeur-serve-test-hello
    (let ((response (imprimeur-test-http-get port "/tok/x")))
      (should (equal (car response) 200))
      (should (equal (nth 2 response) "hello"))
      (dolist (header imprimeur-serve-test-headers)
        (should (equal (assoc (car header) (nth 1 response)) header))))
    (dolist (case `((("/wrong/x") . 404)
                    (("/tok/x" "Host: evil.example") . 403)))
      (let ((response (if (cdar case)
                          (imprimeur-test-http port (format "GET %s HTTP/1.1\r\n%s\r\n\r\n"
                                                            (caar case) (cadar case)))
                        (imprimeur-test-http-get port (caar case)))))
        (should (equal (cons case (car response)) (cons case (cdr case))))
        (dolist (header imprimeur-serve-test-headers)
          (should (equal (assoc (car header) (nth 1 response)) header)))))))

(ert-deftest imprimeur-serve-refuses-bad-requests ()
  (imprimeur-serve-test-with-server port #'imprimeur-serve-test-hello
    (let ((host (format "Host: 127.0.0.1:%d" port)))
      (dolist (case `(("GET /tok/x HTTP/1.1\r\n\r\n" . 400)
                      (,(format "POST /tok/x HTTP/1.1\r\n%s\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}" host) . 403)
                      (,(format "POST /tok/x HTTP/1.1\r\n%s\r\nContent-Length: 70000\r\n\r\n" host) . 413)
                      (,(format "GET /tok/x HTTP/1.1\r\n%s\r\nX: %s\r\n\r\n" host (make-string 20000 ?a)) . 431)
                      (,(format "POST /tok/x HTTP/1.1\r\n%s\r\nTransfer-Encoding: chunked\r\n\r\n" host) . 501)))
        (let ((label (truncate-string-to-width (car case) 40)))
          (should (equal (cons label (car (imprimeur-test-http port (car case))))
                         (cons label (cdr case)))))))))

(ert-deftest imprimeur-serve-reports-a-failing-handler ()
  (imprimeur-serve-test-with-server port (lambda (_connection _request _rest) (error "Broken"))
    (should (equal (car (imprimeur-test-http-get port "/tok/x")) 500))
    (should (string-match-p "Broken" (with-current-buffer " *imprimeur-log*" (buffer-string))))))

(ert-deftest imprimeur-serve-keeps-at-most-32-connections ()
  (imprimeur-serve-test-with-server port #'imprimeur-serve-test-hello
    (let ((clients (mapcar (lambda (_) (imprimeur-test-http-open port)) (number-sequence 1 33))))
      (unwind-protect
          (progn
            (imprimeur-test-wait-for (lambda () (= (seq-count #'process-live-p clients) 32)))
            (accept-process-output nil 0.2)
            (should (= (seq-count #'process-live-p clients) 32)))
        (mapc #'delete-process clients)))))

(ert-deftest imprimeur-serve-closes-incomplete-requests-but-not-streams ()
  (let ((imprimeur-server-request-deadline 0.5))
    (imprimeur-serve-test-with-server port
        (lambda (connection _request _rest)
          (imprimeur-server-stream connection)
          (imprimeur-server-send-event connection "hello" '(:n 1)))
      (let ((idle (imprimeur-test-http-open port))
            (stream (imprimeur-test-http-open port)))
        (unwind-protect
            (progn
              (process-send-string idle "GET /tok/x HTTP/1.1\r\n")
              (process-send-string stream (format "GET /tok/x HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n" port))
              (imprimeur-test-wait-for (lambda () (not (process-live-p idle))) 5)
              (accept-process-output nil 1)
              (should (process-live-p stream))
              (should (string-match-p "\r\n\r\nevent: hello\ndata: {\"n\":1}\n\n\\'"
                                      (with-current-buffer (process-buffer stream) (buffer-string)))))
          (delete-process idle)
          (delete-process stream))))))

(ert-deftest imprimeur-serve-stops-listening ()
  (let ((port (imprimeur-server-start)))
    (imprimeur-server-stop)
    (should-error (imprimeur-test-http-open port) :type 'file-error)))

;;; imprimeur-serve-test.el ends here
