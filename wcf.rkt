#lang racket

;;;; Reading FSMs from files
;;;
;;; FSMs are read from files, each of which contains a single form
;;; which is a list of patterns.
;;;
;;; The default set of files is "/etc/warranted/commands.rktd",
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
;;; Note that ommands, but not their arguments, are matched against
;;; the absolute path of the executable: so 'cat foo' would turn into
;;; '/bin/cat foo' for instance.
;;;

(require "low.rkt"
         (only-in "fsm.rkt"
                  valid-patterns?
                  patterns->fsm
                  fsm?))


(provide (contract-out
          (warranted-commands-files
           (case->
            (-> (-> (listof (and/c path-string? absolute-path?))))
            (-> (-> (listof (and/c path-string? absolute-path?)))
                void?)))
          (default-warranted-commands-files
            (-> (-> (listof (and/c path-string? absolute-path?)))))
          (read-fsm
           (->* ()
                ((listof (and/c path-string? absolute-path?)))
                fsm?)))
         (struct-out exn:fail:bad-patterns)
         (struct-out exn:fail:bad-metafile))

(module+ test
  (require rackunit))

(struct exn:fail:bad-patterns exn:fail (spec source)
  ;; A bad pattern specification
  #:extra-constructor-name make-exn:fail:bad-patterns
  #:transparent)

(struct exn:fail:bad-metafile exn:fail (wcfs source)
  ;; something wrong with a metafile
  #:extra-constructor-name make-exn:fail:bad-metafile
  #:transparent)

(define (default-warranted-commands-files)
  ;; This is the default returner of files containing WCT specifications.
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
            (let ([wcfs (and (file-exists? metafile)
                             (call-with-default-reading-parameterization
                              (thunk (call-with-input-file metafile read))))])
              (cond [wcfs
                     (debug "[wct files from ~A~%~A]~%"
                            metafile (pretty-format wcfs))
                     (unless (and (list? wcfs)
                                  (andmap (λ (wcf)
                                            (and (path-string? wcf)
                                                 (absolute-path? wcf)))
                                          wcfs))
                       (raise (make-exn:fail:bad-metafile
                               "bad file list from metafile"
                               (current-continuation-marks)
                               wcfs metafile)))
                     wcfs]
                    [else
                     (search more-metas)])))))))

(define warranted-commands-files
  ;; This is a parameter whose value is a function which should return
  ;; the list of files with WCT specifications.
  (make-parameter default-warranted-commands-files))

(define (read-fsm (files ((warranted-commands-files))))
  ;; Read an FSM from a set of files, with the default being whatever
  ;; warranted-command-files returns.
  (patterns->fsm
   (for/fold ([wcs '()]) ([file files])
     (debug "[looking for wct file ~A]~%" file)
     (append wcs (if (file-exists? file)
                     (let ([spec (call-with-default-reading-parameterization
                                  (thunk (call-with-input-file file read)))])
                       (debug "[entries from ~A~%~A]~%"
                              file (pretty-format spec))
                       (unless (valid-patterns? spec)
                         (raise (make-exn:fail:bad-patterns
                                 "bad patterns"
                                 (current-continuation-marks)
                                 spec file)))
                       spec)
                     '())))))
