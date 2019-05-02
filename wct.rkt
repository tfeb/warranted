#lang racket

;;;; Warranted command trees & their representation in files
;;;

(provide (contract-out
          (slist-matches-wct?
           (-> valid-slist? valid-wct? boolean?))
          (warranted-commands-files
           (->* () ((listof (and/c path? absolute-path?)))
                (listof (and/c path? absolute-path?))))
          (read-wct
           (->* () ((listof (and/c path? absolute-path?))) valid-wct?)))
         (struct-out exn:fail:bad-wct-spec))

(define (valid-wct? thing)
  ;; A tree is a list of nodes, possibly a null list
  (and (list? thing)
       (for/and ([node thing])
         (valid-wct-node? node))))

(define (valid-wct-node? node)
  ;; a node is either null, which matches
  (or (null? node)
      ;;  or a cons of (string . tree)
      (and (cons? node)
           (string? (car node))
           (valid-wct? (cdr node)))))

(define (valid-file-entry? entry)
  ;; a fle entry ie either a list of strings or a WCT node
  (or (and (list? entry)
           (andmap string? entry))
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

(define (valid-slist? thing)
  ;; a valid string list
  (and (list? thing)
       (andmap string? thing)))

(define wct-node-null? null?)
(define wct-node-key car)
(define wct-node-children cdr)
(define append-wcts append)
(define null-wct '())

(define (slist-matches-wct? slist wct)
  (if (null? slist)
      (or (null? wct)
          (ormap wct-node-null? wct))
      (match-let ([(cons slfirst slrest) slist])
        (for/or ([node (in-list wct)])
          (and (not (wct-node-null? node))
               (string=? slfirst (wct-node-key node))
               (slist-matches-wct? slrest (wct-node-children node)))))))


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
  (define (read-one-wct file)
    (if (file-exists? file)
        (let ([spec (call-with-default-reading-parameterization
                     (thunk (call-with-input-file file read)))])
          (unless (valid-file-entries? spec)
            (raise (make-exn:fail:bad-wct-spec
                    "bad WCT spec"
                    (current-continuation-marks)
                    spec file)))
          (file-entries->wct spec))
        null-wct))
  (apply append-wcts (map read-one-wct files)))
