(ql:quickload '("usocket" "bordeaux-threads" "cl-json" "flexi-streams"))

(defpackage #:ooze-server
  (:use #:cl)
  (:export #:start-server #:stop-server #:main)
  (:local-nicknames
   (#:usocket #:usocket)
   (#:bt #:bordeaux-threads)
   (#:json #:cl-json)
   (#:flexi #:flexi-streams)))

(in-package #:ooze-server)

(defvar *server-thread* nil
  "Holds the server thread.")

(defvar *listening-socket* nil
  "Holds the main server listening socket.")

(defun read-exact-bytes (stream count)
  "Reads exactly COUNT bytes from STREAM."
  (let ((buffer (make-array count :element-type '(unsigned-byte 8))))
    (read-sequence buffer stream)
    buffer))

(defun process-request (body-str stream)
  "Decodes a JSON request, evaluates it, and sends a JSON response."
  (handler-case
      (let* ((request (json:decode-json-from-string body-str))
             (id (cdr (assoc :id request)))
             (op (cdr (assoc :op request))))

        (when (and id op)
          (let ((response
                  (cond
                    ((string-equal op "eval")
                     (let* ((code (cdr (assoc :code request)))
                            (pkg-name (cdr (assoc :package request)))
                            (package (find-package (string-upcase pkg-name))))
                       (handler-case
                           (let* ((form (read-from-string code))
                                  (result nil)
                                  (output (with-output-to-string (*standard-output*)
                                            (let ((*package* package))
                                            (setf result (eval form))))))
                             `((:id . ,id)
                               (:ok . t)
                               (:result . ,(prin1-to-string result))
                               (:stdout . ,output)))
                         (error (c)
                           `((:id . ,id)
                             (:ok . nil)
                             (:err . ,(format nil "Evaluation error: ~a" c)))))))
                    (t
                     `((:id . ,id)
                       (:ok . nil)
                       (:err . ,"Unknown operation"))))))

            ;; Send the response
            (when response
              (let* ((response-json (json:encode-json-to-string response))
                     (response-msg (format nil "~6,'0X~a" (length response-json) response-json)))
                (write-sequence response-msg stream)
                (finish-output stream))))))
    (error (c)
      (format *error-output* "Failed to process request: ~a~%" c))))

(defun handle-client (socket)
  "Handles a single client connection."
  (unwind-protect
       (let ((stream (usocket:socket-stream socket)))
         (handler-case
             (loop
               ;; 1. Read the 6-byte hex length prefix
               (let* ((len-bytes (read-exact-bytes stream 6))
                      (len-str (flexi:octets-to-string len-bytes :external-format :utf-8))
                      (msg-len (parse-integer len-str :radix 16)))

                 ;; 2. Read the message body of `msg-len` bytes
                 (let* ((body-bytes (read-exact-bytes stream msg-len))
                        (body-str (flexi:octets-to-string body-bytes :external-format :utf-8)))

                   ;; 3. Process the request
                   (process-request body-str stream))))

           ;; Handle client disconnecting gracefully
           (end-of-file ()
             (format t "Client disconnected.~%")
             (return-from handle-client))
           (error (c)
             (format *error-output* "Error in client handler: ~a~%" c)
             (return-from handle-client))))

    ;; This cleanup form ensures the socket is closed no matter what.
    (usocket:socket-close socket)))

(defun run-server-loop (host port)
  "Main server loop to listen for and handle connections."
  (unwind-protect
       (progn
         (setf *listening-socket* (usocket:socket-listen host port :reuse-address t))
         (format t "Ooze server listening on ~a:~a~%" host port)
         (loop
           (handler-case
               (let ((client-socket (usocket:socket-accept *listening-socket* :element-type 'flexi:octet)))
                 (when client-socket
                   (bt:make-thread
                     (lambda () (handle-client client-socket))
                     :name "Ooze Client Handler")))

             ;; We catch any error here.
             (error (c)
               ;; If *listening-socket* is nil, it means we called stop-server, so the
               ;; resulting error is expected and we can exit silently.
               ;; Otherwise, it was an unexpected error that we should report.
               (when *listening-socket*
                 (format *error-output* "Error in server accept loop: ~a~%" c))
               (return-from run-server-loop)))))

    ;; Cleanup form for unwind-protect
    (when *listening-socket*
      (usocket:socket-close *listening-socket*)
      (setf *listening-socket* nil))))

(defun start-server (&key (host "127.0.0.1") (port 4005))
  "Starts the Ooze server in a new thread."
  (when (and *server-thread* (bt:thread-alive-p *server-thread*))
    (format t "Ooze server is already running.~%")
    (return-from start-server))

  (setf *server-thread*
        (bt:make-thread
         (lambda ()
           (handler-case
               (run-server-loop host port)
             (error (c)
               (format *error-output* "Ooze server error: ~a~%" c))))
         :name "Ooze Server")))

(defun stop-server ()
  "Stops the Ooze server thread if it is running."
  (when *listening-socket*
    (format t "Closing server socket...~%")
    (usocket:socket-close *listening-socket*)
    (setf *listening-socket* nil))
  (if (and *server-thread* (bt:thread-alive-p *server-thread*))
      (progn
        (format t "Destroying server thread...~%")
        (bt:destroy-thread *server-thread*)
        (setf *server-thread* nil)
        (format t "Server stopped.~%"))
      (format t "Ooze server is not running or thread already stopped.~%")))

(defun parse-cli-args (args)
  "Parses command-line arguments for --host and --port."
  (let ((host nil)
        (port nil)
        ;; Make a copy so we don't modify the original list
        (remaining-args (copy-list args)))
    (loop while remaining-args
          for arg = (pop remaining-args)
          do (cond
               ((string-equal arg "--host")
                (setf host (pop remaining-args)))
               ((string-equal arg "--port")
                (let ((port-str (pop remaining-args)))
                  (when port-str
                    (setf port (parse-integer port-str :junk-allowed t)))))))
    (list :host host :port port)))

(defun main ()
  "The main entry point for running the server from the command line."
  (let* ((cli-args (parse-cli-args sb-ext:*posix-argv*))
         (host (or (getf cli-args :host) "127.0.0.1"))
         (port (or (getf cli-args :port) 4005)))
    (start-server :host host :port port)))
