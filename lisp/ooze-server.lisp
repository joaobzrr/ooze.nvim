(ql:quickload '("usocket" "bordeaux-threads" "com.inuoe.jzon" "flexi-streams" "alexandria"))

(defpackage #:ooze-server
  (:use #:cl)
  (:export #:start-server #:stop-server #:main)
  (:local-nicknames
    (#:us :usocket)
    (#:bt :bordeaux-threads)
    (#:jzon :com.inuoe.jzon)
    (#:flexi :flexi-streams)
    (#:alex :alexandria)))

(in-package #:ooze-server)

(defvar *server-thread* nil)
(defvar *listening-socket* nil)
(defconstant +header-length+ 6)

(defun eval-form-capturing-output (source)
  "Evaluates a single string source, returning a result hash-table with correct value/stdout."
  (handler-case
      (let* ((form (read-from-string source))
             (eval-result nil)
             (captured-stdout (with-output-to-string (*standard-output*)
                                (setf eval-result (eval form)))))
        (alex:plist-hash-table 
         `("ok" t 
           "value" ,(prin1-to-string eval-result) 
           "stdout" ,captured-stdout) 
         :test 'equal))
    (error (c)
      (alex:plist-hash-table `("ok" nil "err" ,(format nil "~a" c)) :test 'equal))))

(defun dispatch-op (request)
  "Routes operations to specific handlers."
  (let ((op (gethash "op" request))
        (id (gethash "id" request)))
    (alex:switch (op :test #'string-equal)
      ("eval" 
       (let ((results (map 'list #'eval-form-capturing-output (gethash "code" request))))
         (alex:plist-hash-table `("id" ,id "ok" t "results" ,results) :test 'equal)))
      (t (alex:plist-hash-table `("id" ,id "ok" nil "err" "Unknown op") :test 'equal)))))

(defun send-json (response stream)
  (let* ((json (jzon:stringify response))
         (envelope (format nil "~6,'0X~a" (length json) json))
         (octets (flexi:string-to-octets envelope :external-format :utf-8)))
    (write-sequence octets stream)
    (finish-output stream)))

(defun handle-client (socket)
  (let ((stream (us:socket-stream socket)))
    (handler-case
        (loop
          (let* ((len-buf (make-array +header-length+ :element-type '(unsigned-byte 8))))
            (read-sequence len-buf stream)
            (let* ((len (parse-integer (flexi:octets-to-string len-buf) :radix 16))
                   (body-buf (make-array len :element-type '(unsigned-byte 8))))
              (read-sequence body-buf stream)
              (let* ((body-str (flexi:octets-to-string body-buf))
                     (request (jzon:parse body-str))
                     (response (dispatch-op request)))
                (send-json response stream)))))
      (end-of-file () (format t "Client closed connection.~%"))
      (error (c) (format *error-output* "Client error: ~a~%" c)))
    (us:socket-close socket)))

(defun run-server-loop (host port)
  (setf *listening-socket* (us:socket-listen host port :reuse-address t))
  (format t "Ooze listening on ~a:~a~%" host port)
  (handler-case
      (loop
        (let ((client (us:socket-accept *listening-socket* :element-type 'flexi:octet)))
          (when client
            (bt:make-thread (lambda () (handle-client client)) :name "Ooze Worker"))))
    (error () (format t "Server loop shutting down.~%"))))

(defun start-server (&key (host "127.0.0.1") (port 4005))
  (unless (and *server-thread* (bt:thread-alive-p *server-thread*))
    (setf *server-thread* (bt:make-thread (lambda () (run-server-loop host port)) :name "Ooze Main"))))

(defun stop-server ()
  (let ((sock *listening-socket*))
    (setf *listening-socket* nil)
    (when sock (us:socket-close sock)))
  (when (and *server-thread* (bt:thread-alive-p *server-thread*))
    (bt:destroy-thread *server-thread*)
    (setf *server-thread* nil)))

(defun parse-cli-args (args)
  (let ((host nil)
        (port nil)
        (remaining-args (copy-list args)))
    (loop while remaining-args
          for arg = (pop remaining-args)
          do (cond
               ((string-equal arg "--host") (setf host (pop remaining-args)))
               ((string-equal arg "--port")
                (let ((port-str (pop remaining-args)))
                  (when port-str (setf port (parse-integer port-str :junk-allowed t)))))))
    (list :host host :port port)))

(defun main ()
  (let* ((cli-args (parse-cli-args sb-ext:*posix-argv*))
         (host     (or (getf cli-args :host) "127.0.0.1"))
         (port     (or (getf cli-args :port) 4005)))
    (start-server :host host :port port)))
