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
                    (exit really-exit))
         (only-in racket/cmdline
                  command-line))

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

(define me "warranted")
(define usage
  (format "usage: ~A [option...] command [argument ...] (~A -h for help)"
          me me))

(define (run (args (vector->list (current-command-line-arguments)))
             #:wct (wct (read-wct))
             #:pretend-exit-code (pretend-exit-code 0))
  ;; Run a warranted command.  This either returns the exit code of the command,
  ;; or raises an exception.
  (cond [(not (null? args))
         (define command (first args))
         (define executable (find-executable-path command))
         (unless executable
           (die "no executable for ~A" command))
         (define effective-command-line (cons (path->string executable)
                                              (rest args)))
         (unless (slist-matches-wct? effective-command-line wct)
           (die "unwarranted command line ~S (from ~S)"
                effective-command-line args))
         (unless (absolute-path? executable)
           (die "command is not absolute: ~S (from ~S)"
                executable command))
         (exit (run-command effective-command-line
                            #:pretend-exit-code pretend-exit-code))]
        [else
         (die usage)]))

(module+ test
  (parameterize ([warranted-development? #t]
                 [warranted-pretend? #t]
                 [warranted-quiet? #t])
    (let ([wct '(("/bin/cat" ("foo" ())
                             ("bar" ())))])
      (check-eqv? (run '("cat" "foo")
                       #:wct wct)
                  0)
      (check-eqv? (run '("cat" "bar")
                       #:wct wct)
                  0)
      (check-exn exn:fail:death?
                 (thunk (run '("cat" "fish")
                             #:wct wct))))))


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
    (command-line
     #:program me
     #:once-each
     (("-q" "--quiet") "run more quietly"
                       (warranted-quiet? #t))
     (("-n" "--pretend") "don't actually run commands"
                         (warranted-pretend? #t))
     (("-d" "--debug") "debug output"
                       (warranted-debug? #t))
     (("-D" "--development") "development mode"
                             (warranted-development? #t))
     #:handlers
     (lambda (_ . args)
       (if (> (length args) 0)
           (run args)
           (die usage)))
     '("command" "arg")
     (lambda (help-message)
       ;; help: this is a normal exit
       (complain "~A" help-message)
       (exit 0))
     (lambda switches
       ;; unknown switch or switches: this is death
       (case (length switches)
         [(1)
          (die "unknown switch ~A (try -h)" (first switches))]
         [(0)
          (die "mutant switch death")]
         [else
          (die "unknown switches ~A (try -h)" switches)])))))
