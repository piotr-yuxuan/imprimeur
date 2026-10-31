;;; imprimeur-render-test.el --- Tests of pandoc runs  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; Requirements (plan 002, acceptance 2 and 3, and the umbrella plan's
;; security section): a render calls back once with its outcome, reports
;; each failure by kind, never calls back after cancellation; untrusted
;; documents run sandboxed; the filter maps fence languages, task lists,
;; Org video links and remote images, and unwraps inline sourcepos spans.

;;; Code:

(require 'ert)
(require 'repo-test-helpers)
(require 'imprimeur-test-helpers)
(require 'imprimeur-render)

(defun imprimeur-render-test-run (spec &optional environment)
  "Render SPEC with ENVIRONMENT added, and return the outcome."
  (let ((process-environment (append environment process-environment))
        (outcome nil))
    (imprimeur-render-start (append spec (list :directory (make-temp-file "render" t)))
                            (lambda (result) (setq outcome result)))
    (imprimeur-test-wait-for (lambda () outcome))))

(defun imprimeur-render-test-fake (behaviour &optional text)
  "Render TEXT with the fake pandoc behaving as BEHAVIOUR; return the outcome."
  (imprimeur-render-test-run (list :program imprimeur-test-fake-pandoc :arguments nil
                                   :text (or text "text"))
                             (list (concat "IMPRIMEUR_FAKE_PANDOC=" behaviour))))

(ert-deftest imprimeur-render-arguments-sandbox-untrusted-documents ()
  (let ((untrusted (imprimeur-render-arguments "org" nil nil "bash"))
        (trusted (imprimeur-render-arguments "org" t t "bash")))
    (should (member "--sandbox" untrusted))
    (should-not (member "--sandbox" trusted))
    (should (equal (seq-take untrusted 2) '("-f" "org")))
    (should (member "imprimeur-remote-images=block" untrusted))
    (should (member "imprimeur-remote-images=allow" trusted))
    (should (member "imprimeur-languages=bash" untrusted))))

(ert-deftest imprimeur-render-reader-follows-the-alist ()
  (with-temp-buffer
    (org-mode)
    (should (equal (imprimeur-reader) "org")))
  (with-temp-buffer
    (text-mode)
    (should-not (imprimeur-reader))
    (setq buffer-file-name "/scratch/page.creole")
    (should (equal (imprimeur-reader) "creole"))
    (setq buffer-file-name nil))
  ;; gfm-mode derives from markdown-mode, which this test may lack: a
  ;; stand-in pair of modes checks that derived modes match.
  (should (equal (alist-get 'markdown-mode (default-value 'imprimeur-reader-alist))
                 "gfm+sourcepos"))
  (with-temp-buffer
    (define-derived-mode imprimeur-render-test-parent-mode text-mode "Parent")
    (define-derived-mode imprimeur-render-test-child-mode imprimeur-render-test-parent-mode "Child")
    (imprimeur-render-test-child-mode)
    (let ((imprimeur-reader-alist '((imprimeur-render-test-parent-mode . "gfm+sourcepos")
                                    (org-mode . "org"))))
      (should (equal (imprimeur-reader) "gfm+sourcepos")))))

(ert-deftest imprimeur-render-parse-output-keeps-only-valid-metadata ()
  (let ((marker "<!--imprimeur-meta-->\n"))
    (should (equal (imprimeur-render-parse-output
                    (concat marker "{\"title\":\"T\",\"lang\":\"fr-CA\"}\n<p>x</p>"))
                   '("<p>x</p>" :title "T" :lang "fr-CA")))
    ;; Whatever follows the first line of JSON is the document's, a marker
    ;; it wrote included, and pandoc's footnotes after it.
    (should (equal (imprimeur-render-parse-output
                    (concat marker "{\"title\":\"T\"}\n<p>a</p>\n" marker
                            "{\"title\":\"Forged\"}\n<section id=\"doc-footnotes\"></section>"))
                   (list (concat "<p>a</p>\n" marker "{\"title\":\"Forged\"}\n"
                                 "<section id=\"doc-footnotes\"></section>")
                         :title "T" :lang nil)))
    (should (equal (imprimeur-render-parse-output
                    (concat marker "{\"title\":[],\"lang\":\"\\\"><script>\"}\n<p>b</p>"))
                   '("<p>b</p>" :title nil :lang nil)))
    (should (equal (imprimeur-render-parse-output (concat marker "{\"title\":\"\",\"lang\":\"\"}"))
                   '("" :title "" :lang nil)))
    (should-not (imprimeur-render-parse-output "<p>no marker</p>"))
    (should-not (imprimeur-render-parse-output (concat "<p>x</p>\n" marker "{\"title\":\"T\"}")))
    (should-not (imprimeur-render-parse-output (concat marker "not json\n<p>x</p>")))
    (should (equal (length (plist-get (cdr (imprimeur-render-parse-output
                                            (format "%s{\"title\":\"%s\"}" marker
                                                    (make-string 600 ?a))))
                                      :title))
                   500))))

(ert-deftest imprimeur-render-reports-success-once ()
  (should (equal (imprimeur-render-test-fake "echo" "Hello")
                 '(:ok "<p>Hello</p>" (:title "" :lang nil) nil))))

(ert-deftest imprimeur-render-reports-each-failure-by-kind ()
  (let ((failure (imprimeur-render-test-fake "fail")))
    (should (equal (seq-take failure 2) '(:error exit)))
    (should (string-match-p "boom" (nth 2 failure))))
  (should (string-match-p "WARNING" (nth 3 (imprimeur-render-test-fake "warn"))))
  (should (equal (seq-take (imprimeur-render-test-fake "big") 2) '(:error too-large)))
  (let ((imprimeur-render-timeout 0.5))
    (should (equal (seq-take (imprimeur-render-test-fake "hang") 2) '(:error timeout))))
  (let (outcome)
    (should-not (imprimeur-render-start (list :program "/nonexistent/pandoc" :arguments nil
                                              :text "x" :directory temporary-file-directory)
                                        (lambda (result) (setq outcome result))))
    (should (equal (seq-take outcome 2) '(:error spawn)))))

(ert-deftest imprimeur-render-never-calls-back-after-cancellation ()
  (let* ((called nil)
         (process-environment (cons "IMPRIMEUR_FAKE_PANDOC=slow" process-environment))
         (process (imprimeur-render-start (list :program imprimeur-test-fake-pandoc :arguments nil
                                                :text "x" :directory temporary-file-directory)
                                          (lambda (_) (setq called t)))))
    (imprimeur-render-cancel process)
    (should-not (process-live-p process))
    (accept-process-output nil 1.5)
    (should-not called)))

(defun imprimeur-render-test-real (reader text &optional trusted remote)
  "Render TEXT with the real pandoc and READER; return the HTML.
TRUSTED and REMOTE are as for `imprimeur-render-arguments'."
  (let* ((pandoc (imprimeur-test-require "pandoc"))
         (outcome (imprimeur-render-test-run
                   (list :program pandoc :text text
                         :arguments (imprimeur-render-arguments
                                     reader trusted remote (imprimeur-render-languages pandoc))))))
    (should (eq (car outcome) :ok))
    (nth 1 outcome)))

(ert-deftest imprimeur-render-filter-shapes-markdown ()
  (let ((html (imprimeur-render-test-real
               "gfm+sourcepos"
               "# Title\n\n- [ ] open\n- [x] done\n\n```elisp\n(a)\n```\n\n```nonsense\nb\n```\n\nSome *text*.\n")))
    (should (string-match-p "data-pos=" html))
    (should-not (string-match-p "<span data-wrapper" html))
    (should (string-match-p "class=\"sourceCode commonlisp\"" html))
    (should (string-match-p "data-language=\"nonsense\"" html))
    (should (string-match-p "<span class=\"task\" data-checked=\"false\">" html))
    (should (string-match-p "data-checked=\"true\"" html))
    (should-not (string-match-p "<input" html))
    (let ((start 0) (ids nil))
      (while (string-match " id=\"\\([^\"]*\\)\"" html start)
        (push (match-string 1 html) ids)
        (setq start (match-end 0)))
      (should ids)
      (should-not (seq-remove (lambda (id) (string-prefix-p "doc-" id)) ids)))))

(ert-deftest imprimeur-render-filter-shapes-org ()
  (let ((html (imprimeur-render-test-real
               "org" "#+title: T\n\n[[file:clip.webm]] [[file:clip.webm][A clip]]\n")))
    (should (string-match-p "<video src=\"clip.webm\"" html))
    (should (string-match-p "<a href=\"clip.webm\">A clip</a>" html))))

(ert-deftest imprimeur-render-filter-keeps-footnotes ()
  (should (string-search "The Org note." (imprimeur-render-test-real
                                          "org" "Text[fn:1].\n\n* Heading\n\n[fn:1] The Org note.\n")))
  (should (string-search "The Markdown note." (imprimeur-render-test-real
                                               "gfm+sourcepos" "Text[^1].\n\n# H\n\n[^1]: The Markdown note.\n"))))

(ert-deftest imprimeur-render-filter-blocks-remote-images-unless-allowed ()
  (let ((text "![logo](https://example.org/logo.png)\n"))
    (let ((html (imprimeur-render-test-real "gfm" text)))
      (should (string-match-p "class=\"imprimeur-remote\">logo (example.org)</a>" html))
      (should-not (string-match-p "<img" html)))
    (should (string-match-p "<img src=\"https://example.org/logo.png\""
                            (imprimeur-render-test-real "gfm" text t t)))
    (should-not (string-match-p "<img" (imprimeur-render-test-real
                                        "gfm" (concat "---\nimprimeur-remote-images: allow\n---\n" text))))))

(ert-deftest imprimeur-render-sandbox-stops-includes ()
  (let* ((secret (make-temp-file "secret" nil ".txt" (format "marker-%d\n" (random 1000000))))
         (marker (string-trim (with-temp-buffer (insert-file-contents secret) (buffer-string))))
         (text (format "#+INCLUDE: \"%s\"\n" secret)))
    (should-not (string-search marker (imprimeur-render-test-real "org" text)))
    (should (string-search marker (imprimeur-render-test-real "org" text t)))))

;;; imprimeur-render-test.el ends here
