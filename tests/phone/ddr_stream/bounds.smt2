; The two complete admission predicates must agree for arbitrary inputs.
; Run: z3 tests/phone/ddr_stream/bounds.smt2
(set-logic QF_BV)
(declare-fun req_addr () (_ BitVec 32))
(declare-fun req_count () (_ BitVec 7))
(declare-fun req_write () Bool)
(declare-fun req_stream () Bool)
(declare-fun req_fill () Bool)
(declare-fun write_fill_enabled () Bool)

(define-fun common () Bool
  (and (distinct req_count (_ bv0 7))
       (bvule req_count (_ bv64 7))
       (= ((_ extract 2 0) req_addr) #b000)
       (or (not req_write) req_stream (and write_fill_enabled req_fill)
           (= req_count (_ bv1 7)))))
(define-fun request_end () (_ BitVec 33)
  (bvadd ((_ zero_extend 1) req_addr)
         (bvshl ((_ zero_extend 26) req_count) (_ bv3 33))))
(define-fun old_valid () Bool
  (and common (bvule request_end (_ bv4294967296 33))))

(define-fun window_end () (_ BitVec 7)
  (bvadd ((_ zero_extend 1) ((_ extract 8 3) req_addr)) req_count))
(define-fun in_final_window () Bool
  (= ((_ extract 31 9) req_addr) (_ bv8388607 23)))
(define-fun new_valid () Bool
  (and common (or (not in_final_window) (bvule window_end (_ bv64 7)))))

(assert (distinct old_valid new_valid))
(check-sat)
