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

(defconstant +header-length+ 6)
(defvar *server-thread* nil)
(defvar *listening-socket* nil)

;; --- Core Logic ---

(defun capture-eval (source)
  (handler-case
      (let* ((sexp (read-from-string source))
             (eval-result nil)
             (stdout (with-output-to-string (*standard-output*)
                       (setf eval-result (eval sexp)))))
        (list :|ok| t :|value| (prin1-to-string eval-result) :|stdout| stdout))
    (error (c)
      (list :|ok| nil :|err| (format nil "~a" c)))))

(defun make-envelope (payload)
  (let ((resp (alex:plist-hash-table payload :test 'equal)))
    (setf (gethash "package" resp) (package-name *package*))
    resp))

(defun dispatch-request (request)
  (let ((op (gethash "op" request))
        (id (gethash "id" request)))
    (alex:switch (op :test #'string-equal)
      ("ping" (make-envelope `("id" ,id "ok" t)))
      ("eval" 
       (let ((results (map 'list 
                           (lambda (code) (alex:plist-hash-table (capture-eval code) :test 'equal))
                           (gethash "code" request))))
         (make-envelope `("id" ,id "ok" t "results" ,results))))
      (t (make-envelope `("id" ,id "ok" nil "err" "Unknown op"))))))

;; --- Networking ---

(defun read-u8-string (stream length)
  (let ((buf (make-array length :element-type '(unsigned-byte 8))))
    (unless (= (read-sequence buf stream) length) (error 'end-of-file))
    (flexi:octets-to-string buf :external-format :utf-8)))

(defun handle-client (socket)
  (let ((stream (us:socket-stream socket)))
    (handler-case
        (loop
          (let* ((header (read-u8-string stream +header-length+))
                 (len (parse-integer header :radix 16))
                 (body-str (read-u8-string stream len))
                 (request (jzon:parse body-str))
                 (response (dispatch-request request))
                 (json (jzon:stringify response))
                 (envelope (format nil "~6,'0X~a" (length json) json))
                 (octets (flexi:string-to-octets envelope :external-format :utf-8)))
            (write-sequence octets stream)
            (finish-output stream)))
      (end-of-file ())
      (error (c) (format *error-output* "Worker error: ~a~%" c)))
    (ignore-errors (us:socket-close socket))))

;; --- Lifecycle ---

(defun start-server (&key (host "127.0.0.1") (port 4005))
  (when (and *server-thread* (bt:thread-alive-p *server-thread*))
    (format t "Server is already running.~%")
    (return-from start-server))
  (setf *listening-socket* (us:socket-listen host port :reuse-address t))
  (setf *server-thread* (bt:make-thread 
         (lambda ()
           (handler-case
               (loop for client = (us:socket-accept *listening-socket* :element-type 'flexi:octet)
                     do (bt:make-thread (lambda () (handle-client client)) :name "Ooze Worker"))
             (error () (format t "Ooze server loop stopped.~%"))))
         :name "Ooze Main"))
  (format t "Ooze server started on ~A:~A~%" host port))

(defun stop-server ()
  (when *listening-socket*
    (us:socket-close *listening-socket*)
    (setf *listening-socket* nil))
  (when (and *server-thread* (bt:thread-alive-p *server-thread*))
    (bt:destroy-thread *server-thread*)
    (setf *server-thread* nil))
  (format t "Ooze server stopped.~%"))

(defun main ()
  "Starts server and keeps REPL alive."
  (let* ((args sb-ext:*posix-argv*)
         (host (or (cadr (member "--host" args :test #'string-equal)) "127.0.0.1"))
         (port (or (alex:when-let ((p-str (cadr (member "--port" args :test #'string-equal))))
                     (parse-integer p-str :junk-allowed t))
                   4005)))
    (start-server :host host :port port)))
