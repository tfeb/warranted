#lang racket

;;;; FSMs for matching command patterns
;;;

;;; An FSM is one or more states connected by arcs, where an arc is an
;;; object with a label and a target state (arcs are implemented as
;;; conses).  A state may have any number of outgoing arcs, and may
;;; also be labelled as final.  The target of an arc may be the same
;;; state in a special case (see below).

;;;
;;; FSMs are created from patterns.  A pattern is either a list of the form
;;; (and . elements) or a list of zero or more elements.  Each element is
;;; one of:
;;; - a string, which matches itself;
;;; - a regexp, which must match the whole of an element;
;;; - the symbol * which matches any one element;
;;; - the symbol ** which matches zero or more elements (this is done
;;;   by looping back to the same node in the FSM);
;;; - the symbol / which matches zero elements;
;;; - a list which is a disjunction, which is either a list of the form
;;;   (or . disjuncts) or a list of disjuntss, which matchec any of the
;;;   disjuncts.  Each disjunct is either a string, a regexp, /, *, **
;;;   or a pattern, which matches recursively.
;;;
;;; Example patterns:
;;; - ("ls" "-l") matches ls -l (in fact it doesn't as the first
;;;   element needs to be an absolute pathname);
;;; - (and "ls" "-l") is an equivalent pattern;
;;; - ("ls: #rx"-[lh]") matches ls -l or ls -h;
;;; - ("ls" "-l" *) matches ls -l followed by any single argument;
;;; - ("ls" ("-l" "-d") *) matches ls -l or ls -d followed by any
;;;   single argument;
;;; - ("ls" #rx"-[ld]" *) is a regexpy way of saying the same thing;
;;; - ("ls" **) matches ls followed by any number of arguments
;;;   including zero;
;;; - ("ls" (("-l" *) "-l")) matches ls -l followed by any single
;;;   argument, or ls -l;
;;; - (and "ls" (or (and "-l" *) "-l")) is an equivalent pattern;
;;; - ("ls" (/ "-l") *) matches ls, optionally -l then any single argument.
;;;
;;; The (and ...) and (or ...) versions are equivalent but are meant to be
;;; clearer, I hope.
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

(define (arc-match? arc thing)
  (let ([key (arc-key arc)])
    (if (regexp? key)
        (if (string? thing)
            (regexp-match-exact? key thing)
            #f)
        (equal? key thing))))

(define-values (arc-key arc-next) (values car cdr))

(define (get-next-state s key (missing #f))
  ;; get the next state from s matching (with equal? -- this is not
  ;; pattern matching yet) key.  If no state is found then, if missing
  ;; is a procedure, call it with s & key, otherwise return it.
  (let ([found (findf (λ (arc)
                        (arc-match? arc key))
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

(define (maybe-flatten-elements key elements)
  ;; flatten the elements of a named (and, or) list of things
  (let floop ([elts elements]
              [agenda '()]
              [results '()])
    (match elts
      ['()
       (if (null? agenda)
           (reverse results)
           (floop (first agenda)
                  (rest agenda)
                  results))]
      [(list* this more)
       (match this
         [(list* maybe-key subelements)
          (if (eqv? maybe-key key)
              (floop subelements
                     (cons more agenda)
                     results)
              (floop more agenda (cons this results)))]
         [_
          (floop more agenda (cons this results))])])))

(define (pattern-elements pattern)
  ;; The elements of a pattern: this is where it is known that
  ;; patterns can be lists of the form (and ...).
  (match pattern
    [(list* 'and elements)
     (maybe-flatten-elements 'and elements)]
    [(list elements ...)
     elements]
    [anything anything]))

(define (disjunction-elements disjunction)
  ;; The elements of a disjunction: this is where it is known that
  ;; disjunctions can be of the form (or ...).
  (match disjunction
    [(list* 'or elements)
     (maybe-flatten-elements 'or elements)]
    [(list elements ...)
     elements]
    [anything anything]))

(module+ test
  (check-equal? (disjunction-elements
                 '(or "a" "b" (or "c") (and "d") (or "e")))
                '("a" "b" "c" (and "d") "e"))
  (check-equal? (pattern-elements
                 '(and "a" "b" (or "c") (and "d" (and "e")) "f"))
                '("a" "b" (or "c") "d" "e" "f")))

(define (valid-pattern? pattern-candidate)
  ;; Is a pattern-candidate a valid pattern?
  (define (valid-element? elt)
    ;; valid atomic elements
    (or (string? elt) (regexp? elt) (memv elt '(* ** /))))
  (let valid-pattern-tail? ([candidate (pattern-elements pattern-candidate)])
    (and (list? candidate)
         (if (null? candidate)
             ;; the empty list is valid
             #t
             (match-let ([(cons head tail) candidate])
               (cond [(valid-element? head)
                      ;; a pattern with a valid atomic head is valid
                      ;; if its tail is valid
                      (valid-pattern-tail? tail)]
                     [(list? head)
                      ;; disjunction head
                      (and (for/and ([disjunct (disjunction-elements head)])
                             ;; each disjunct must be a valid element
                             ;; or a valid pattern ...
                             (or (valid-element? disjunct)
                                 (valid-pattern? disjunct)))
                           ;; ... and the fail must be valid
                           (valid-pattern-tail? tail))]
                     [else #f]))))))

(module+ test
  (for ([pattern (in-list '(("ls")
                            ("ls" "-l")
                            ("ls" *)
                            ("ls" "-l" *)
                            ("ls" "-l" **)
                            ("ls" (/ "-l") *)
                            ("ls" ("-l" "-t") *)
                            ("ls" (or "-l" "-t") *)
                            ("ls" (or / "-l") *)
                            (and "ls" (or / "-l") *)
                            (and "ls" (or "-l" (and "-l" "-r")))
                            (and "ls" (or / "-l") "x")
                            (and "ls" (and "-l" (and *)))
                            (and "ls" (or (and "-l" *)
                                          (or "-l" "-r")))))])
    (check-true (valid-pattern? pattern)))
  (for ([bad (in-list '(1 (1) (x) ("ls" . "-l") *
                          (and and)
                          (and "ls" or)))])
    (check-false (valid-pattern? bad))))

(define (valid-patterns? candidates)
  ;; are all the patterns (from a file) valid)
  (and (list? candidates)
       (andmap valid-pattern? candidates)))

(define (intern-pattern s pattern)
  ;; Intern a pattern into a state
  (let ([elements (pattern-elements pattern)])
    (if (null? elements)
        ;; this must be an accepting state
        (set! (state-final s) #t)
        (match-let ([(cons this tail) elements])
          (if (list? this)
              ;; disjunction
              (for ([disjunct (in-list (disjunction-elements this))])
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
                 (intern-pattern (ensure-next-state s this) tail))))))))

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
  (define-syntax-rule (with-fsm (fsm patterns) form ...)
    (let ([fsm (patterns->fsm patterns)])
      form ...))
  (define (check-match fsm . slists)
    (for ([slist (in-list slists)])
      (check-true (slist-matches? fsm slist))))
  (define (check-nomatch fsm . slists)
    (for ([slist (in-list slists)])
      (check-false (slist-matches? fsm slist))))

  (test-case
   "Basic FSM matching"
   (with-fsm (fsm '(("ls")
                    ("ls" ("-l" "-t") *)))
     (check-match fsm
                  '("ls")
                  '("ls" "-t" "x"))
     (check-nomatch fsm
                    '("ls" "-l")
                    '("ls" "-l" "x" "y")))
   (with-fsm (fsm '(("ls" (/ "-l") *)))
     (check-match fsm
                  '("ls" "-l" "a")
                  '("ls" "a"))
     (check-nomatch fsm
                    '("ls" "-r" "a")
                    '("ls"))))

  (test-case
   "Decorated FSMs"
   (with-fsm (fsm '(("ls" (or "-l" "-t") *)))
     (check-match fsm
                  '("ls" "-l" "x")
                  '("ls" "-t" "y"))
     (check-nomatch fsm
                    '("ls")
                    '("ls" "-d" "x")
                    '("ls" "-l")))
   (with-fsm (fsm '((and "ls" "-l")
                    (and "ls" (or "-t" "-d") *)))
     (check-match fsm
                  '("ls" "-l")
                  '("ls" "-t" "x"))
     (check-nomatch fsm
                    '("ls" "-t"))))

  (test-case
   "Regexp FSM matching"
   (with-fsm (fsm '(("ls")
                    ("ls" #rx"-[lh]")))
     (check-match fsm
                  '("ls")
                  '("ls" "-l"))
     (check-nomatch fsm
                    '("ls" "-")
                    '("ls" "-lh")
                    '("ls" "-ll")))
   (with-fsm (fsm '(("ls" #rx"(a|b)")))
     (check-match fsm
                  '("ls" "a")
                  '("ls" "b"))
     (check-nomatch fsm
                    '("ls" "ab")
                    '("ls" "c"))))

  (test-case
   "Examples from the documentation"
   (with-fsm (fsm '(("/bin/ls")))
     (check-match fsm '("/bin/ls"))
     (check-nomatch fsm '("/bin/ls" "x") '("/bin/cat")))
   (with-fsm (fsm '(("/bin/ls" "/etc/motd")))
     (check-match fsm '("/bin/ls" "/etc/motd"))
     (check-nomatch fsm '("/bin/ls" "/dev/null") '("/bin/cat")))
   (with-fsm (fsm '(("/bin/ls" *)))
     (check-match fsm
                  '("/bin/ls" "/etc/motd")
                  '("/bin/ls" "/dev/null")
                  '("/bin/ls" "-l"))
     (check-nomatch fsm
                    '("/bin/ls" "-l" "/etc/motd")))
   (with-fsm (fsm '(("/bin/ls" "-l" *)))
     (check-match fsm
                  '("/bin/ls" "-l" "x")
                  '("/bin/ls" "-l" "-r"))
     (check-nomatch fsm
                    '("/bin/ls")
                    '("/bin/ls" "-r" "-l")
                    '("/bin/ls" "-l" "x" "y")))
   (with-fsm (fsm '(("/bin/ls" #rx"-[ld]" *)))
     (check-match fsm
                  '("/bin/ls" "-l" "x")
                  '("/bin/ls" "-l" "-d")
                  '("/bin/ls" "-d" "x"))
     (check-nomatch fsm
                    '("/bin/ls")
                    '("/bin/ls" "-r" "-l")
                    '("/bin/ls" "-l" "x" "y")))
   (with-fsm (fsm '(("/bin/ls" **)))
     (check-match fsm
                  '("/bin/ls" "x" "y" "z")
                  '("/bin/ls"))
     (check-nomatch fsm '("/bin/cat")))
   (with-fsm (fsm '(("/bin/ls" ** "/etc/motd")))
     (check-match fsm
                  '("/bin/ls" "/etc/motd")
                  '("/bin/ls" "x" "y" "/etc/motd"))
     (check-nomatch fsm
                    '("/bin/ls")
                    '("/bin/ls" "x" "y")))
   (with-fsm (fsm '(("/bin/ls" ("/etc/motd" "/etc/hostname"))))
     (check-match fsm
                  '("/bin/ls" "/etc/motd")
                  '("/bin/ls" "/etc/hostname"))
     (check-nomatch fsm
                    '("/bin/ls")
                    '("/bin/ls" "/etc/rc.local")))
   (with-fsm (fsm '(("/bin/ls" (/ "-l") "/etc/motd")))
     (check-match fsm
                  '("/bin/ls" "/etc/motd")
                  '("/bin/ls" "-l" "/etc/motd"))
     (check-nomatch fsm
                    '("/bin/ls" "-r" "/etc/motd")
                    '("/bin/ls" "-l" "-r" "/etc/motd")))
   (with-fsm (fsm '(("/bin/ls" (/ ("-l" "-r")) "/etc/motd")))
     (check-match fsm
                  '("/bin/ls" "/etc/motd")
                  '("/bin/ls" "-l" "-r" "/etc/motd"))
     (check-nomatch fsm
                    '("/bin/ls" "-l" "/etc/motd")
                    '("/bin/ls" "-l" "-r")))
   (with-fsm (fsm '(("/bin/ls" (/ #rx"-[lr]") "/etc/motd")))
     (check-match fsm
                  '("/bin/ls" "/etc/motd")
                  '("/bin/ls" "-l" "/etc/motd")
                  '("/bin/ls" "-r" "/etc/motd"))
     (check-nomatch fsm
                    '("/bin/ls" "-lr" "/etc/motd")
                    '("/bin/ls" "-l" "x")))
   (with-fsm (fsm '(("/bin/ls" (/ (("-l" "-r"))) "/etc/motd")))
     (check-match fsm
                  '("/bin/ls" "/etc/motd")
                  '("/bin/ls" "-l" "/etc/motd")
                  '("/bin/ls" "-r" "/etc/motd"))
     (check-nomatch fsm
                    '("/bin/ls" "-lr" "/etc/motd")
                    '("/bin/ls" "-l" "x")))
   (with-fsm (fsm '(("/bin/ls" (or / ((or "-l" "-r"))) "/etc/motd")))
     (check-match fsm
                  '("/bin/ls" "/etc/motd")
                  '("/bin/ls" "-l" "/etc/motd")
                  '("/bin/ls" "-r" "/etc/motd"))
     (check-nomatch fsm
                    '("/bin/ls" "-lr" "/etc/motd")
                    '("/bin/ls" "-l" "x")))))
