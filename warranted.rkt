#lang racket

;;; Warranted commands
;;;

(require "wct.rkt"
         (only-in racket/system
                  system*/exit-code))

(struct exn:fail:death exn:fail ()
  #:extra-constructor-name make-exn:fail:death
  #:transparent)

(define (die fmt . args)
  (raise (make-exn:fail:death
          (apply format fmt args)
          (current-continuation-marks))))

(define (run #:wct (wct (read-wct))
             #:args (argv (current-command-line-arguments)))
  (define command-list (vector->list argv))
  (cond [(not (null? command-list))
         (unless (slist-matches-wct? command-list wct)
           (die "unwarranted command line ~S" command-list)
         (match-let ([(cons command arguments) command-list])
           (unless (absolute-path? command)
             (die "command is not absolute: ~S" command))
           (exit (apply system*/exit-code command arguments))))]
        [else
         (die "Usage: warranted command arg ...")]))

(module+ main
  (with-handlers ([exn:fail:death?
                   (λ (e)
                     (fprintf (current-error-port)
                              "~A~%" (exn-message e))
                     (exit 1))]
                  [exn:fail:bad-wct-spec?
                   (λ (e)
                     (fprintf (current-error-port)
                              "~A in ~A~"
                              (exn-message e)
                              (exn:fail:bad-wct-spec-source e))
                     (exit 2))]
                  [exn?
                   (λ (e)
                     (fprintf (current-error-port)
                              "mutant death: ~A~%" (exn-message e))
                     (exit 3))])
    (run)))
