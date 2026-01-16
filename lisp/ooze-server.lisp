(ql:quickload '("usocket" "bordeaux-threads" "com.inuoe.jzon" "cl-json" "flexi-streams" "alexandria"))

(defpackage #:ooze-server
  (:use #:cl)
  (:export #:start-server
           #:stop-server
           #:main)
  (:local-nicknames
   (#:usocket #:usocket)
   (#:bt      #:bordeaux-threads)
   (#:jzon    #:com.inuoe.jzon)
   (#:flexi   #:flexi-streams)
   (#:alex    #:alexandria)))

(in-package #:ooze-server)

(defvar *server-thread* nil
  "Holds the server thread.")

(defvar *listening-socket* nil
  "Holds the main server listening socket.")

(defun read-bytes (stream count)
  (let ((buffer (make-array count :element-type '(unsigned-byte 8))))
    (read-sequence buffer stream)
    buffer))

(defun process-request (body-str stream)
  "Decodes a JSON request, evaluates it, and sends a JSON response."
  (handler-case
      (let* ((request (jzon:parse body-str))
             (id      (gethash "id" request))
             (op      (gethash "op" request)))
        (when (and id op)
          (let ((response
                  (cond
                    ((string-equal op "eval")
                     (let ((source (gethash "code" request)))
                       (handler-case
                           (let ((results '()))
                             (with-input-from-string (s source)
                               (loop
                                 (handler-case
                                     (let ((form (read s nil 'eof)))
                                       (when (eq form 'eof) (return))
                                       (let (value form-stdout)
                                         (setf form-stdout
                                               (with-output-to-string (*standard-output*)
                                                 (setf value (eval form))))
                                         (push (alex:plist-hash-table
                                                `("ok"     t
                                                  "value"  ,(prin1-to-string value)
                                                  "stdout" ,form-stdout)
                                                :test 'equal)
                                               results)))
                                   (error (c)
                                     (push (alex:plist-hash-table
                                            `("ok"  nil  ;; nil = JSON false in jzon
                                              "err" ,(format nil "Evaluation error: ~a" c))
                                            :test 'equal)
                                           results)))))
                             (setq results (nreverse results))
                             (alex:plist-hash-table
                              `("id"      ,id
                                "ok"      t
                                "results" ,results)
                              :test 'equal))
                         (error (c)
                           (alex:plist-hash-table
                            `("id" ,id
                              "ok"  nil
                              "err" ,(format nil "Evaluation error: ~a" c))
                            :test 'equal)))))
                    (t
                     (alex:plist-hash-table
                      `("id" ,id
                        "ok"  nil
                        "err" "Unknown operation")
                      :test 'equal)))))
            (when response
              (let* ((response-json (jzon:stringify response))
                     (response-msg (format nil "~6,'0X~a"
                                           (length response-json)
                                           response-json))
                     (octets (flexi:string-to-octets
                              response-msg
                              :external-format :utf-8)))
                (write-sequence octets stream)
                (finish-output stream))))))
    (error (c)
      (format *error-output* "Failed to process request: ~a~%" c))))

(defun handle-client (socket)
  "Handles a single client connection."
  (unwind-protect
       (let ((stream (usocket:socket-stream socket)))
         (handler-case
             (loop
               (let* ((len-bytes (read-bytes stream 6))
                      (len-str
                        (flexi:octets-to-string
                         len-bytes
                         :external-format :utf-8))
                      (msg-len
                        (parse-integer len-str :radix 16)))
                 (let* ((body-bytes (read-bytes stream msg-len))
                        (body-str
                          (flexi:octets-to-string
                           body-bytes
                           :external-format :utf-8)))
                   (process-request body-str stream))))
           (end-of-file ()
             (format t "Client disconnected.~%")
             (return-from handle-client))
           (error (c)
             (format *error-output*
                     "Error in client handler: ~a~%"
                     c)
             (return-from handle-client))))
    (usocket:socket-close socket)))

(defun run-server-loop (host port)
  "Main server loop to listen for and handle connections."
  (unwind-protect
       (progn
         (setf *listening-socket*
               (usocket:socket-listen host port
                                      :reuse-address t))
         (format t "Ooze server listening on ~a:~a~%"
                 host port)
         (loop
           (handler-case
               (let ((client-socket
                       (usocket:socket-accept
                        *listening-socket*
                        :element-type 'flexi:octet)))
                 (when client-socket
                   (bt:make-thread
                    (lambda ()
                      (handle-client client-socket))
                    :name "Ooze Client Handler")))
             (error (c)
               (when *listening-socket*
                 (format *error-output*
                         "Error in server accept loop: ~a~%"
                         c))
               (return-from run-server-loop)))))
    (when *listening-socket*
      (usocket:socket-close *listening-socket*)
      (setf *listening-socket* nil))))

(defun start-server (&key (host "127.0.0.1") (port 4005))
  "Starts the Ooze server in a new thread."
  (when (and *server-thread*
             (bt:thread-alive-p *server-thread*))
    (format t "Ooze server is already running.~%")
    (return-from start-server))
  (setf *server-thread*
        (bt:make-thread
         (lambda ()
           (unwind-protect
                (handler-case
                    (run-server-loop host port)
                  (error (c)
                    (format *error-output*
                            "Ooze server error: ~a~%"
                            c)))
             ;; Ensure the global is cleared when the thread exits
             (setf *server-thread* nil)))
         :name "Ooze Server")))

(defun stop-server ()
  "Stops the Ooze server thread if it is running."
  (cond
    ((and *server-thread*
          (bt:thread-alive-p *server-thread*))
     (format t "Stopping Ooze server...~%")
     (when *listening-socket*
       (format t "Closing server socket...~%")
       (usocket:socket-close *listening-socket*)
       (setf *listening-socket* nil))
     (bt:join-thread *server-thread*)
     (setf *server-thread* nil)
     (format t "Server stopped.~%"))
    (t
     (format t "Ooze server is not running.~%"))))

(defun parse-cli-args (args)
  "Parses command-line arguments for --host and --port."
  (let ((host nil)
        (port nil)
        (remaining-args (copy-list args)))
    (loop while remaining-args
          for arg = (pop remaining-args)
          do (cond
               ((string-equal arg "--host")
                (setf host (pop remaining-args)))
               ((string-equal arg "--port")
                (let ((port-str (pop remaining-args)))
                  (when port-str
                    (setf port
                          (parse-integer port-str
                                         :junk-allowed t)))))))
    (list :host host :port port)))

(defun main ()
  "The main entry point for running the server from the command line."
  (let* ((cli-args (parse-cli-args sb-ext:*posix-argv*))
         (host     (or (getf cli-args :host) "127.0.0.1"))
         (port     (or (getf cli-args :port) 4005)))
    (start-server :host host :port port)))
