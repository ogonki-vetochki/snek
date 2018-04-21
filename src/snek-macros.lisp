
(in-package :snek)

(defmacro with ((snk &key zwidth collect include-alts) &body body)
  "
  creates a context for manipulating snek via alterations.
  all alterations created in this context will be flattened
  and applied to snk at the end of the context.
  "
  (declare (type boolean collect))
  (declare (type boolean include-alts))
  (with-gensyms (sname zw aname rec x y resalts do-funcall finally)
    (let* ((do-funcall `(funcall (gethash (type-of ,x) ,aname) ,sname ,x))
           (wrap-funcall (cond ((and collect include-alts)
                                  `(array-push (list ,do-funcall ,x) ,resalts))
                               (collect `(array-push ,do-funcall ,resalts))
                               (t do-funcall)))
           (finally (if collect `(to-list ,resalts)
                                nil)))

      `(let* ((,sname ,snk)
              (,zw ,zwidth)
              (,resalts (make-generic-array))
              (,aname (snek-alt-names ,sname)))

        (incf (snek-wc ,sname))

        (labels ((,rec (,x)
                  (cond ((null ,x))
                  ((atom ,x)
                     ; if atom is also alteration (else ignore):
                     (when (gethash (type-of ,x) ,aname) ,wrap-funcall))
                  (t (,rec (car ,x))
                     (,rec (cdr ,x))))))

          (zmap:with* (,zw (snek-verts ,sname) (snek-num-verts ,sname)
                          (lambda (,y) (setf (snek-zmap ,sname) ,y)))
            ; this lets @body be executed in the context of zmap:with;
            ; useful if we want to have a parallel context inside zmap.
            (,rec (list ,@body))))

        ,finally))))


(defmacro zwith ((snk zwidth) &body body)
  "
  creates a snek context. the zmap is constant inside this context.
  "
  (with-gensyms (sname zw y)
    `(let ((,sname ,snk)
           (,zw ,zwidth))
      (zmap:with* (,zw (snek-verts ,sname) (snek-num-verts ,sname)
                        (lambda (,y) (setf (snek-zmap ,sname) ,y)))
          (progn ,@body)))))


(defmacro with-verts-in-rad ((snk xy rad v) &body body)
  (with-gensyms (sname)
    `(let ((,sname ,snk))
      (zmap:with-verts-in-rad ((snek-zmap ,sname) (snek-verts ,sname) ,xy ,rad ,v)
        (progn ,@body)))))


(defmacro with-dx ((snk vv dx d) &body body)
  (with-gensyms (sname)
    `(let ((,sname ,snk))
       (let* ((,dx (apply #'vec:isub (get-verts ,sname ,vv)))
              (,d (vec:len ,dx)))
         (declare (double-float ,d))
         (declare (vec:vec ,dx))
         (when (> ,d 0d0)
           (list ,@body))))))


(defmacro with-grp ((snk grp g) &body body)
  "
  select a grp from a snek instance. the grp will be available
  in the context as g.
  "
  (with-gensyms (grps exists gname sname)
    `(let ((,sname ,snk)
           (,gname ,g))
      (let ((,grps (snek-grps ,sname)))
        (multiple-value-bind (,grp ,exists)
          (gethash ,gname ,grps)
            (unless ,exists
              (error "attempted to access invalid group: ~a" ,gname))
            (progn ,@body))))))


(defmacro with-rnd-edge ((snk i &key g) &body body)
  "
  select an arbitrary edge from a snek instance. the edge will be
  available in the context as i.

  if a grp is supplied it will select an edge from g, otherwise it will
  use the main grp.
  "
  (with-gensyms (grp edges grph ln)
    `(with-grp (,snk ,grp ,g)
      (let ((,grph (grp-grph ,grp)))
        (let* ((,edges (graph:get-edges ,grph))
               (,ln (length ,edges)))
          (declare (integer ,ln))
          (when (> ,ln 0)
            (let ((,i (aref ,edges (random ,ln))))
              (declare (list ,i))
              (list ,@body))))))))


(defmacro with-rnd-vert ((snk i) &body body)
  "
  select an arbitrary vert from a snek instance. the vert will be
  available in the context as i.
  "
  (with-gensyms (num)
    `(let ((,num (snek-num-verts ,snk)))
       (when (> ,num 0)
         (let ((,i (random ,num)))
           (declare (integer ,i))
           (list ,@body))))))


(defmacro itr-verts ((snk i &key g (collect t)) &body body)
  "
  iterates over all verts in grp g as i.

  you should use itr-all-verts if you can, as it is faster.

  if g is not provided, the main grp wil be used.
  "
  (declare (type boolean collect))
  (with-gensyms (grp sname)
    `(let ((,sname ,snk))
      (with-grp (,sname ,grp ,g)
        (map ',(if collect 'list 'nil)
          (lambda (,i) (declare (integer ,i)) (list ,@body))
          (graph:get-verts (grp-grph ,grp)))))))


(defmacro itr-prm-verts ((snk i &key p (collect t)) &body body)
  "
  iterates over all verts in prm p as i.
  "
  (declare (type boolean collect))
  (with-gensyms (prm pr sname)
    `(let* ((,sname ,snk))
      (map ',(if collect 'list 'nil)
          (lambda (,i) (declare (integer ,i)) (list ,@body))
          (get-prm-vert-inds ,sname :p ,p)))))


(defmacro itr-all-verts ((snk i &key (collect t)) &body body)
  "
  iterates over all verts in snk as i.
  "
  (declare (type boolean collect))
  (with-gensyms (sname)
    `(let ((,sname ,snk))
      (loop for ,i of-type integer from 0 below (snek-num-verts ,sname)
        ,(if collect 'collect 'do) (list ,@body)))))


(defmacro itr-edges ((snk i &key g (collect t)) &body body)
  "
  iterates over all edges in grp g as i.

  if g is not provided, the main grp will be used.
  "
  (declare (type boolean collect))
  (with-gensyms (grp grph)
    `(with-grp (,snk ,grp ,g)
      (let ((,grph (grp-grph ,grp)))
        (map ',(if collect 'list 'nil)
             (lambda (,i) (list ,@body))
             (graph:get-edges ,grph))))))


(defmacro itr-grps ((snk g &key (collect t) main) &body body)
  "
  iterates over all grps of snk as g.
  "
  (declare (type boolean collect))
  (with-gensyms (grps sname main*)
    `(let ((,sname ,snk)
           (,main* ,main))
      (let ((,grps (snek-grps ,sname)))
        (loop for ,g being the hash-keys of ,grps
          if (or ,main* ,g)
          ,(if collect 'collect 'do) (list ,@body))))))


(defmacro itr-prms ((snk p &key (collect t)) &body body)
  "
  iterates over all prms of snk as p.
  "
  (declare (type boolean collect))
  (with-gensyms (prms sname)
    `(let ((,sname ,snk))
      (let ((,prms (snek-prms ,sname)))
        (loop for ,p being the hash-keys of ,prms
          ,(if collect 'collect 'do) (list ,@body))))))

