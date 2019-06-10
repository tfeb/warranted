#lang racket

;;;; FSMs for matching command patterns
;;;

;;; An FSM is one or more states connected by arcs, where an arc is an
;;; object with a label and a target state (arcs are implemented as
;;; conses).  A state may have any number of outgoing arcs, and may
;;; also be labelled as final.  The target of an arc may be the same
;;; state in a special case (see below).

;;;
;;; FSMs are created from patterns.  A pattern is a list of zero or
;;; more elements, each of which may be:
;;; - a string, which matches itself;
;;; - the symbol * which matches any one element;
;;; - the symbol ** which matches zero or more elements (this is done
;;;   by looping back to the same node in the FSM);
;;; - the symbol / which matches zero elements;
;;; - a list which is a disjunction and matches any of its members.
;;; Each element of a disjunction is either a string, * or **, or a
;;; pattern, which matches recursively.
;;;
;;; Example patterns:
;;; - ("ls" "-l") matches ls -l (in fact it doesn't as the first
;;;   element needs to be an absolute pathname);
;;; - ("ls" "-l" *) matches ls -l followed by any single argument;
;;; - ("ls" ("-l" "-d") *) matches ls -l or ls -d followed by any
;;;   single argument;
;;; - ("ls" **) matches ls followed by any number of arguments
;;;   including zero;
;;; - ("ls" (("-l" *) "-l")) matches ls -l followed by any single
;;;   argument, or ls -l;
;;; - ("ls" (/ "-l") *) matches ls, optionally -l then any single argument.
;;;

(require "low.rkt"
         srfi/17)

(provide (contract-out
          (slist-matches?
           (-> state? valid-slist? boolean?))
          (valid-slist?
           (-> any/c boolean?))
          (valid-pattern?
           (-> any/c boolean?))
          (valid-patterns?
           (-> any/c boolean?))
          (fsm?
           (-> any/c boolean?))
          (patterns->fsm
           (-> valid-patterns? fsm?))))

(module+ test
  (require rackunit))

;;; States
;;;

