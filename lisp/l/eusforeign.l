;;;;
;;;;	Foreign language interface
;;;;	1987-SEP-25
;;;;	Copyright Toshihiro MATSUI
;;;;
(in-package "LISP")
(eval-when (load eval)
#-(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(export '(read-symbol-table foreign-module))

(export '(load-foreign defforeign make-foreign-code defvoidforeigns
	defun-c-callable pod-address byte-size cstructclass cstruct
	defcstruct carray defcarray foreign-string make-foreign-string)) )

(defmethod load-module
 (:find (symname)
       (system::find-entry symname self)))


#-(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)   
(defun read-symbol-table (objfile &optional (offset 0))
  (let* ((nm)
	 (line nil)
	 (strm nil)
	 (address nil)
	 (mark nil)
	 (sym nil)
	 (eof (gensym))
	 (htab (make-hash-table :size 10 :test #'equal))
	 (*read-base* 16))
    ; run "nm -gp objfile >tmpfile". 
    (setq nm (piped-fork "nm" "-gp" objfile))
    ; read the symbol tables from the pipe
    (while (not (eq (setq line (read-line nm nil eof)) eof))
	(when (not (eq (elt line 0) #\ ))
	    (setq strm (make-string-input-stream  line))
	    (setq address (+ (read strm) offset)
		  mark (read strm))
	    (read-char strm)
	    (setq sym (read-line strm))
	    (setf (gethash sym htab) (list mark address))))
    (close nm)
    htab))

#-(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(defclass foreign-module :super compiled-code
			 :slots (symbol-table object-file))

#-(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(defmethod foreign-module
 (:code-alignment (symfile)
    (if (not (equal object-file symfile))
        (if (intersection '(:sun4 :news :vax :mips) *features*)
	    (- (sys:address codevector))
	    (- (+ (sys:address codevector) 2)))
        (cond
	    ((member :sun4 *features*)
	     (if (member :sunos4 *features*)
		 8
		 (- 1024 (mod (sys:address codevector) 1024))) )
	    ((member :vax *features*) 8)
	    ((member :mips *features*) 8)
	    (t  6))))	;sun3 --> 6
 (:load (file &key (symbol-input (namestring *symbol-input*))
		   (symbol-output "") (ld-option "")
		   (symbol-file file))
    (let ((om ; (sys:binload file "" "" symbol-input symbol-output ld-option)
		(load file :entry ""	;foreign module cannot have entry
			   :symbol-input symbol-input 
			   :symbol-output symbol-output
			   :ld-option ld-option)
		) )
	(setq codevector (compiled-code-codevector om)
	      quotevector (compiled-code-quotevector om)
	      object-file file
	      symbol-table
	         (read-symbol-table symbol-file
				    (send self :code-alignment symbol-file)))
	self  ))
 (:find (entry)   (gethash entry symbol-table))
 (:address (entry) (+ (sys:address codevector) (cadr (send self :find entry))))
 (:defforeign (name entry params result)
    (let ((fc (instance foreign-code))
          (e (gethash entry symbol-table)))
       (if (null e)
           (setq e (gethash (subseq entry 1) symbol-table)))
       (cond 
	  (e
	   (setq (fc . type) 0	;function
		 (fc . codevector) (self . codevector)
		 (fc . quotevector) (self . quotevector)
	         (fc . entry) (cadr e)
		 (fc . paramtypes) params
		 (fc . resulttype) result)
	   (setf (symbol-function name) fc)
	   name)
	  (t (warn "no such entry ~s~%" entry)))
      ))
   )

#+(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(defmethod foreign-code
 (:init (ent &optional param (result :integer))
    (setq codevector 0
	  quotevector nil
	  entry ent
	  paramtypes param
	  resulttype result
	  type 0)	; function
    self))

#+(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(defun make-foreign-code (fentry &optional param (result :integer)
					(fmod (sys::sysmod)))
	 (cond ((numberp fentry))
	       ((system::find-entry fentry fmod)
		(setq fentry (system::find-entry fentry fmod)))
	       (t (error "no such foreign entry ~s" fentry)))
   (instance foreign-code :init fentry param result))

;;;

#-(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(defun load-foreign (file &key  (symbol-input (namestring *symbol-input*))
				(symbol-output "")
			        (ld-option "")    (symbol-file file))
   (instance foreign-module :load file  :symbol-input symbol-input
					:symbol-output symbol-output
					:ld-option ld-option
					:symbol-file symbol-file))

