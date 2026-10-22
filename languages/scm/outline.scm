;; The outline: what a file defines. `(define (f a) …)` lists as `f` rather
;; than as `(f a)`, so procedures and variables read the same way in the
;; outline view.
(list
  .
  (symbol) @context
  (#any-of? @context
   "define" "define-values" "define-syntax" "define-record-type"
   "define-library")
  .
  [(symbol) @name
   (list . (symbol) @name)]) @item

;; A docstring annotates the procedure it opens: a leading string in a body
;; is scm's docstring convention (docs/repl.md, "Introspection is values").
(list
  .
  (symbol) @_head
  (#eq? @_head "define")
  .
  (list)
  .
  (string) @annotation)
