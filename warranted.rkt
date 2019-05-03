#!/usr/bin/env racket
#lang racket

;;; Warranted commands
;;;
;;; This needs rethinking about when it dies (should run raise exceptions?)
;;; and more generally about verbosity &c
;;;
;;; It also needs more tests
;;;

(require "wct.rkt"
         "low.rkt"
         (only-in racket/system
                  system*/exit-code)
         (rename-in racket
                    (exit really-exit)))

(module+ test
  (require rackunit))

(struct exn:fail:death exn:fail ()
  #:extra-constructor-name make-exn:fail:death
  #:transparent)

(define (die fmt . args)
  (raise (make-exn:fail:death
          (apply format fmt args)
          (current-continuation-marks))))

;;; Exit control: I would like to be able to make this work so it knew
;;; whether it was running under DrRacket automatically.  Instead you can say
;;; WARRANTED_DEVELOPMENT=1 drracket ...
;;;
(define warranted-development?
  (make-parameter (if (getenv "WARRANTED_DEVELOPMENT") #t #f)))

(define (exit code)
  (cond [(warranted-development?)
         (mutter "[would exit with ~S]~%" code)
         code]
        [else
         (really-exit code)]))

;;; Control whether we actually run commands
;;;
(define warranted-pretend?
  (make-parameter (if (getenv "WARRANTED_PRETEND") #t #f)))

(define (run-command command-line #:pretend-exit-code (pretend-exit-code 0))
  (cond [(warranted-pretend?)
         (mutter "[would run ~S]~%" command-line)
         pretend-exit-code]
        [else
         (apply system*/exit-code command-line)]))

(define (run #:wct (wct (read-wct))
             #:argv (argv (current-command-line-arguments))
             #:pretend-exit-code (pretend-exit-code 0))
  ;; Run a warranted command.  This either returns the exit code of the command,
  ;; or raises an exception.
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
           (exit (run-command effective-command-line
                              #:pretend-exit-code pretend-exit-code))]
          [else
           (die "Usage: warranted command arg ...")])))

(module+ test
  (parameterize ([warranted-development? #t]
                 [warranted-pretend? #t]
                 [warranted-quiet? #t])
    (let ([wct '(("/bin/cat" ("foo" ())
                             ("bar" ())))])
      (check-eqv? (run #:wct wct
                       #:argv '#("cat" "foo"))
                  0)
      (check-eqv? (run #:wct wct
                       #:argv '#("cat" "bar"))
                  0)
      (check-exn exn:fail:death?
                 (thunk (run #:wct wct
                             #:argv '#("cat" "fish")))))))

(module+ main
  (with-handlers ([exn:fail:death?
                   (λ (e)
                     (complain "~A~%" (exn-message e))
                     (exit 1))]
                  [exn:fail:bad-wct-spec?
                   (λ (e)
                     (complain "~A in ~A~%"
                               (exn-message e)
                               (exn:fail:bad-wct-spec-source e))
                     (exit 2))]
                  [exn:fail:bad-metafile?
                   (λ (e)
                     (complain "~A ~A~%"
                               (exn-message e)
                               (exn:fail:bad-metafile-source e))
                     (exit 2))]
                  [exn?
                   (λ (e)
                     (complain "mutant death~% ~A~%" (exn-message e))
                     (exit 3))])
    (run)))
