#lang racket

;;;; Low-level for warranted
;;;

(provide (contract-out
          (mutter
           (->* (string?) #:rest any/c any))
          (complain
           (->* (string?) #:rest any/c any))
          (warranted-quiet?
           (->* () (boolean?) boolean?))))

;;; Verbosity control & complaining
;;;
(define warranted-quiet?
  (make-parameter (if (getenv "WARRANTED_QUIET") #t #f)))

(define (mutter fmt . args)
  (unless (warranted-quiet?)
    (apply fprintf (current-error-port) fmt args))
  (void))

(define (complain fmt . args)
  (apply fprintf (current-error-port) fmt args)
  (void))
