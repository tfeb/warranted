#lang racket

;;;; Warranted command trees & their representation in files
;;;

(require "low.rkt")

(provide (contract-out
          (slist-matches-wct?
           (-> valid-slist? valid-wct? boolean?))
          (warranted-commands-files
           (->* () ((listof (and/c path? absolute-path?)))
                (listof (and/c path? absolute-path?))))
          (read-wct
           (->* () ((listof (and/c path? absolute-path?))) valid-wct?)))
         (struct-out exn:fail:bad-wct-spec))

(module+ test
  (require rackunit))

(define (valid-wct? thing)
  ;; A tree is a list of nodes, possibly a null list
  (and (list? thing)
       (for/and ([node thing])
         (valid-wct-node? node))))

(define (valid-wct-node-name? name)
  ;; node names are strings or the two wildcard symbols
  (or (string? name)
      (eqv? name '*)
      (eqv? name '**)))

(define (valid-wct-node? node)
  ;; a node is either null, which matches
  (or (null? node)
      ;;  or a cons of (string . tree)
      (and (cons? node)
           (valid-wct-node-name? (car node))
           (valid-wct? (cdr node)))))

(module+ test
  (for ([n (in-list '("foo" "" * **))])
    (check-true (valid-wct-node-name? n)))
  (check-false (valid-wct-node-name? 'x))

  (check-true (valid-wct-node? '("x")))
  (check-false (valid-wct-node? '("x" "y")))
  (check-true (valid-wct-node? '(*)))

  (check-true (valid-wct? '(("foo"))))
  (check-true (valid-wct? '()))
  (check-false (valid-wct? '("foo" "bar")))

  (let ([node '("cat" ("foo") ("bar") ("fish" ("x") ("y")))])
    (check-true (valid-wct-node? node))
    (check-true (valid-wct? (list node)))))

(define (valid-file-entry? entry)
  ;; a file entry ie either a list of valid node names or a WCT node
  (or (and (list? entry)
           (andmap valid-wct-node-name? entry))
      (valid-wct-node? entry)))

(define (valid-file-entries? entries)
  ;; the entries in a file must be a list of valid file entries
  (and (list? entries)
       (andmap valid-file-entry? entries)))

(define (file-entry->wct-node entry)
  ;; entry is known to be a valid file entry: turn it into a valid WCT node
  (if (valid-wct-node? entry)
      entry
      (let convert ([tail entry])
        (if (null? tail)
            '()
            (cons (first tail) (list (convert (rest tail))))))))

(define (file-entries->wct entries)
  ;; turn a list of file entries into a WCT
  (map file-entry->wct-node entries))

(module+ test
  (check-true (valid-file-entry? '("cat" "/etc/motd")))
  (check-true (valid-file-entry? '("cat" *)))
  (check-true (valid-file-entry? '("cat" * **)))
  (check-true (valid-file-entries? '(("echo" "hi")
                                     ("echo")
                                     ("cp" "foo" "bar"))))
  ;; See below for checks that these are equivalent to the simpler translations
  (check-equal? (file-entry->wct-node '("cat" "foo"))
                '("cat" ("foo" ())))
  (check-equal? (file-entries->wct '(("echo" "hi")
                                    ("cp" "foo" "bar")))
               '(("echo" ("hi" ()))
                 ("cp" ("foo" ("bar" ()))))))

(define (valid-slist? thing)
  ;; a valid string list
  (and (list? thing)
       (andmap string? thing)))

(module+ test
  (for ([s (in-list '(("foo" "bar")
                      ("foo")))])
    (check-true (valid-slist? s)))
  (for ([s (in-list '(a ("b" . "c")
                        (* "1")))])
    (check-false (valid-slist? s))))

;;; Some abstraction so the matcher can think in terms of trees.
;;; Note that the children of a node are explicitly a list of nodes still,
;;; and a WCT is a list of nodes.
;;;
(define wct-node-null? null?)
(define wct-node-key car)
(define wct-node-children cdr)

(define (slist-matches-wct? slist wct)
  ;; does an slist match a WCT?
  (debug "match ~S to ~S~%" slist wct)
  (if (null? slist)
      ;; the empty list matches if ...
      (or (null? wct) ; ... the tree is empty ...
          (ormap (λ (node)
                   (or (wct-node-null? node) ; ... a node is null ...
                       ;; ... or it has a wild-inferiors key and has no children
                       (and (eqv? (wct-node-key node) '**)
                            (null? (wct-node-children node)))))
                 wct))
      ;; slist is not empty, it matches if one of the children matches
      (match-let ([(cons slfirst slrest) slist])
        (for/or ([node wct])
          (and (not (wct-node-null? node)) ; null children don't match
               (let ([key (wct-node-key node)])
                 (case key
                   [(*)
                    ;; the wildcard key matches if the rest of the slist
                    ;; matches the children of the node
                    (slist-matches-wct? slrest (wct-node-children node))]
                   [(**)
                    ;; wild-inferiors key matches if either the rest of the
                    ;; slist matches a WCT fabricated from this node,
                    ;; or if it matches the children of this node
                    (or (slist-matches-wct? slrest (list node))
                        (slist-matches-wct? slrest (wct-node-children node)))]
                   [else
                    ;; otherwise the key is stringy and it matches if the
                    ;; strings match & the rest of the slist matches the
                    ;; children of this node
                    (and (string=? slfirst key)
                         (slist-matches-wct? slrest
                                             (wct-node-children node)))])))))))

(module+ test
  ;; non-wildcard WCT tests
  (let ([wct/small '(("cat" ("foo")))]
        [wct/bigger '(("cat" ("foo" ())
                             ("bar")))]
        [cf '("cat" "foo")]
        [cb '("cat" "bar")]
        [cff '("cat" "foo" "foo")])
    (check-true (slist-matches-wct? cf wct/small))
    (check-true (slist-matches-wct? cf wct/bigger))
    (check-false (slist-matches-wct? cb wct/small))
    (check-true (slist-matches-wct? cb wct/bigger))
    (check-false (slist-matches-wct? cff wct/small))
    (check-false (slist-matches-wct? cff wct/bigger)))

  ;; wildcarded WCTs: there are not enough tests here
  (let ([wct '(("cat" (** ("x"))
                      ("fish" ("y"))
                      ("bone")
                      (* ("z"))))])
    (check-true (slist-matches-wct? '("cat" "bone") wct))
    (check-true (slist-matches-wct? '("cat" "fish" "y") wct))
    (check-true (slist-matches-wct? '("cat" "fish" "x") wct))
    (check-true (slist-matches-wct? '("cat" "fish" "bone" "x") wct))
    (check-true (slist-matches-wct? '("cat" "fish" "z") wct))
    (check-false (slist-matches-wct? '("cat" "fish" "bone" "z") wct))))


;;;; Reading WCTs from files
;;;

(struct exn:fail:bad-wct-spec exn:fail (spec source)
  #:extra-constructor-name make-exn:fail:bad-wct-spec
  #:transparent)

(define warranted-commands-files
  (make-parameter
   (let* ([home (find-system-path 'home-dir)]
          [root (first (explode-path home))]
          [wcf "warranted.rktd"])
     (list
      (build-path root "etc" wcf)
      (build-path root "usr" "local" "etc" wcf)
      (build-path home "etc" wcf)))))

(define (read-wct (files (warranted-commands-files)))
  (for/fold ([wct '()]) ([file files])
    (append wct (if (file-exists? file)
                    (let ([spec (call-with-default-reading-parameterization
                                 (thunk (call-with-input-file file read)))])
                      (unless (valid-file-entries? spec)
                        (raise (make-exn:fail:bad-wct-spec
                                "bad WCT spec"
                                (current-continuation-marks)
                                spec file)))
                      (file-entries->wct spec))
                    '()))))
