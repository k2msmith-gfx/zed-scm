; scm's own spellings
(define v [1 2 3])
(define (f a &opt (b 2) &named (c 3) &keys rest)
  "A docstring."
  (vector-ref [10 20] a))
(set-marker :tex-scale 2.0 :-x 1 :a* 2 :k? #t :at>b 3)
(let-values (((q r) (floor/ 7 2))) (list q r))
(define-record-type point (make-point x y) point? (x point-x))
(define-syntax swap! (syntax-rules () ((_ a b) (let ((t a)) (set! a b) (set! b t)))))
#| block
   comment |#
#;(ignored datum)
(display #\newline) (display "esc \" \\ done") (display #u8(1 2 3))
(define big 1/3) (define c 1.5e-8) (define z #xdeadbeef)
'(a . b) `(x ,y ,@ys)
(define-syntax my-when (syntax-rules () ((_ c b ...) (if c (begin b ...) #f))))
(cond [(= 1 2) 'no] [else 'yes])
(define-library (my lib) (export f) (import (scheme base)) (begin (define (f) 1)))
