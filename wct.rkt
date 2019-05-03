#lang racket

;;;; Warranted command trees & their representation in files
;;;
;;; A warranted command tree (WCT) is a list of nodes.
;;; A node is either the empty list, or it is a cons of a name and a WCT.
;;; A node's name (key) is either a string, the symbol * or the symbol **.
;;; * matches one component, ** matches zero or more components.
;;;
;;; A list of strings (from a command line), known as an slist in this code
;;;  is matched against a WCT.
;;; If the list is null then it matches the empty WCT, a WCT with an empty
;;;  child node, or a WCT with a child node whose name is ** and whose WCT is
;;;  null (the last case makes sure that this is really the end of the WCT).
;;; If the list is not null it matches if its first element matches and the
;;;  remaining elements match the WCT which is the child of the matched node.
;;; An element matches a node if the node's name is *, if the node's name is a
;;;  string which is equal to the element, or if the node's name is ** and
;;;  the rest of the slist matches either a WCT whose only node is the node
;;;  that matched, or if it matches the WCT of the node.
;;;
;;; WCTs are read from files in two forms: as WCTs or as command specifications
;;;  which are turned into WCTs.
;;; A command specification is just a list containing a command and its
;;;  arguments, where any entry can also be * or **.
;;; Each file has a single form which can contain as many specifications or WCTs
;;;  as you like.  There's no fancy merging of the tops of trees.
;;;
;;; The default set of config files is "/etc/warranted.rktd",
;;;  "/usr/local/etc/warranted.rktd" and "~/etc/warranted.rktd": all of these
;;;  are checked and if they exist read into a single WCT.
;;;
;;; Commands, but not their arguments, are matched against the absolute path of
;;;  the executable: so 'cat foo' would turn into '/bin/cat foo' for instance.
;;;


(require "low.rkt")

(provide (contract-out
          (slist-matches-wct?
           (-> valid-slist? valid-wct? boolean?))
          (warranted-commands-files
           (case->
            (-> (-> (listof (and/c path-string? absolute-path?))))
            (-> (-> (listof (and/c path-string? absolute-path?)))
                void?)))
          (default-warranted-commands-files
            (-> (listof (and/c path-string? absolute-path?))))
          (read-wct
           (->* () ((listof (and/c path-string? absolute-path?))) valid-wct?)))
         (struct-out exn:fail:bad-wct-spec)
         (struct-out exn:fail:bad-metafile))

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

(struct exn:fail:bad-metafile exn:fail (wcfs source)
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
         [wcf "warranted.rktd"]
         [metaf "warranted-meta.rktd"])
    (define (locations file)
      (list (build-path root "etc" file)
            (build-path root "usr" "local" "etc" file)
            (build-path home "etc" file)))
    (let search ([metafiles (locations metaf)])
      (if (null? metafiles)
          (locations wcf)
          (match-let ([(cons metafile more-metas) metafiles])
            (let ([wcfs (and (file-exists? metafile)
                             (call-with-default-reading-parameterization
                              (thunk (call-with-input-file metafile read))))])
              (cond [wcfs
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

(define (read-wct (files ((warranted-commands-files))))
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
