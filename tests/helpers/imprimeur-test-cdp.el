;;; imprimeur-test-cdp.el --- Drive headless Chromium from the tests  -*- lexical-binding: t; -*-

;; SPDX-License-Identifier: EUPL-1.2 OR GPL-3.0-or-later

;;; Commentary:

;; The page tests drive a headless Chromium over the Chrome DevTools
;; Protocol, through the pipe that --remote-debugging-pipe reads on file
;; descriptor 3 and writes on 4: JSON texts, each ended by a NUL byte.  No
;; port is opened and no Node is needed.  Each browser has its own profile
;; in the scratch directory and resolves no host but the loopback address,
;; so that a request escaping the page's policy fails instead of leaving
;; the machine.  The input events it sends are trusted, as a user's are.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'imprimeur-test-helpers)

(cl-defstruct (imprimeur-test-cdp (:constructor imprimeur-test-cdp--create) (:copier nil))
  "A browser driven by a test, and the page it shows."
  process stderr profile session (next 0) (replies (make-hash-table)) events)

(defun imprimeur-test-cdp--filter (process bytes)
  "Collect the messages in BYTES, sent by the browser of PROCESS."
  (let ((browser (process-get process :browser))
        (data (concat (process-get process :data) bytes))
        (start 0))
    (while-let ((end (string-search "\0" data start)))
      (let ((message (json-parse-string (decode-coding-string (substring data start end) 'utf-8)
                                        :object-type 'plist :null-object nil :false-object nil)))
        (if (plist-get message :id)
            (puthash (plist-get message :id) message (imprimeur-test-cdp-replies browser))
          (push message (imprimeur-test-cdp-events browser))))
      (setq start (1+ end)))
    (process-put process :data (substring data start))))

(defun imprimeur-test-cdp--send (browser method params)
  "Send METHOD with PARAMS, a plist, to BROWSER; return the message's id.
The methods of the Browser and Target domains go to the browser, the
others to its page."
  (let ((id (cl-incf (imprimeur-test-cdp-next browser)))
        (session (and (imprimeur-test-cdp-session browser)
                      (not (string-match-p "\\`\\(?:Browser\\|Target\\)\\." method))
                      (imprimeur-test-cdp-session browser))))
    (process-send-string (imprimeur-test-cdp-process browser)
                         (concat (encode-coding-string
                                  (json-serialize `(:id ,id :method ,method :params ,params
                                                        ,@(and session (list :sessionId session))))
                                  'utf-8)
                                 "\0"))
    id))

(defun imprimeur-test-cdp-call (browser method &optional params)
  "Call METHOD with PARAMS, a plist, in BROWSER; return the result.
Fail the test when the browser answers with an error."
  (let* ((id (imprimeur-test-cdp--send browser method params))
         (reply (imprimeur-test-wait-for (lambda () (gethash id (imprimeur-test-cdp-replies browser))))))
    (when (plist-get reply :error)
      (ert-fail (list method (plist-get reply :error))))
    (plist-get reply :result)))

(defun imprimeur-test-cdp-close (browser)
  "Close BROWSER, terminating it after 5 seconds, and delete its profile."
  (let ((process (imprimeur-test-cdp-process browser))
        (deadline (+ (float-time) 5)))
    (when (process-live-p process)
      (imprimeur-test-cdp--send browser "Browser.close" nil)
      (while (and (process-live-p process) (< (float-time) deadline))
        (accept-process-output process 0.05))
      (when (process-live-p process)
        (signal-process process 'TERM)
        (accept-process-output process 1)))
    (when (imprimeur-test-cdp-stderr browser)
      (delete-process (imprimeur-test-cdp-stderr browser)))
    (delete-directory (imprimeur-test-cdp-profile browser) t)))

(defun imprimeur-test-cdp-start ()
  "Start a headless Chromium showing a blank page; return the browser.
The page records the violations of its security policy in
window.__violations, from its first script on."
  (let* ((program (imprimeur-test-require "chromium"))
         (browser (imprimeur-test-cdp--create :profile (make-temp-file "imprimeur-cdp-" t)))
         (started nil))
    (setf (imprimeur-test-cdp-stderr browser)
          (make-pipe-process :name "imprimeur-test-cdp-stderr" :noquery t
                             :buffer (get-buffer-create " *imprimeur-test-cdp*")))
    (unwind-protect
        (let ((process (make-process
                        :name "imprimeur-test-cdp" :connection-type 'pipe :coding 'binary
                        :noquery t :sentinel #'ignore :filter #'imprimeur-test-cdp--filter
                        :stderr (imprimeur-test-cdp-stderr browser)
                        :command (list "sh" "-c" "exec \"$0\" \"$@\" 3<&0 4>&1 0</dev/null 1>&2"
                                       program "--headless" "--remote-debugging-pipe"
                                       (concat "--user-data-dir=" (imprimeur-test-cdp-profile browser))
                                       "--no-first-run" "--no-default-browser-check"
                                       "--disable-background-networking" "--disable-component-update"
                                       "--disable-extensions" "--disable-sync"
                                       "--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1"))))
          (process-put process :browser browser)
          (setf (imprimeur-test-cdp-process browser) process)
          (let ((target (imprimeur-test-cdp-call browser "Target.createTarget" '(:url "about:blank"))))
            (setf (imprimeur-test-cdp-session browser)
                  (plist-get (imprimeur-test-cdp-call browser "Target.attachToTarget"
                                                      `(:targetId ,(plist-get target :targetId)
                                                                  :flatten t))
                             :sessionId)))
          (dolist (domain '("Page" "Runtime" "Network" "Log"))
            (imprimeur-test-cdp-call browser (concat domain ".enable")))
          (imprimeur-test-cdp-call
           browser "Page.addScriptToEvaluateOnNewDocument"
           '(:source "window.__violations = [];
document.addEventListener('securitypolicyviolation',
  (event) => window.__violations.push(event.violatedDirective + ' ' + event.blockedURI));"))
          (setq started t)
          browser)
      (unless started (imprimeur-test-cdp-close browser)))))

(defmacro imprimeur-test-cdp-with-browser (browser &rest body)
  "Run BODY with BROWSER bound to a started browser, closed afterwards."
  (declare (indent 1))
  `(let ((,browser (imprimeur-test-cdp-start)))
     (unwind-protect (progn ,@body)
       (imprimeur-test-cdp-close ,browser))))

(defun imprimeur-test-cdp-events-named (browser method)
  "Return the parameters of BROWSER's events named METHOD, oldest first."
  (nreverse (delq nil (mapcar (lambda (event)
                                (and (equal (plist-get event :method) method) (plist-get event :params)))
                              (imprimeur-test-cdp-events browser)))))

(defun imprimeur-test-cdp-eval (browser expression)
  "Return the value of the JavaScript EXPRESSION in BROWSER's page.
A promise is awaited; an exception fails the test."
  (let ((result (imprimeur-test-cdp-call browser "Runtime.evaluate"
                                         `(:expression ,expression :awaitPromise t :returnByValue t))))
    (when (plist-get result :exceptionDetails)
      (ert-fail (list expression (plist-get result :exceptionDetails))))
    (plist-get (plist-get result :result) :value)))