(struct state
  ;; An FSM state: it has some arcs and may or may not be final
  ((arcs #:mutable)
   (final #:mutable))
  #:constructor-name boa-make-state)

(define (make-state #:arcs (arcs '())
                    #:final (final #f))
  (boa-make-state arcs final))

(set! (setter state-arcs) set-state-arcs!)
(set! (setter state-final) set-state-final!)

(define state-final? state-final)

(define fsm?
  ;; fsm? is the thing we provide: an fsm is a state
  state?)

;;; Abstraction for arcs
;;;

(define (make-arc key (next (make-state)))
  (cons key next))

(define-values (arc-key arc-next) (values car cdr))

(define (get-next-state s key (missing #f))
  ;; get the next state from s matching (with equal? -- this is not
  ;; pattern matching yet) key.  If no state is found then, if missing
  ;; is a procedure, call it with s & key, otherwise return it.
  (let ([found (findf (λ (arc)
                        (equal? (arc-key arc) key))
                      (state-arcs s))])
    (cond [found
           (arc-next found)]
          [(procedure? missing)
           (missing s key)]
          [else missing])))

(module+ test
  (let ([s (make-state)])
    (check-false (get-next-state s "foo"))
    (check-eqv? (get-next-state s "foo" 32) 32)
    (check-eqv? (get-next-state s "foo" (λ (s k) 96)) 96)))

(define (ensure-next-state s key (target #f))
  (get-next-state s key
                 (λ (ss kk)
                   (let ([new (make-arc kk (or target (make-state)))])
                     (set! (state-arcs ss) (cons new (state-arcs ss)))
                     (arc-next new)))))

(module+ test
  (check-pred state? (ensure-next-state (make-state) "foo"))
  (let ([target (make-state)])
    (check-eq? (ensure-next-state (make-state) "foo" target) target))
  (let ([s (make-state)])
    (ensure-next-state s "foo")
    (ensure-next-state s "bar")
    (check-pred state? (get-next-state s "foo"))
    (check-pred state? (get-next-state s "bar"))
    (check-not-eq? (get-next-state s "foo") (get-next-state s "bar"))
    (check-false (get-next-state s "ben"))))

(define (valid-pattern? candidate)
  ;; Is a candidate a valid pattern?
  (define (valid-element? elt)
    ;; valid atomic elements
    (or (string? elt) (memv elt '(* ** /))))
  (and (list? candidate)
       (if (null? candidate)
           ;; the empty list is valid
           #t
           (match-let ([(cons head tail) candidate])
             (cond [(valid-element? head)
                    ;; a pattern with a valid atomic head is valid if
                    ;; its tail is valid
                    (valid-pattern? tail)]
                   [(list? head)
                    ;; disjunction head
                    (and (for/and ([disjunct head])
                           ;; each disjunct must be a valid element or
                           ;; a valid pattern ...
                           (or (valid-element? disjunct)
                               (valid-pattern? disjunct)))
                         ;; ... and the fail must be valid
                         (valid-pattern? tail))]
                   [else #f])))))

(module+ test
  (for ([pattern (in-list '(("ls")
                            ("ls" "-l")
                            ("ls" *)
                            ("ls" "-l" *)
                            ("ls" "-l" **)
                            ("ls" (/ "-l") *)
                            ("ls" ("-l" "-t") *)))])
    (check-true (valid-pattern? pattern)))
  (for ([bad (in-list '(1 (1) (x) ("ls" . "-l") *))])
    (check-false (valid-pattern? bad))))

(define (valid-patterns? candidates)
  ;; are all the patterns (from a file) valid)
  (and (list? candidates)
       (andmap valid-pattern? candidates)))

(define (intern-pattern s pattern)
  ;; Intern a pattern into a state
  (if (null? pattern)
      ;; this must be an accepting state
      (set! (state-final s) #t)
      (match-let ([(cons this tail) pattern])
        (if (list? this)
            ;; disjunction
            (for ([disjunct (in-list this)])
              ;; the way to deal with disjunctions is simply to intern
              ;; patterns constructed from them and the existing tail:
              ;; if the disjunction is a recursive pattern just do this
              ;; by appending.
              (intern-pattern s (if (list? disjunct)
                                    (append disjunct tail)
                                    (cons disjunct tail))))
              (case this
                ((**)
                 ;; loopback case
                 (intern-pattern (ensure-next-state s this s) tail))
                (else
                 ;; normal case: note * is normal here.
                 (intern-pattern (ensure-next-state s this) tail)))))))

(define (patterns->fsm patterns)
  ;; intern a bunch of patterns into a new FSM
  (let ([s (make-state)])
    (for ([pattern (in-list patterns)])
      (intern-pattern s pattern))
    s))

(define (valid-slist? thing)
  ;; a valid string list
  (and (list? thing)
       (andmap string? thing)))

(define (slist-matches? s slist)
  ;; does an slist match a pattern?
  (debug "matching ~S~%" slist)
  (if (null? slist)
      (state-final? s)
      (match-let ([(cons this tail) slist])
        (or (let ([next (get-next-state s this)])
              (and next (slist-matches? next tail)))
            (let ([skip-next (get-next-state s '/)])
              (and skip-next (slist-matches? skip-next (cons this tail))))
            (let ([wild-next (get-next-state s '*)])
              (and wild-next (slist-matches? wild-next tail)))
            (let ([wild-loop (get-next-state s '**)])
              (and wild-loop (slist-matches? wild-loop tail)))))))

(module+ test
  (let ([fsm (patterns->fsm '(("ls")
                             ("ls" ("-l" "-t") *)))])
    (check-true (slist-matches? fsm '("ls")))
    (check-true (slist-matches? fsm '("ls" "-t" "x")))
    (check-false (slist-matches? fsm '("ls" "-l")))
    (check-false (slist-matches? fsm '("ls" "-l" "x" "y"))))
  (let ([fsm (patterns->fsm '(("ls" (/ "-l") *)))])
    (check-true (slist-matches? fsm '("ls" "-l" "a")))
    (check-true (slist-matches? fsm '("ls" "a")))
    (check-false (slist-matches? fsm '("ls" "-r" "a")))
    (check-false (slist-matches? fsm '("ls")))))