#+(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(defun load-foreign (file)   (load file :entry ""))

#-(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(defmacro defforeign (name fmod label param result)
   `(send ,fmod :defforeign ',name ,label ',param ',result))

#+(or :solaris2 :linux :irix :irix6 :sunos4.1 :alpha :cygwin)
(defmacro defforeign  (name fmod label param result)
   `(setf (symbol-function ',name)
	  (make-foreign-code ,label ',param ',result ,fmod)))

(defmacro defvoidforeigns (mod &rest names)
   `(dolist (fname ',names)
	(setf (symbol-function (intern (string-upcase fname)))
	      (make-foreign-code fname nil :integer ,mod))))

;(eval-when (compile)
;  (defclass foreign-pod :super symbol :slots (podcode paramtypes resulttype)))

(defmethod foreign-pod
 (:pod-address () (+ 8 (sys:address podcode)))
 (:init (param result func)
    (let ((self-address (sys:address self)))
      (cond
	((memq :sun3 *features*)
	 (inc self-address 2)
	 (setq podcode (make-string #x36))
	 (replace  podcode 
	      (list #x4E #x56 #x00 #x00			;linkw #0,a6
		    #x48 #x6E #x00 #x08			;pea a6@(8)
		    #x2F #x3C (ldb self-address 24 8)
			      (ldb self-address 16 8)
			      (ldb self-address 8 8)
			      (ldb self-address 0 8)	;movl #self,sp@-
		    #x4E #xB9 (ldb *calleus* 24 8)
			      (ldb *calleus* 16 8)
			      (ldb *calleus* 8 8)
			      (ldb *calleus* 0 8)	;jsr _calleus
		    #x50 #x8F				;addql 8,sp
		    #x2d #x40 #x00 #x08			;movl d0,a6@(8)
		    #xf2 #x2e #x44 #x00 #x00 #x08	;fmoves a6@(8),fp0
		    #x4E #x5E				;unlk a6
		    #x4E #x75				;rts
		    )))
	((memq :sun4 *features*)
	 (setq podcode (make-string #x48))	;18 long words
	 (let ( (self-address-high (ldb self-address 10 22))
		(self-address-low (ldb self-address 0 10))
		(calleus (ash (- *calleus* (+ (sys:address podcode) 8 44))
			      -2)))
	     (replace  podcode
		(list
		 #x03 #x3F #xFF #xFF	;sethi
		 #x82 #x00 #x63 #xA0	;add
		 #x9D #xE3 #x80 #x01	;save
		 #xF0 #x27 #xA0 #x44	; %i0
		 #xF2 #x27 #xA0 #x48	; %i1
		 #xF4 #x27 #xA0 #x4C	; %i2
		 #xF6 #x27 #xA0 #x50	; %i3
		 #xF8 #x27 #xA0 #x54	; %i4
		 #xFA #x27 #xA0 #x58	; %i5
		 #x11 (ldb self-address-high 16 8)
		      (ldb self-address-high 8 8)
		      (ldb self-address-high 0 8)   ;sethi symboladdress,%o0
		 #x90 #x12 (+ #x20 (ldb self-address-low 8 2))
			  (ldb self-address-low 0 8)	;add ...
		 (+ #x40 (ldb calleus 24 6))	;call _calleus
		    (ldb calleus 16 8) (ldb calleus 8 8) (ldb calleus 0 8)
		 #x92 #x07 #xA0 #x44	;add
		 #xB0 #x10 #x00 #x08	;mov
		 #xD0 #x27 #xa0 #x44	;st
		 #xc1 #x07 #xa0 #x44	;ldf
		 #x81 #xC7 #xE0 #x08	;ret
		 #x81 #xE8 #x00 #x00	;restore
		))))
	(t (error "not yet implemented for this processor")))
      (cond 
	 ((listp func)
	   (if (eq (car func) 'lisp:lambda-closure)
	       (setq func (append '(lisp:lambda) (nthcdr 4 func)))))
	 ((derivedp func closure)
	       (setq func (func . code))))
      (setq function func)
      (setq paramtypes param
	    resulttype result)
      self))
)



(defmacro defun-c-callable (name param &rest forms)
  (let ((paramspecs
	    (mapcar #'(lambda (x) (if (atom x) :integer (cadr x))) param))
        (paramsyms
	    (mapcar #'(lambda (x) (if (atom x) x (car x))) param))
	(result (if (keywordp (car forms))
		    (car forms)
		    :integer))
	(bod (if (keywordp (car forms))
		 (cdr forms)
	       forms))
	)
    `(progn
       (unintern ',name *package*)
       (send (let ((symbol foreign-pod))
		(intern ',(string name) *package*))
	     :init ',paramspecs ',result
	     #'(lambda ,paramsyms . ,bod)))))


(defun pod-address (x) (send x :pod-address))


;(eval-when (load)
;  (defvar *eus-module*
;    (let ((m (instance foreign-module)))
;      (setq (m . symbol-table) 
;	     (read-symbol-table "/usr/local/bin/eus"))
;      (setq (m . codevector) 0)
;      m)) )


;;;;	cstruct
;;;;	Enables handling C's struct in euslisp
;;;	
;;;	1987-Nov
;;;	Copyright Toshihiro MATSUI
;;;
;;;	(defcstruct structname
;;;		    (slotid :primitive-type)
;;;		    (slotid structname)
;;;		    (slotid (:primitive-type [*] [dimension])))

(defvar sizeof-types
  `((:pointer ,lisp::sizeof-*) (:long ,lisp::sizeof-long)
    (:int ,lisp::sizeof-int) (:integer ,lisp::sizeof-int)
    (:short ,lisp::sizeof-short) (:char ,lisp::sizeof-char)
    (:character ,lisp::sizeof-char) (:float ,lisp::sizeof-float)
    (:double ,lisp::sizeof-double) (:word 2) (:byte 1)))

(defun byte-size (typekey)
  (cadr (assq typekey sizeof-types)))

(defclass cstructclass :super vectorclass :slots (slotlist))

(defmethod cstructclass
 (:slotlist (&optional slots)
    (if (null slots) (return-from :slotlist slotlist))
    (setq slotlist nil)
    (let ((offset 0) (slotsize 0) (typespec) (element_size) (element_count 1)
	  (s) (typename) slist)
	(dolist (sl slots)	;expand reference to other cstructs
	   (setq typespec (cadr sl))
	   (cond ((and (symbolp typespec) (not (keywordp typespec)))
		  (dolist (x (send (symbol-value (cadr sl)) :slotlist))
		     (push (cons (intern (concatenate string	
				      (string (car sl)) "." (string (car x))))
				 (cdr x))
			   slist)))
		 (t (push sl slist))))
	(setq slist (nreverse slist))
	(dolist (sl slist)
	    (setq typename (car sl)
	    	  typespec (cadr sl)
		  s (cddr sl)
		  element_size (byte-size typespec))
	    (unless (keywordp typespec)
		(error "keyword expected for cstruct type"))
	    (when (eq (car s) '*)
		(setq typespec :pointer
		      element_size lisp::sizeof-*)	;pointer
		(pop s))
	    (setq element_count (if (car s) (car s) 1))
	    (setq slotsize (* element_size element_count))
	    (setq offset
		  (* (/ (+ offset element_size -1) element_size) element_size))
	    (push (list typename	;0
			typespec	;1
			element_count	;2
			element_size	;3
			offset		;4
			slotsize)	;5
		  slotlist)
	    (inc offset slotsize))
      (setq slotlist (nreverse slotlist))
      (setq size offset)
      slotlist))
 (:size () size)
 (:slot (id)
   (if id
     (assq id slotlist)
     (car slotlist)))
 (:offset (id &optional index)
    (let ((slot (send self :slot id)))
	(unless slot  (error "no such cstruct slot ~s" id))
	(cond (index
		(if (>= index (elt slot 2)) (error "index out of range"))
		(+ (elt slot 4) (* index  (elt slot 3))) )
	      (t  (elt slot 4)))))
 (:access (id &optional index)
    (let ((slot (send self :slot id)) (offset))
	(unless slot  (error "no such cstruct slot"))
	(cond (index
		(if (>= index (elt slot 2)) (error "index out of range"))
		(setq offset (+ (elt slot 4) (* index  (elt slot 3))) ))
	      (t (setq offset  (elt slot 4))))
	(list (elt slot 1) offset)))
  )

(defclass cstruct :super string :element-type :byte)

(defmethod cstruct
 (:get (id &optional index)
    (let ((slot (send (class self) :access id index)))
	(sys:peek self (cadr slot) (car slot))) )
 (:set (val id &optional index)
    (let ((slot (send (class self) :access id index)))
	(sys:poke val self (cadr slot) (car slot))))
 )


(defmacro defcstruct (struct-name &rest slotlist)
   (let (accessors slotname getter setter setter-fn type (offset 0)
	 slot slotsize substruct expanded-slotlist
	 element_type element_size accessor accessor-fn accessor-name
	 (struct-name-string (string struct-name)) (super 'cstruct))
     (when (eq (car slotlist) :super)
       (setq super (cadr slotlist))
       (setq slotlist (cddr slotlist)))
     (dolist (s slotlist)
	(setq type (cadr s))
	(if (and (symbolp type) (not (keywordp type))) ;struct of struct
	    (dolist (x (send (symbol-value (cadr s)) :slotlist))
		(push (list (intern (concatenate  string
				(string (car s)) "." (string (car x))))
			    (cadr x))
		      expanded-slotlist) )
	    (push s expanded-slotlist)))
     (dolist (s (nreverse expanded-slotlist))
	(setq slotname (string (car s))
	      type (cadr s)
	      accessor-name (concatenate string 
					 struct-name-string "-" slotname)
	      accessor (intern accessor-name)
	      accessor-fn (intern (concatenate string "SET-" accessor-name))
	      s (cddr s))
	(cond ((null s)
		(setq slotsize (byte-size type)
		      offset (* (/ (+ offset slotsize -1) slotsize) slotsize)
		      getter `(defun ,accessor (s)
				(sys:peek s ,offset ,type))
		      setter `(defsetf ,accessor ,accessor-fn)
		      setter-fn `(defun ,accessor-fn (s val)
				   (sys:poke val s ,offset ,type))))
	      (t
		(setq element_type type)	;array of pointer or primitive
		(when (eq (car s) '*)		;pointer 
		   (setq element_type :long)
		   (pop s))
		(setq element_size (byte-size element_type)
		      slotsize (* element_size (if (car s) (car s) 1))
		      offset (* (/ (+ offset element_size -1)
				   element_size) element_size))
		(cond
		   ((memq element_type '(:char :byte))
		    (setq getter `(defun ,accessor (s &optional i)
				    (if i
				      (sys:peek s (+ ,offset i) :byte)
				      (subseq s ,offset (+ ,offset ,slotsize)))))
		    (setq setter `(defsetf ,accessor ,accessor-fn)
			  setter-fn `(defun ,accessor-fn (s i &rest val)
				       (if val
					 (sys:poke (car val)
						   (+ ,offset i) :byte)
					 (replace s i :start1 ,offset
						      :end2 (length i))))))
		   (t
		    (setq getter `(defun ,accessor (s i)
				    (declare (fixnum i))
				    (sys:peek s (+ ,offset
						   (* i ,element_size))
					      ,element_type)))
		    (setq setter `(defsetf ,accessor ,accessor-fn)
			  setter-fn `(defun ,accessor-fn (s i val)
				       (declare (fixnum i))
				       (sys:poke val s
						 (+ ,offset
						    (* i ,element_size))
						 ,element_type))))))
	      (t (error "illegal type specifier")))
	(push getter accessors)
	(push setter accessors)
	(push setter-fn accessors)
	(inc offset slotsize))
     `(progn
	  (defclass ,struct-name :super ,super
				 :element-type :byte
				 :metaclass cstructclass)
	  (send ,struct-name :slotlist ',slotlist)
	  ,@(nreverse accessors)
	  ',struct-name)))

(defclass carray :super cstruct)

(defmethod carray
  (:get (&optional (index 0))
    (send-super :get nil index))
  (:set (val &optional (index 0))
    (send-super :set val nil index)))

(defmacro defcarray (array-name type &optional (size 1))
  (let* ((field (gensym (symbol-name type)))
	 (array-name-string (symbol-name array-name))
	 (accessor-string (concatenate string array-name-string "-"
				       (symbol-name field)))
	 (set (intern (concatenate string "SET-" array-name-string)))
	 (get-field (intern accessor-string))
	 (set-field (intern (concatenate string "SET-" accessor-string))))
    `(progn
       (defcstruct ,array-name :super carray (,field ,type ,size))
       (defun ,array-name (s &optional (i 0))
	 (,get-field s i))
       (defun ,set (s i &optional val)
	 (if val
	   (,set-field s i val)
	   (,set-field s 0 i)))
       (defsetf ,array-name ,set)
       ',array-name)))

(defclass foreign-string :super vector :element-type :foreign)
(defun make-foreign-string (addr size)
   (let* ((fstr (instantiate foreign-string size)) )
      (sys:poke addr (+ (* 2 lisp::sizeof-*) (sys:address fstr)) :long)
      fstr))

(provide :eusforeign "@(#)$Id$")