(defun imprimeur-test-cdp-wait (browser expression &optional timeout)
  "Wait until EXPRESSION is true in BROWSER's page; return its value.
TIMEOUT is as for `imprimeur-test-wait-for'."
  (imprimeur-test-wait-for (lambda () (imprimeur-test-cdp-eval browser expression)) timeout))

(defun imprimeur-test-cdp-navigate (browser url)
  "Load URL in BROWSER's page and wait for its load event."
  (let ((loads (length (imprimeur-test-cdp-events-named browser "Page.loadEventFired"))))
    (imprimeur-test-cdp-call browser "Page.navigate" `(:url ,url))
    (imprimeur-test-wait-for
     (lambda () (> (length (imprimeur-test-cdp-events-named browser "Page.loadEventFired")) loads)))))

(defun imprimeur-test-cdp-click (browser element &optional button)
  "Click the middle of ELEMENT in BROWSER's page with BUTTON.
ELEMENT is a JavaScript expression giving the element; BUTTON is
\"left\", the default, or \"middle\"."
  (let ((point (imprimeur-test-cdp-eval
                browser (format "(() => { const box = (%s).getBoundingClientRect();
return [box.x + box.width / 2, box.y + box.height / 2]; })()"
                                element))))
    (dolist (type '("mousePressed" "mouseReleased"))
      (imprimeur-test-cdp-call browser "Input.dispatchMouseEvent"
                               `(:type ,type :x ,(aref point 0) :y ,(aref point 1)
                                       :button ,(or button "left") :clickCount 1)))))

(defun imprimeur-test-cdp-wheel (browser delta)
  "Turn the wheel over BROWSER's page, by DELTA pixels towards the end."
  (imprimeur-test-cdp-call browser "Input.dispatchMouseEvent"
                           `(:type "mouseWheel" :x 100 :y 100 :deltaX 0 :deltaY ,delta)))

(defun imprimeur-test-cdp-posted (browser route)
  "Return the JSON bodies, as plists, that BROWSER posted to a URL ending in ROUTE."
  (mapcar (lambda (params)
            (json-parse-string (plist-get (plist-get params :request) :postData) :object-type 'plist))
          (seq-filter (lambda (params)
                        (let ((request (plist-get params :request)))
                          (and (equal (plist-get request :method) "POST")
                               (string-suffix-p route (plist-get request :url)))))
                      (imprimeur-test-cdp-events-named browser "Network.requestWillBeSent"))))

(defun imprimeur-test-cdp-errors (browser)
  "Return the errors that BROWSER's page logged or threw."
  (append (imprimeur-test-cdp-events-named browser "Runtime.exceptionThrown")
          (seq-filter (lambda (params) (equal (plist-get params :type) "error"))
                      (imprimeur-test-cdp-events-named browser "Runtime.consoleAPICalled"))
          (seq-filter (lambda (params) (equal (plist-get (plist-get params :entry) :level) "error"))
                      (imprimeur-test-cdp-events-named browser "Log.entryAdded"))))

(defun imprimeur-test-cdp-escaped (browser)
  "Return the URLs that BROWSER requested off the loopback address.
A request that the browser blocked, by the page's policy for one,
never left and is left out."
  (let ((blocked (mapcar (lambda (params) (plist-get params :requestId))
                         (seq-filter (lambda (params) (plist-get params :blockedReason))
                                     (imprimeur-test-cdp-events-named browser "Network.loadingFailed")))))
    (delq nil (mapcar (lambda (params)
                        (let ((url (plist-get (plist-get params :request) :url)))
                          (and (not (member (plist-get params :requestId) blocked))
                               (not (string-match-p "\\`\\(?:data:\\|blob:\\|about:\\|http://127\\.0\\.0\\.1:\\)"
                                                    url))
                               url)))
                      (imprimeur-test-cdp-events-named browser "Network.requestWillBeSent")))))

(defun imprimeur-test-cdp-pages (browser)
  "Return the number of pages open in BROWSER."
  (seq-count (lambda (target) (equal (plist-get target :type) "page"))
             (plist-get (imprimeur-test-cdp-call browser "Target.getTargets") :targetInfos)))

(provide 'imprimeur-test-cdp)

;;; imprimeur-test-cdp.el ends here
