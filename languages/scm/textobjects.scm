;; Vim text objects. A "function" here is any definition form, which is what
;; `[[` / `]]` and `daf` should step over in a Scheme file.
(list
  .
  (symbol) @_head
  (#any-of? @_head
   "define" "define-values" "define-syntax" "define-record-type"
   "define-library" "lambda" "case-lambda")) @function.around

(list
  .
  (symbol) @_head
  (#any-of? @_head "define" "lambda")
  .
  (_)
  .
  (_) @_start (_)? @_end) @function.inside

[(comment) (block_comment) (sexp_comment)] @comment.around
