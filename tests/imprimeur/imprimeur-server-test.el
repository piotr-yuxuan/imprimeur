;;; imprimeur-server-test.el --- Tests of the server's boundary  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 002, acceptance 4, 5 and 8; the umbrella plan's
;; security section): requests, page messages, links and file names are
;; judged at the boundary.  A Host header other than the loopback address
;; or localhost with our port is refused, as are a POST from another
;; origin, oversized or malformed requests, transfer encodings, and any
;; file outside the document's root, not regular, or of another type.
;;
;; Plan 003, acceptance 2, and RFC 9110, section 14: a Range header asks
;; for one range, A-B, A- or the last N bytes -N, which the server cuts at
;; the end of the file and to 256 KiB; a reversed, multiple, malformed or
;; unsatisfiable range is refused, and a unit other than bytes is ignored;
;; the answers 206 and 416 carry their reason phrases.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-server)

(defun imprimeur-server-test-request (&rest lines)
  "Return an HTTP request head made of LINES, ended by an empty line."
  (concat (mapconcat #'identity lines "\r\n") "\r\n\r\n"))

(ert-deftest imprimeur-server-parses-requests ()
  (let ((request (imprimeur-server-parse-request
                  (imprimeur-server-test-request "GET /tok/a.org?v=1 HTTP/1.1" "Host: 127.0.0.1:8"))))
    (should (equal (plist-get request :method) "GET"))
    (should (equal (plist-get request :path) "/tok/a.org"))
    (should (equal (plist-get request :query) "v=1"))
    (should (equal (plist-get request :headers) '(("host" . "127.0.0.1:8"))))
    (should (equal (plist-get request :body) "")))
  (let ((post (concat (imprimeur-server-test-request "POST /tok/.imprimeur/post HTTP/1.1"
                                                     "Content-Length: 5")
                      "abc")))
    (should (equal (imprimeur-server-parse-request post) '(:incomplete)))
    (should (equal (plist-get (imprimeur-server-parse-request (concat post "de")) :body) "abcde"))))

(ert-deftest imprimeur-server-refuses-malformed-or-large-requests ()
  (dolist (case `(("GET / HTTP/1.1\r\nHost: a" . (:incomplete))
                  (,(concat "GET / HTTP/1.1\r\nX: " (make-string 20000 ?a)) . (:error 431))
                  (,(imprimeur-server-test-request "GET / HTTP/1.1" (concat "X: " (make-string 20000 ?a)))
                   . (:error 431))
                  (,(imprimeur-server-test-request "HELLO") . (:error 400))
                  (,(imprimeur-server-test-request "GET relative HTTP/1.1") . (:error 400))
                  (,(imprimeur-server-test-request "GET / HTTP/1.1" "Host 1") . (:error 400))
                  (,(imprimeur-server-test-request "GET / HTTP/1.1" "Host: a" "Host: b") . (:error 400))
                  (,(imprimeur-server-test-request "POST / HTTP/1.1" "Content-Length: x") . (:error 400))
                  (,(imprimeur-server-test-request "POST / HTTP/1.1" "Transfer-Encoding: chunked")
                   . (:error 501))
                  (,(imprimeur-server-test-request "POST / HTTP/1.1" "Content-Length: 70000")
                   . (:error 413))))
    (should (equal (cons (substring (car case) 0 (min 40 (length (car case))))
                         (imprimeur-server-parse-request (car case)))
                   (cons (substring (car case) 0 (min 40 (length (car case)))) (cdr case))))))

(ert-deftest imprimeur-server-checks-host-origin-and-method ()
  (let ((port 8080))
    (dolist (case '((("GET") . 400)
                    (("GET" ("host" . "evil.example:8080")) . 403)
                    (("GET" ("host" . "127.0.0.1.evil.example:8080")) . 403)
                    (("GET" ("host" . "127.0.0.1:9090")) . 403)
                    (("GET" ("host" . "127.0.0.1:8080")) . nil)
                    (("GET" ("host" . "localhost:8080")) . nil)
                    (("OPTIONS" ("host" . "localhost:8080")) . 405)
                    (("POST" ("host" . "127.0.0.1:8080") ("content-type" . "application/json")) . 403)
                    (("POST" ("host" . "127.0.0.1:8080") ("origin" . "http://evil.example")
                      ("content-type" . "application/json"))
                     . 403)
                    (("POST" ("host" . "127.0.0.1:8080") ("origin" . "http://127.0.0.1:8080")
                      ("content-type" . "text/plain"))
                     . 415)
                    (("POST" ("host" . "127.0.0.1:8080") ("origin" . "http://127.0.0.1:8080")
                      ("content-type" . "application/json"))
                     . nil)))
      (should (equal (cons case (imprimeur-server-check (list :method (caar case) :headers (cdar case))
                                                        port))
                     (cons case (cdr case)))))))

(ert-deftest imprimeur-server-parses-page-messages ()
  (dolist (case `(("{\"type\":\"ready\",\"rev\":3}" . (:type ready :rev 3))
                  ("{\"type\":\"ready\",\"rev\":-1}" . nil)
                  ("{\"type\":\"open\",\"url\":\"https://example.org/\"}"
                   . (:type open :url "https://example.org/"))
                  ("{\"type\":\"open\",\"url\":\"javascript:x\\nhttps://a\"}" . nil)
                  (,(format "{\"type\":\"open\",\"url\":\"https://e.org/%s\"}" (make-string 5000 ?a))
                   . nil)
                  ("{\"type\":\"other\"}" . nil)
                  ("[\"open\"]" . nil)
                  ("not json" . nil)))
    (should (equal (cons (car case) (imprimeur-server-parse-message (car case))) case))))

(ert-deftest imprimeur-server-parses-ranges ()
  (dolist (case `((nil . nil)
                  ("items=0-9" . nil)
                  ("bytes=10-19" . (10 . 19))
                  ("Bytes=10-19" . (10 . 19))
                  ("bytes=0-0" . (0 . 0))
                  ("bytes=0-" . (0 . 262143))
                  ("bytes=1000-" . (1000 . 263143))
                  ("bytes=1048575-" . (1048575 . 1048575))
                  ("bytes=1048000-2000000" . (1048000 . 1048575))
                  ("bytes=0-18446744073709551615" . (0 . 262143))
                  ("bytes=-500" . (1048076 . 1048575))
                  ("bytes=-2000000" . (0 . 262143))
                  ("bytes=5-1" . unsatisfiable)
                  ("bytes=0-1,5-6" . unsatisfiable)
                  ("bytes=0-1, 5-6" . unsatisfiable)
                  ("bytes=1048576-" . unsatisfiable)
                  ("bytes=2000000-" . unsatisfiable)
                  ("bytes=-0" . unsatisfiable)
                  ("bytes=-" . unsatisfiable)
                  ("bytes=" . unsatisfiable)
                  ("bytes=a-9" . unsatisfiable)
                  ;; Beyond `integer-width', arithmetic would signal.
                  (,(concat "bytes=" (make-string 20000 ?9) "-") . unsatisfiable)))
    (should (equal (cons (car case) (imprimeur-server-parse-range (car case) 1048576)) case)))
  (dolist (empty '("bytes=0-" "bytes=-5"))
    (should (equal (cons empty (imprimeur-server-parse-range empty 0)) (cons empty 'unsatisfiable)))))

(ert-deftest imprimeur-server-names-the-range-statuses ()
  (dolist (status '((206 . "Partial Content") (416 . "Range Not Satisfiable")))
    (should (string-prefix-p (format "HTTP/1.1 %d %s\r\n" (car status) (cdr status))
                             (imprimeur-server-head (car status))))))

(defun imprimeur-server-test-root ()
  "Make a scratch git repository with escape routes; return (ROOT . OUTSIDE).
ROOT holds a picture, a document, a text file, a directory named like
a picture, links to a file outside and to /dev/zero, and has a
sibling whose name extends its own."
  (let* ((parent (make-temp-file "server" t))
         (root (expand-file-name "root/" parent))
         (outside (expand-file-name "secret.png" parent)))
    (make-directory (expand-file-name "docs" root) t)
    (make-directory (expand-file-name "folder.png" root) t)
    (make-directory (expand-file-name "root-old" parent) t)
    (dolist (file '("pic.png" "café.png" "notes.txt" "run.sh" "docs/other.md"))
      (with-temp-file (expand-file-name file root) (insert "x")))
    (with-temp-file outside (insert "secret"))
    (with-temp-file (expand-file-name "root-old/x.png" parent) (insert "old"))
    (make-symbolic-link outside (expand-file-name "link.png" root))
    (make-symbolic-link "/dev/zero" (expand-file-name "zero.png" root))
    (repo-test-git root "init" "-q")
    (cons root outside)))

(ert-deftest imprimeur-server-serves-only-files-under-the-root ()
  (let* ((root (car (imprimeur-server-test-root)))
         (media (mapcar #'car imprimeur-server-media-types)))
    (should (equal (imprimeur-server-local-file root "pic.png" media)
                   (file-truename (expand-file-name "pic.png" root))))
    (should (imprimeur-server-local-file root "caf%C3%A9.png" media))
    (dolist (refused '("notes.txt" "%2e%2e/secret.png" "../secret.png" "link.png" "zero.png"
                       "folder.png" "../root-old/x.png" "" "pic.png%00"))
      (should (equal (cons refused (imprimeur-server-local-file root refused media))
                     (list refused))))))

(ert-deftest imprimeur-server-decides-where-links-lead ()
  (let* ((root (car (imprimeur-server-test-root)))
         (cases `(("https://example.org/x" . (:browse "https://example.org/x"))
                  ("mailto:someone@example.invalid" . (:browse "mailto:someone@example.invalid"))
                  ("http://127.0.0.1:8080/tok/docs/other.md"
                   . (:visit ,(file-truename (expand-file-name "docs/other.md" root))))
                  ("http://localhost:8080/tok/pic.png"
                   . (:visit ,(file-truename (expand-file-name "pic.png" root))))
                  ("http://127.0.0.1:8080/tok/link.png" . nil)
                  ("http://127.0.0.1:8080/tok/run.sh" . nil)
                  ("http://127.0.0.1:8080/tok/%2e%2e/secret.png" . nil)
                  ("http://127.0.0.1:8080/tok/%2e%2e/root-old/x.png" . nil)
                  ("http://127.0.0.1:8080/tok/zero.png" . nil)
                  ("http://127.0.0.1:8080/tok/folder.png" . nil)
                  ("http://127.0.0.1:8080/tok/notes.txt"
                   . (:visit ,(file-truename (expand-file-name "notes.txt" root))))
                  ("http://127.0.0.1:8080/wrong/docs/other.md" . nil)
                  ("javascript:alert(1)" . nil)
                  ("file:///etc/passwd" . nil)
                  ("data:text/html,x" . nil))))
    (dolist (case cases)
      (should (equal (cons (car case) (imprimeur-server-open-target (car case) 8080 "tok" root))
                     case)))))

;;; imprimeur-server-test.el ends here
