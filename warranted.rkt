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
  (let ([command-line (vector->list argv)])
    (cond [(not (null? command-line))
           (define command (first command-line))
           (define executable (find-executable-path command))
           (unless executable
             (die "no executable for ~A" command))
           (define effective-command-line (cons (path->string executable)
                                                (rest command-line)))
           (unless (slist-matches-wct? effective-command-line wct)
             (die "unwarranted command line ~S (from ~S)"
                  effective-command-line command-line))
           (unless (absolute-path? executable)
             (die "command is not absolute: ~S (from ~S)"
                  executable command))
           (exit (apply system*/exit-code effective-command-line))]
          [else
           (die "Usage: warranted command arg ...")])))

(module+ main
  (with-handlers ([exn:fail:death?
                   (λ (e)
                     (fprintf (current-error-port)
                              "~A~%" (exn-message e))
                     (exit 1))]
                  [exn:fail:bad-wct-spec?
                   (λ (e)
                     (fprintf (current-error-port)
                              "~A in ~A~%"
                              (exn-message e)
                              (exn:fail:bad-wct-spec-source e))
                     (exit 2))]
                  [exn?
                   (λ (e)
                     (fprintf (current-error-port)
                              "mutant death~% ~A~%" (exn-message e))
                     (exit 3))])
    (run)))
