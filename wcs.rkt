#lang racket

;;;; Reading FSMs from sources
;;;
;;; FSMs are read from sources, each of which contains a single form
;;; which is a list of patterns.
;;;
;;; A source is either a file or a comment specification.  A file is
;;; specified by name and a command specification is a list of the form
;;; (run <path-to-command> . <arguments>).  A file is simply read, while
;;; the standard output of a command is read.
;;;
;;; The default set of sources is "/etc/warranted/commands.rktd",
;;; "/usr/local/etc/warranted/commands.rktd" and
;;; "~/etc/warranted/commands.rktd": all of these are checked and if
;;; they exist read into a single WCT.
;;;
;;; Before doing this a fixed set of meta files is searched: the set
;;; is "/etc/warranted/meta.rktd", "/local/etc/warranted/meta.rktd",
;;; "~/etc/warranted/meta.rktd".  If any of these files exists, then
;;; the first in the list, only, is read, and it should contain a
;;; single list of specification files which will be searched as above
;;; instead of the default set.  This means that, for instance, by
;;; specifiying a different set of files in
;;; "/etc/warranted/meta.rktd", you can prevent user config files
;;; being read at all and ensure that only suitably-safe files are
;;; read.
;;;
;;; Note that commands, but not their arguments, are matched against
;;; the absolute path of the executable: so 'cat foo' would turn into
;;; '/bin/cat foo' for instance.
;;;
;;; It would be nice at some point to abstract the notion of a source,
;;; so sources might all be of the form (<key> . <spec>).  On the other
;;; hand, once you have command sources do you actually need anything else?
;;;

(require "low.rkt"
         (only-in "fsm.rkt"
                  valid-patterns?
                  patterns->fsm
                  fsm?))

(provide (contract-out
          (warranted-commands-sources
           (case->
            (-> (-> (listof valid-wcs-specification?)))
            (-> (-> (listof valid-wcs-specification?))
                void?)))
          (default-warranted-commands-sources
            (-> (-> (listof valid-wcs-specification?))))
          (read-fsm
           (->* ()
                ((listof valid-wcs-specification?))
                fsm?))
          (command->string
           (-> string? (listof string?) string?)))
         (struct-out exn:fail:bad-patterns)
         (struct-out exn:fail:bad-metafile)
         (struct-out exn:fail:command-error))

(module+ test
  (require rackunit))

