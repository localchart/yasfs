#lang racket
(define atom?
  (lambda (v)
    (not (pair? v))))
(define static-wrong 'wait)

(define r.init '())
(define (r-extend* r n*)
  (cons n* r) )

(define (local-variable? r i n)
  (and (pair? r)
       (let scan ((names (car r))
                  (j 0) )
         (cond ((pair? names) 
                (if (eq? n (car names))
                    `(local ,i . ,j)
                    (scan (cdr names) (+ 1 j)) ) )
               ((null? names)
                (local-variable? (cdr r) (+ i 1) n) )
               ((eq? n names) `(local ,i . ,j)) ) ) ) )

(define (global-variable? g n)
  (let ((var (assq n g)))
    (and (pair? var)
         (cdr var) ) ) )

(define sg.current (make-vector 100))

(define (g.current-extend! n)
  (let ((level (length g.current)))
    (set! g.current 
          (cons (cons n `(global . ,level)) g.current) )
    level ) )

(define (global-fetch i)
  (vector-ref sg.current i) )

(define (global-update! i v)
  (vector-set! sg.current i v) )

(define (g.current-initialize! name)
  (let ((kind (compute-kind r.init name)))
    (if kind
        (case (car kind)
          ((global)
           (vector-set! sg.current (cdr kind) 'undefined-value) )
          (else (static-wrong "Wrong redefinition" name)) )
        (let ((index (g.current-extend! name)))
          (vector-set! sg.current index 'undefined-value) ) ) )
  name )

;;;ooooooooooooooooooooo
(define (SEQUENCE m m+)
  (append m m+) )
(define (FIX-CLOSURE m+ arity)
  (let* ((the-function (append (ARITY=? (+ arity 1)) (EXTEND-ENV)
                               m+  (RETURN) ))
         (the-goto (GOTO (length the-function))) )
    (append (CREATE-CLOSURE (length the-goto)) the-goto the-function) ) )

(define NARY-CLOSURE 'wait)

(define (TR-FIX-LET m* m+)
  (append m* (EXTEND-ENV) m+) )

(define (FIX-LET m* m+)
  (append m* (EXTEND-ENV) m+ (UNLINK-ENV)) )

(define (CALL0 address)
  (INVOKE0 address) )

(define (CALL1 address m1)
  (append m1 (INVOKE1 address) ) )

(define (CALL2 address m1 m2)
  (append m1 (PUSH-VALUE) m2 (POP-ARG1) (INVOKE2 address)) )

(define (CALL3 address m1 m2 m3)
  (append m1 (PUSH-VALUE) 
          m2 (PUSH-VALUE) 
          m3 (POP-ARG2) (POP-ARG1) (INVOKE3 address) ) )

(define (TR-REGULAR-CALL m m*)
  (append m (PUSH-VALUE) m* (POP-FUNCTION) (FUNCTION-GOTO)) )

(define (REGULAR-CALL m m*)
  (append m (PUSH-VALUE) m* (POP-FUNCTION) 
          (PRESERVE-ENV) (FUNCTION-INVOKE) (RESTORE-ENV) ) )

(define (STORE-ARGUMENT m m* rank)
  (append m (PUSH-VALUE) m* (POP-FRAME! rank)) )
(define CONS-ARGUMENT 'wait)
(define EXPLICIT-CONSTANT 'wait)

;;;oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
;;; Determine the nature of a variable.
;;; Three different answers. Or the variable is local (ie appears in R)
;;; then return     (LOCAL index . depth)
;;; global (ie created by the user) then return
;;;                 (GLOBAL . index)
;;; or predefined (and immutable) then return
;;;                 (PREDEFINED . index)

(define (compute-kind r n)
  (or (local-variable? r 0 n)
      (global-variable? g.current n)
      (global-variable? g.init n) ) )

(define g.current '())
(define g.init '())
(define sg.init (make-vector 100))

(define (g.init-extend! n)
  (let ((level (length g.init)))
    (set! g.init
          (cons (cons n `(predefined . ,level)) g.init) )
    level ) )
(define (g.init-initialize! name value)
  (let ((kind (compute-kind r.init name)))
    (if kind
        (case (car kind)
          ((predefined)
           (vector-set! sg.init (cdr kind) value) )
          (else (static-wrong "Wrong redefinition" name)) )
        (let ((index (g.init-extend! name)))
          (vector-set! sg.init index value) ) ) )
  name )

(define (meaning e r tail?)
  (if (atom? e)
      (if (symbol? e) (meaning-reference e r tail?)
          (meaning-quotation e r tail?) )
      (case (car e)
        ((quote)  (meaning-quotation (cadr e) r tail?))
        ((lambda) (meaning-abstraction (cadr e) (cddr e) r tail?))
        ((if)     (meaning-alternative (cadr e) (caddr e) (cadddr e) r tail?))
        ((begin)  (meaning-sequence (cdr e) r tail?))
        ((set!)   (meaning-assignment (cadr e) (caddr e) r tail?))
        (else     (meaning-application (car e) (cdr e) r tail?)) ) ) )

(define (meaning-reference n r tail?)
  (let ((kind (compute-kind r n)))
    (if kind
        (case (car kind)
          ((local)
           (let ((i (cadr kind))
                 (j (cddr kind)) )
             (if (= i 0)
                 (SHALLOW-ARGUMENT-REF j)
                 (DEEP-ARGUMENT-REF i j) ) ) )
          ((global)
           (let ((i (cdr kind)))
             (CHECKED-GLOBAL-REF i) ) )
          ((predefined)
           (let ((i (cdr kind)))
             (PREDEFINED i) ) ) )
        (static-wrong "No such variable" n) ) ) )

(define (meaning-quotation v r tail?)
  (CONSTANT v) )

(define (meaning-alternative e1 e2 e3 r tail?)
  (let ((m1 (meaning e1 r #f))
        (m2 (meaning e2 r tail?))
        (m3 (meaning e3 r tail?)) )
    (ALTERNATIVE m1 m2 m3) ) )

(define (meaning-assignment n e r tail?) 
  (let ((m (meaning e r #f))
        (kind (compute-kind r n)) )
    (if kind
        (case (car kind)
          ((local)
           (let ((i (cadr kind))
                 (j (cddr kind)) )
             (if (= i 0)
                 (SHALLOW-ARGUMENT-SET! j m)
                 (DEEP-ARGUMENT-SET! i j m) ) ) )
          ((global)
           (let ((i (cdr kind)))
             (GLOBAL-SET! i m) ) )
          ((predefined)
           (static-wrong "Immutable predefined variable" n) ) )
        (static-wrong "No such variable" n) ) ) )

(define (meaning-sequence e+ r tail?)
  (if (pair? e+)
      (if (pair? (cdr e+))
          (meaning*-multiple-sequence (car e+) (cdr e+) r tail?)
          (meaning*-single-sequence (car e+) r tail?) )
      (static-wrong "Illegal syntax: (begin)") ) )

(define (meaning*-single-sequence e r tail?) 
  (meaning e r tail?) )

(define (meaning*-multiple-sequence e e+ r tail?)
  (let ((m1 (meaning e r #f))
        (m+ (meaning-sequence e+ r tail?)) )
    (SEQUENCE m1 m+) ) )

(define (meaning-abstraction nn* e+ r tail?)
  (let parse ((n* nn*)
              (regular '()) )
    (cond
      ((pair? n*) (parse (cdr n*) (cons (car n*) regular)))
      ((null? n*) (meaning-fix-abstraction nn* e+ r tail?))
      (else       (meaning-dotted-abstraction 
                   (reverse regular) n* e+ r tail? )) ) ) )

(define (meaning-fix-abstraction n* e+ r tail?)
  (let* ((arity (length n*))
         (r2 (r-extend* r n*))
         (m+ (meaning-sequence e+ r2 #t)) )
    (FIX-CLOSURE m+ arity) ) )

(define (meaning-dotted-abstraction n* n e+ r tail?)
  (let* ((arity (length n*))
         (r2 (r-extend* r (append n* (list n))))
         (m+ (meaning-sequence e+ r2 #t)) )
    (NARY-CLOSURE m+ arity) ) )

;;; Application meaning.

(define (meaning-application e e* r tail?)
  (cond ((and (symbol? e)
              (let ((kind (compute-kind r e)))
                (and (pair? kind)
                     (eq? 'predefined (car kind))
                     (let ((desc (get-description e)))
                       (and desc
                            (eq? 'function (car desc))
                            (or (= (length (cddr desc)) (length e*))
                                (static-wrong 
                                 "Incorrect arity for primitive" e )
                                ) ) ) ) ) )
         (meaning-primitive-application e e* r tail?) )
        ((and (pair? e)
              (eq? 'lambda (car e)) )
         (meaning-closed-application e e* r tail?) )
        (else (meaning-regular-application e e* r tail?)) ) )

;;; Parse the variable list to check the arity and detect wether the
;;; abstraction is dotted or not.

(define (meaning-closed-application e ee* r tail?)
  (let ((nn* (cadr e)))
    (let parse ((n* nn*)
                (e* ee*)
                (regular '()) )
      (cond
        ((pair? n*) 
         (if (pair? e*)
             (parse (cdr n*) (cdr e*) (cons (car n*) regular))
             (static-wrong "Too less arguments" e ee*) ) )
        ((null? n*)
         (if (null? e*)
             (meaning-fix-closed-application 
              nn* (cddr e) ee* r tail? )
             (static-wrong "Too much arguments" e ee*) ) )
        (else (meaning-dotted-closed-application 
               (reverse regular) n* (cddr e) ee* r tail? )) ) ) ) )

(define (meaning-fix-closed-application n* body e* r tail?)
  (let* ((m* (meaning* e* r (length e*) #f))
         (r2 (r-extend* r n*))
         (m+ (meaning-sequence body r2 tail?)) )
    (if tail? (TR-FIX-LET m* m+) 
        (FIX-LET m* m+) ) ) )

(define (meaning-dotted-closed-application n* n body e* r tail?)
  (let* ((m* (meaning-dotted* e* r (length e*) (length n*) #f))
         (r2 (r-extend* r (append n* (list n))))
         (m+ (meaning-sequence body r2 tail?)) )
    (if tail? (TR-FIX-LET m* m+)
        (FIX-LET m* m+) ) ) )

;;; Handles a call to a predefined primitive. The arity is already checked.
;;; The optimization is to avoid the allocation of the activation frame.
;;; These primitives never change the *env* register nor have control effect.

(define (meaning-primitive-application e e* r tail?)
  (let* ((desc (get-description e))
         ;; desc = (function address . variables-list)
         (address (cadr desc))
         (size (length e*)) )
    (case size
      ((0) (CALL0 address))
      ((1) 
       (let ((m1 (meaning (car e*) r #f)))
         (CALL1 address m1) ) )
      ((2) 
       (let ((m1 (meaning (car e*) r #f))
             (m2 (meaning (cadr e*) r #f)) )
         (CALL2 address m1 m2) ) )
      ((3) 
       (let ((m1 (meaning (car e*) r #f))
             (m2 (meaning (cadr e*) r #f))
             (m3 (meaning (caddr e*) r #f)) )
         (CALL3 address m1 m2 m3) ) )
      (else (meaning-regular-application e e* r tail?)) ) ) )

;;; In a regular application, the invocation protocol is to call the
;;; function with an activation frame and a continuation: (f v* k).

(define (meaning-regular-application e e* r tail?)
  (let* ((m (meaning e r #f))
         (m* (meaning* e* r (length e*) #f)) )
    (if tail? (TR-REGULAR-CALL m m*) (REGULAR-CALL m m*)) ) )

(define (meaning* e* r size tail?)
  (if (pair? e*)
      (meaning-some-arguments (car e*) (cdr e*) r size tail?)
      (meaning-no-argument r size tail?) ) )

(define (meaning-dotted* e* r size arity tail?)
  (if (pair? e*)
      (meaning-some-dotted-arguments (car e*) (cdr e*) 
                                     r size arity tail? )
      (meaning-no-dotted-argument r size arity tail?) ) )

(define (meaning-some-arguments e e* r size tail?)
  (let ((m (meaning e r #f))
        (m* (meaning* e* r size tail?))
        (rank (- size (+ (length e*) 1))) )
    (STORE-ARGUMENT m m* rank) ) )

(define (meaning-some-dotted-arguments e e* r size arity tail?)
  (let ((m (meaning e r #f))
        (m* (meaning-dotted* e* r size arity tail?))
        (rank (- size (+ (length e*) 1))) )
    (if (< rank arity) (STORE-ARGUMENT m m* rank)
        (CONS-ARGUMENT m m* arity) ) ) )

(define (meaning-no-argument r size tail?)
  (ALLOCATE-FRAME size) )

(define (meaning-no-dotted-argument r size arity tail?)
  (ALLOCATE-DOTTED-FRAME arity) )

(define (check-byte j)
  (or (and (<= 0 j) (<= j 255))
      (static-wrong "Cannot pack this number within a byte" j) ) )

(define (SHALLOW-ARGUMENT-SET! j m)
  (append m (SET-SHALLOW-ARGUMENT! j)) )

(define (DEEP-ARGUMENT-SET! i j m)
  (append m (SET-DEEP-ARGUMENT! i j)) )

(define (GLOBAL-SET! i m)
  (append m (SET-GLOBAL! i)) )

(define (SHALLOW-ARGUMENT-REF j)
  (check-byte j)
  (case j
    ((0 1 2 3) (list (+ 1 j)))
    (else      (list 5 j)) ) )

(define (PREDEFINED i) (list 'PREDEFINED i))
#|
(define (PREDEFINED i)
  (check-byte i)
  (case i
    ;; 0=\#t, 1=\#f, 2=(), 3=cons, 4=car, 5=cdr, 6=pair?, 7=symbol?, 8=eq?
    ((0 1 2 3 4 5 6 7 8) (list (+ 10 i)))
    (else                (list 19 i)) ) )

(define (DEEP-ARGUMENT-REF i j) (list 6 i j))
(define (SET-SHALLOW-ARGUMENT! j)
  (case j
    ((0 1 2 3) (list (+ 21 j)))
    (else      (list 25 j)) ) )
|#
(define (DEEP-ARGUMENT-REF i j) (list 'DEEP-ARGUMENT-REF i j))
(define (SET-SHALLOW-ARGUMENT! j) (list 'SET-SHALLOW-ARGUMENT! j))
(define (SET-DEEP-ARGUMENT! i j) (list 'SET-DEEP-ARGUMENT! i j))

;(define (SET-DEEP-ARGUMENT! i j) (list 26 i j))

;(define (GLOBAL-REF i) (list 7 i))

(define (CHECKED-GLOBAL-REF i) (list 8 i))

(define (SET-GLOBAL! i) (list 27 i))

(define (CONSTANT value) (list 'CONSTANT value))
#|
(define (CONSTANT value)
  (cond ((eq? value #t)    (list 10))
        ((eq? value #f)    (list 11))
        ((eq? value '())   (list 12))
        ((equal? value -1) (list 80))
        ((equal? value 0)  (list 81))
        ((equal? value 1)  (list 82))
        ((equal? value 2)  (list 83))
        ((equal? value 4)  (list 84))
        ((and (integer? value)  ; immediate value
              (<= 0 value)
              (< value 255) )
         (list 79 value) )
        (else (EXPLICIT-CONSTANT value)) ) )
|#
;;; All gotos have positive offsets (due to the generation)

(define (GOTO offset) (list 'GOTO offset))
#|(define (GOTO offset)
  (cond ((< offset 255) (list 30 offset))
        ((< offset (+ 255 (* 255 256))) 
         (let ((offset1 (modulo offset 256))
               (offset2 (quotient offset 256)) )
           (list 28 offset1 offset2) ) )
        (else (static-wrong "too long jump" offset)) ) )
|#
(define (JUMP-FALSE offset) (list 'JMUP-FALSE offset))
#|
(define (JUMP-FALSE offset)
  (cond ((< offset 255) (list 31 offset))
        ((< offset (+ 255 (* 255 256))) 
         (let ((offset1 (modulo offset 256))
               (offset2 (quotient offset 256)) )
           (list 29 offset1 offset2) ) )
        (else (static-wrong "too long jump" offset)) ) )
|#

;;(define (EXTEND-ENV) (list 32))
;;(define (UNLINK-ENV) (list 33))
(define (EXTEND-ENV) (list 'EXTEND-ENV))
(define (UNLINK-ENV) (list 'UNLINK-ENV))

(define (INVOKE0 address)
  (case address
    ((read)    (list 89))
    ((newline) (list 88))
    (else (static-wrong "Cannot integrate" address)) ) )

(define (INVOKE1 address)
  (case address
    ((car)     (list 90))
    ((cdr)     (list 91))
    ((pair?)   (list 92))
    ((symbol?) (list 93))
    ((display) (list 94))
    (else (static-wrong "Cannot integrate" address)) ) )

;;; The same one with other unary primitives.
#|
(define (INVOKE1 address)
  (case address
    ((car)     (list 90))
    ((cdr)     (list 91))
    ((pair?)   (list 92))
    ((symbol?) (list 93))
    ((display) (list 94))
    ((primitive?) (list 95))
    ((null?)   (list 96))
    ((continuation?) (list 97))
    ((eof-object?)   (list 98))
    (else (static-wrong "Cannot integrate" address)) ) )
|#

(define (ALTERNATIVE m1 m2 m3)
  (let ((mm2 (append m2 (GOTO (length m3)))))
    (append m1 (JUMP-FALSE (length mm2)) mm2 m3) ) )

;;(define (PUSH-VALUE) (list 34)) 
;;(define (POP-ARG1) (list 35))
(define (PUSH-VALUE) (list 'PUSH-VALUE)) 
(define (POP-ARG1) (list 'POP-ARG1))

#|
(define (INVOKE2 address)
  (case address
    ((cons)     (list 100))
    ((eq?)      (list 101))
    ((set-car!) (list 102))
    ((set-cdr!) (list 103))
    ((+)        (list 104))
    ((-)        (list 105))
    ((=)        (list 106))
    ((<)        (list 107))
    ((>)        (list 108))
    ((*)        (list 109))
    ((<=)       (list 110))
    ((>=)       (list 111))
    ((remainder)(list 112))
    (else (static-wrong "Cannot integrate" address)) ) )
|#

(define (INVOKE2 address)
  (case address
    ((cons)     (list 'CONS))
    ((eq?)      (list 'EQ?))
    ((set-car!) (list 'SET-CAR!))
    ((set-cdr!) (list 'SET-CDR!))
    ((+)        (list 'ADD))
    ((-)        (list 'SUB))
    ((=)        (list 'EQUAL))
    ((<)        (list '<))
    ((>)        (list '>))
    ((*)        (list '*))
    ((<=)       (list '<=))
    ((>=)       (list '>=))
    ((remainder)(list 'REMAINDER))
    (else (static-wrong "Cannot integrate" address)) ) )

(define (POP-ARG2) (list 36))

(define (INVOKE3 address)
  (static-wrong "No ternary integrated procedure" address) )

(define (CREATE-CLOSURE offset) (list 'CREATE-CLOSURE offset))
;;(define (CREATE-CLOSURE offset) (list 40 offset))

(define (ARITY=? arity+1) (list 'ARITY=? arity+1))

#|
(define (ARITY=? arity+1)
  (case arity+1
    ((1 2 3 4) (list (+ 70 arity+1)))
    (else        (list 75 arity+1)) ) )
|#
;;(define (RETURN) (list 43))
(define (RETURN) (list 'RETURN))

(define (PACK-FRAME! arity) (list 44 arity))

(define (ARITY>=? arity+1) (list 78 arity+1))

;(define (FUNCTION-GOTO) (list 46))
(define (FUNCTION-GOTO) (list 'FUNCTION-GOTO))
;(define (POP-FUNCTION) (list 39))
(define (POP-FUNCTION) (list 'POP-FUNCTION))

(define (FUNCTION-INVOKE) (list 45))

(define (PRESERVE-ENV) (list 37))

(define (RESTORE-ENV) (list 38))

#|
(define (POP-FRAME! rank)
  (case rank
    ((0 1 2 3) (list (+ 60 rank)))
    (else      (list 64 rank)) ) )
|#
(define (POP-FRAME! rank)
  (list 'POP-FRAME! rank))

(define (POP-CONS-FRAME! arity) (list 47 arity))

#|
(define (ALLOCATE-FRAME size)
  (case size
    ((0 1 2 3 4) (list (+ 50 size)))
    (else        (list 55 (+ size 1))) ) )
|#
(define (ALLOCATE-FRAME size) (list 'ALLOCATE-FRAME size))

(define (ALLOCATE-DOTTED-FRAME arity) (list 56 (+ arity 1)))

;(define (FINISH) (list 20))
(define (FINISH) (list 'FINISH))

;;;ooooooooooooooooooooooooooooooooooooo
(define-syntax definitial
  (syntax-rules ()
    ((definitial name value)
     (g.init-initialize! 'name value) ) ) )
(definitial t #t)
(definitial f #f)
(definitial nil '())

(define-syntax defprimitive
  (syntax-rules ()
    ((defprimitive name value 0)
     (defprimitive0 name value) )
    ((defprimitive name value 1)
     (defprimitive1 name value) )
    ((defprimitive name value 2)
     (defprimitive2 name value) )
    ((defprimitive name value 3)
     (defprimitive3 name value) ) ) )  

(define-syntax defprimitive0
  (syntax-rules ()
    ((defprimitive0 name value)
     (definitial name
       (begin
         (description-extend! 'name `(function value))
         (lambda (v) name))))))

;;;oooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
;;; Describe a predefined value.
;;; The description language only represents primitives with their arity:
;;;          (FUNCTION address . variables-list)
;;; with variables-list := () | (a) | (a b) | (a b c)
;;; Only the structure of the VARIABLES-LIST is interesting (not the
;;; names of the variables). ADDRESS is the address of the primitive
;;; to use when inlining an invokation to it. This address is
;;; represented by a Scheme procedure.

(define desc.init '())

(define (get-description name)
  (let ((p (assq name desc.init)))
    (and (pair? p) (cdr p)) ) )

(define (description-extend! name description)
  (set! desc.init 
        (cons (cons name description) desc.init) )
  name )

(define-syntax defprimitive1
  (syntax-rules ()
    ((defprimitive1 name value)
     (definitial name
       (begin
         (description-extend! 'name `(function value a))
         (lambda (v) name))))))

(define-syntax defprimitive2
  (syntax-rules ()
    ((defprimitive2 name value)
     (definitial name
       (begin
         (description-extend! 'name `(function value a b))
         (lambda (v) name))))))

(defprimitive cons cons 2)
(defprimitive car car 1)
(defprimitive cdr cdr 1)
(defprimitive pair? pair? 1)
(defprimitive symbol? symbol? 1)
(defprimitive eq? eq? 2)
;;(defprimitive set-car! set-car! 2)
;;(defprimitive set-cdr! set-cdr! 2)
(defprimitive + + 2)
(defprimitive - - 2)
(defprimitive = = 2)
(defprimitive < < 2)
(defprimitive > > 2)
(defprimitive * * 2)
(defprimitive <= <= 2)
(defprimitive >= >= 2)
(defprimitive remainder remainder 2)
(defprimitive display display 1)
(defprimitive read read 0)
(defprimitive primitive? primitive? 1)
(defprimitive continuation? continuation? 1)
(defprimitive null? null? 1)
(defprimitive newline newline 0)
(defprimitive eof-object? eof-object? 1)