#lang racket

;;;; Low-level for warranted
;;;

(provide (contract-out
          (complain
           (->* (string?) #:rest any/c any))
          (mutter
           (->* (string?) #:rest any/c any))
          (warranted-quiet?
           (->* () (any/c) any))
          (debug
           (->* (string?) #:rest any/c any))
          (warranted-debug?
           (->* () (any/c) any))))

;;; Verbosity control & complaining
;;;
(define warranted-quiet?
  (make-parameter (if (getenv "WARRANTED_QUIET") #t #f)))

(define (talk fmt args)
  (apply fprintf (current-error-port) fmt args))

(define (mutter fmt . args)
  (unless (warranted-quiet?)
    (talk fmt args))
  (void))

(define (complain fmt . args)
  (talk fmt args)
  (void))

(define warranted-debug?
  (make-parameter (if (getenv "WARRANTED_DEBUG") #t #f)))

(define (debug fmt . args)
  (when (warranted-debug?)
    (talk fmt args))
  (void))