(struct exn:fail:bad-patterns exn:fail (spec source)
  ;; A bad pattern specification
  #:extra-constructor-name make-exn:fail:bad-patterns
  #:transparent)

(struct exn:fail:bad-metafile exn:fail (wcss source)
  ;; something wrong with a metafile
  #:extra-constructor-name make-exn:fail:bad-metafile
  #:transparent)

(define (read-safely in)
  ;; Try to read safely from a port.
  ;; This is probably not enough, but it is at least a start
  (call-with-default-reading-parameterization
   (thunk
    (parameterize ([read-accept-lang #f]
                   [read-accept-reader #f])
      (read in)))))

(module+ test
  (test-case
   "Check that read-safely is a bit safe"
   (check-exn
    exn:fail:read?
    (thunk
     (call-with-input-string "#reader \"foo\" (foo)"
                             read-safely)))
   (check-exn
    exn:fail:read?
    (thunk
     (call-with-input-string "#lang racket (foo)"
                             read-safely)))))

(define (valid-wcs-specification? maybe-specification)
  ;; is maybe-specification a valid specification?
  (define (good-path? p)
    (and (path-string? p)
         (absolute-path? p)))
  (match maybe-specification
    [(list* 'run command arguments)
     (and (good-path? command)
          (andmap string? arguments))]
    [anything (good-path? anything)]))

(define (default-warranted-commands-sources)
  ;; This is the default returner of sources containing WCT specifications.
  ;; it looks for metafiles and if it finds any reads a list from the first
  ;; one (only).  Otherwise it returns the default list of files.
  ;; Because it only reads the first metafile it finds, if you create
  ;; /etc/warranted-meta.rktd, then you can control the list of files
  ;; without allowing the user to do so.
  (let* ([home (find-system-path 'home-dir)]
         [root (first (explode-path home))]
         [wcf "commands.rktd"]
         [metaf "meta.rktd"])
    (define (locations file)
      (list (build-path root "etc" "warranted" file)
            (build-path root "usr" "local" "etc" "warranted" file)
            (build-path home "etc" "warranted" file)))
    (let search ([metafiles (locations metaf)])
      (if (null? metafiles)
          (let ([wcfs (locations wcf)])
            (debug "[wct files from whole cloth~%~A]~%"
                   (pretty-format wcfs))
            wcfs)
          (match-let ([(cons metafile more-metas) metafiles])
            (debug "[looking for metafile ~A]~%" metafile)
            (let ([wcss (and (file-exists? metafile)
                             (call-with-input-file metafile read-safely))])
              (cond [wcss
                     (debug "[wct sources from ~A~%~A]~%"
                            metafile (pretty-format wcss))
                     (unless (and (list? wcss)
                                  (andmap valid-wcs-specification?
                                          wcss))
                       (raise (make-exn:fail:bad-metafile
                               "bad file list from metafile"
                               (current-continuation-marks)
                               wcss metafile)))
                     wcss]
                    [else
                     (search more-metas)])))))))

(define warranted-commands-sources
  ;; This is a parameter whose value is a function which should return
  ;; the list of files with WCT specifications.
  (make-parameter default-warranted-commands-sources))

(define (read-fsm (sources ((warranted-commands-sources))))
  ;; Read an FSM from a set of sources, with the default being whatever
  ;; warranted-commands-sources returns.
  (patterns->fsm
   (for/fold ([wcs '()] #:result (reverse wcs)) ([source sources])
     (match source
       [(list* 'run command arguments)
        (append (read-fsm/command command arguments) wcs)]
       [file
        (append (read-fsm/file file) wcs)]))))


;;; File sources
;;;

(define (read-fsm/file file)
  (debug "[looking for wct file ~A]~%" file)
  (if (file-exists? file)
      (let ([spec (call-with-input-file file read-safely)])
        (debug "[entries from ~A~%~A]~%"
               file (pretty-format spec))
        (unless (valid-patterns? spec)
          (raise (make-exn:fail:bad-patterns
                  "bad patterns"
                  (current-continuation-marks)
                  spec file)))
        spec)
      '()))


;;; Command sources
;;;

(struct exn:fail:command-error exn:fail (command arguments status stderr)
  ;; something wrong when running a command
  #:extra-constructor-name make-exn:fail:command-error
  #:transparent)

(define (command->string command arguments)
  ;; A pretty string for debugging
  (string-join (cons command arguments)))

(define (read-fsm/command command arguments)
  (define command-string (command->string command arguments))
  (debug "[looking for command ~A]~%" command-string)
  (if (file-exists? command)
      (let-values ([(status stdout-bytes stderr-bytes wakeups)
                    (run-command command arguments)])
        (if (zero? status)
            (if (> (bytes-length stdout-bytes) 0)
                ;; special case: command OK but no output: ignore it
                (let ([entries (read-safely (open-input-bytes stdout-bytes))])
                  (when (> (bytes-length stderr-bytes) 0)
                    (debug "[stderr ~A]~%" (bytes->string/locale stderr-bytes)))
                  (debug "[entries from ~A~%~A]~%"
                         command-string (pretty-format entries))
                  entries)
                (begin
                  (debug "[nothing from ~A]~%" command-string)
                  '()))
            (raise (make-exn:fail:command-error
                    command-string
                    (current-continuation-marks)
                    command arguments status stderr-bytes))))
      '()))

(define (run-command cmd args)
  ;; Run a command and return exit code, stdout & stderr
  ;; as byte strings and the number of wakeups.
  ;; I hope this will not block.
  (let-values ([(proc proc-stdout proc-stdin proc-stderr)
                (apply subprocess #f #f #f cmd args)])
    (dynamic-wind
     (thunk (close-output-port proc-stdin))
     (thunk
      (define (prepend-port-chunk p to (close? #f))
        (if (not (port-closed? p))
            (let ([got (port->bytes p #:close? close?)])
              (if (and (bytes? got)
                       (> (bytes-length got) 0))
                  (cons got to)
                  to))
            to))
      ;; wait on the ports and the process
      (define (next-status)
        (sync proc-stdout (eof-evt proc-stdout)
              proc-stderr (eof-evt proc-stderr)
              proc)
        (subprocess-status proc))
      (for/fold ([status 'running]
                 [stdout-bytes '()]
                 [stderr-bytes '()]
                 [wakeups 0]
                 #:result (values status
                                  (bytes-append*
                                   (reverse (prepend-port-chunk
                                             proc-stdout stdout-bytes #t)))
                                  (bytes-append*
                                   (reverse (prepend-port-chunk
                                             proc-stderr stderr-bytes #t)))
                                  wakeups))
                ([next (in-producer next-status)])
        #:break (not (eq? status 'running))
        (values next
                (prepend-port-chunk proc-stdout stdout-bytes)
                (prepend-port-chunk proc-stderr stderr-bytes)
                (+ wakeups 1))))
     (thunk
      (close-input-port proc-stdout)
      (close-input-port proc-stderr)))))
