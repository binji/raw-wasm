(memory (export "mem") 8)
(data (i32.const 1050)
  ;; == Temp huffman data ==
  ;; addr:0    lens    (size: 1b x 318 = 318)
  ;; addr:318  offs    (size: 2b x  32 =  64)

  ;; == Lit/codelen huffman ==
  ;; addr:382  count   (size: 1b x  32 =  32)
  ;; addr:414  syms    (size: 2b x 318 = 636)

  ;; == Constant data ==
  ;; addr:1050   codelen literals  (size: 1b x 19 = 19)
  (i8 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15)

  ;; addr:1069 hcode base table
  (i8 2 3 7)
)

(func $memcpy (param $dst i32) (param $src i32) (param $dstend i32) (result i32)
  ;; don't write anything if dst >= dstend
  (local.get $dstend)
  (br_if 0 (i32.ge_u (local.get $dst) (local.get $dstend)))
  (loop $copy
    (i32.store8 (local.get $dst) (i32.load8_u (local.get $src)))
    (local.set $src (i32.add (local.get $src) (i32.const 1)))
    (br_if $copy
      (i32.lt_u
        (local.tee $dst (i32.add (local.get $dst) (i32.const 1)))
        (local.get $dstend))))
)

(func $memset (param $val i32) (param $dst i32) (param $dstend i32) (result i32)
  ;; always write at least one byte!
  (i32.store8 (local.get $dst) (local.get $val))
  (call $memcpy
    (i32.add (local.get $dst) (i32.const 1))
    (local.get $dst)
    (local.get $dstend)))

;; Length is a code in range [257,285]. The final length uses the
;; base length from the table below, along with [0,5] extra bits.
;; This is described in RFC1951 using the following table for the
;; extra bits:
;;
;;   [0, 0, 0, 0, 0, 0, 0, 0, 1, 1,
;;    1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
;;    4, 4, 4, 4, 5, 5, 5, 5, 0]
;;
;; And the following table for the base:
;;
;;   [3,   4,  5,   6,   7,   8,   9,  10,  11, 13,
;;    15, 17, 19,  23,  27,  31,  35,  43,  51, 59,
;;    67, 83, 99, 115, 131, 163, 195, 227, 258]
;;
;; If we normalize the code [257,285] to [0,29], then we can
;; determine the extra bits programmatically via:
;;
;;         code <= 3    =>  0
;;    4 <= code <= 28   =>  (code >> 2) - 1
;;         code == 29   =>  0
;;
;; Then the length base can be calculated programmatically via:
;;
;;         code <= 3    =>  3 + code
;;    4 <= code <= 28   =>  3 + ((4 + (code & 3)) << extra_bits)
;;         code == 29   =>  3 + 255

;; Distance is a code in range [0,31]. The final distance uses the base
;; distance from the table below, along with [0,13] extra bits. This is
;; described in RFC1951 using the following table for the extra bits:
;;
;;   [0, 0,  0,  0,  1,  1,  2,  2,  3,  3,
;;    4, 4,  5,  5,  6,  6,  7,  7,  8,  8,
;;    9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
;;
;; And the following table for the base:
;;
;;   [   1,    2,    3,    4,    5,    7,    9,    13,    17,    25,
;;      33,   49,   65,   97,  129,  193,  257,   385,   513,   769,
;;    1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
;;
;; Like length above, we can determine the extra bits programmatically
;; via:
;;
;;         code <= 1    =>  0
;;    2 <= code <= 30   =>  (code >> 1) - 1
;;
;; Then the distance base can be calculated programmatically via:
;;
;;         code <= 1    =>  1 + code
;;    2 <= code <= 30   =>  1 + ((2 + (code & 1)) << extra_bits)

(func $inflate (export "inflate")
      (param $src i32) (param $dst i32) (result i32)
  (local $bfinal i32)
  (local $state i32)
  (local $bit-idx i32)
  (local $read-bit-count i32)
  (local $read-bits i32)
  (local $i i32)
  (local $hlit i32)
  (local $hlit-plus-hdist i32)
  (local $hclen i32)
  (local $huffman-len i32)
  (local $hcend i32)
  (local $addr i32)
  (local $val i32)
  (local $read-code-index i32)
  (local $read-code i32)

  (local $length-dist i32)
  (local $min i32)
  (local $max i32)
  (local $shift i32)

  (local $copy-len i32)

  (local.set $bit-idx (i32.shl (local.get $src) (i32.const 3)))
  (local.set $read-bit-count (i32.const 3))

  loop $main-loop
    block $inc-state
    block $next-code (result i32)
    block $extra-length-dist-bits
    block $calc-length-dist
    block $final-read-dist
    block $final-read-lit
    block $build-huffman (result i32)
    block $dynamic-read-codelen
    block $dynamic-repeat-loop (result i32)
    block $dynamic-repeat-value
    block $dynamic-read-table
    block $read-code
    block $dynamic-header
    block $dynamic
    block $fixed
    block $stored
    block $bfinal-btype

      ;; read n bits
      (local.set $read-bits
        (i32.and
          (i32.shr_u
            (i32.load (i32.shr_u (local.get $bit-idx) (i32.const 3)))
            (i32.and (local.get $bit-idx) (i32.const 7)))
          (i32.sub
            (i32.shl (i32.const 1) (local.get $read-bit-count))
            (i32.const 1))))
      (local.set $bit-idx (i32.add (local.get $bit-idx) (local.get $read-bit-count)))

      (br_table $bfinal-btype            ;; 0
                $dynamic-header          ;; 1
                $dynamic-read-codelen    ;; 2
                $read-code               ;; 3 (for temp huffman)
                $dynamic-repeat-value    ;; 4
                $read-code               ;; 5 (for final huffman literal/length)
                $extra-length-dist-bits  ;; 6
                $read-code               ;; 7 (for final huffman dist)
                $extra-length-dist-bits  ;; 8
        (local.get $state))

    end $bfinal-btype  ;; state 0
      (local.set $bfinal (i32.and (local.get $read-bits) (i32.const 1)))
      ;; 0 => $stored, 1 => $fixed, 2 => $dynamic
      (br_table $stored $fixed $dynamic
        (i32.shr_u (local.get $read-bits) (i32.const 1)))

    end $stored
      ;; TODO
      (return (i32.const 0))

    end $fixed
      (local.set $huffman-len
        (call $memset (i32.const 21)
          (call $memset (i32.const 8)
            (call $memset (i32.const 9)
              (call $memset (i32.const 7)
                (call $memset (i32.const 8)
                  (i32.const 0)
                  (i32.const 144))
                (i32.const 256))
              (i32.const 280))
            (i32.const 288))
          (i32.const 318)))
      (br $build-huffman (i32.const 5))

    end $dynamic
      ;; read 5 + 5 + 4 == 14 bits
      (local.set $read-bit-count (i32.const 14))
      (br $inc-state)  ;; state 0->1

    end $dynamic-header  ;; state 1
      ;; hlit  = 257 + getBits(5)
      ;; hdist =   1 + getBits(5)
      ;; hclen =   4 + getBits(4)
      (local.set $hlit-plus-hdist
        (i32.add
          (i32.add
            (i32.and
              (i32.shr_u (local.get $read-bits) (i32.const 5))
              (i32.const 31))
            (local.tee $hlit
              (i32.add
                (i32.and (local.get $read-bits) (i32.const 31))
                (i32.const 257))))
          (i32.const 1)))
      (local.set $hclen
        (i32.add
          (i32.shr_u (local.get $read-bits) (i32.const 10))
          (i32.const 4)))
      (local.set $huffman-len (i32.const 19))
      ;; read 3 bits * hclen
      (local.set $read-bit-count (i32.const 3))
      (local.set $i (i32.const 0))
      (br $inc-state)

    end $read-code           ;; state 3,5,7
      ;; If we subtract and the code goes negative, then we've found which
      ;; range it belongs to. Otherwise we need to read another bit.
      (br_if $main-loop
        (i32.ge_s
          (local.tee $read-code
            (i32.sub
              ;; shift in lowest bit
              (i32.or
                (i32.shl (local.get $read-code) (i32.const 1))
                (local.get $read-bits))
              ;; read count[++i]
              (i32.load8_u offset=382
                (local.tee $read-code-index
                  (i32.add (local.get $read-code-index) (i32.const 1))))))
          (i32.const 0)))

      ;; add in the offset, and read the code symbol.
      (local.set $read-code
        (i32.load16_u offset=414
          (i32.add
            (i32.load16_u offset=318
              (i32.shl (local.get $read-code-index) (i32.const 1)))
            (i32.shl (local.get $read-code) (i32.const 1)))))

      ;; state == 3  => $dynamic-read-table
      ;; state == 5  => $final-read-lit
      ;; state == 7  => $final-read-dist
      (br_table $dynamic-read-table $final-read-lit $final-read-dist
        (i32.shr_u (i32.sub (local.get $state) (i32.const 3)) (i32.const 1)))

    end $dynamic-read-table
      (if (i32.lt_u (local.get $read-code) (i32.const 16))
        (then
          ;; write literal value to lens. When writing distance values, add 16
          ;; to the length so they are stored in the other tree.
          (local.set $val
            (i32.add
              (local.get $read-code)
              (i32.shl
                (i32.ge_u (local.get $i) (local.get $hlit))
                (i32.const 4))))
          (br $dynamic-repeat-loop (i32.add (local.get $i) (i32.const 1))))
        (else
          ;; 16 => repeat last length, 3 + getBits(2) times
          ;; 17 => put zero length, 3 + getBits(3) times
          ;; 18 => put zero length, 11 + getBits(7) times
          (local.set $val
            (i32.mul
              (i32.eq (local.get $read-code) (i32.const 16))
              (local.get $val)))
          ;; set length to 8 if $read-code==18 (additional +3 happens below)
          (local.set $hcend
            (i32.add
              (local.get $i)
              (i32.shl
                (i32.eq (local.get $read-code) (i32.const 18))
                (i32.const 3))))
          (local.set $read-bit-count
            (i32.load8_u offset=1053 (local.get $read-code))) ;; 1069-16
          (br $inc-state)))  ;; state 3->4

    end $dynamic-repeat-value ;; state 4
      (local.set $read-bit-count (i32.const 1))
      (local.set $state (i32.const 3))

      ;; set hcend (see below)
      (i32.add
        (i32.add (local.get $read-bits) (local.get $hcend))
        (i32.const 3))

      ;; fallthrough
    end $dynamic-repeat-loop
      (local.set $hcend (; (result i32) ;))
      (local.set $i
        (call $memset (local.get $val) (local.get $i) (local.get $hcend)))
      (local.set $read-code-index
        (local.tee $read-code (i32.const 0)))
      (br_if $main-loop (i32.lt_u (local.get $i) (local.get $hlit-plus-hdist)))

      ;; final huffman table is decompressed, so build it.
      (local.set $huffman-len (local.get $hlit-plus-hdist))
      (br $build-huffman (i32.const 5))

    end $dynamic-read-codelen  ;; state 2
      ;; write each length in the order specified by "codelen literals"
      (i32.store8 offset=0
        (i32.load8_u offset=1050 (local.get $i))
        (local.get $read-bits))
      (br_if $main-loop
        (i32.lt_u
          (local.tee $i (i32.add (local.get $i) (i32.const 1)))
          (local.get $hclen)))

      (i32.const 3) ;; go to state 3 after building huffman
      ;; fallthrough
    end $build-huffman
      (local.set $state (; (result i32) ;))
      ;; clear offs + count
      (drop (call $memset (i32.const 0) (i32.const 318) (i32.const 414)))

      (local.set $i (i32.const 0))
      loop $loop
        ;; count[len[i]] += 1
        (i32.store8 offset=382
          (local.tee $addr (i32.load8_u offset=0 (local.get $i)))
          (i32.add
            (i32.load8_u offset=382 (local.get $addr))
            (i32.const 1)))

        (br_if $loop
          (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 1)))
                    (local.get $huffman-len)))
      end

      ;; set offs values
      (local.set $i (i32.const 0))
      loop $loop
        ;; offs[i+1] = offs[i] + 2*count[i/2]
        ;;  2* so that the offset is an offset into syms (u16)
        ;;  i/2 because i is a u16 index, but count is u8 array
        (i32.store16 offset=320
          (local.get $i)
          (i32.add
            (i32.load16_u offset=318 (local.get $i))
            (i32.shl
              (i32.load8_u offset=382 (i32.shr_u (local.get $i) (i32.const 1)))
              (i32.const 1))))

        (br_if $loop
          (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 2)))
                    (i32.const 62)))
      end

      ;; set syms values
      (local.set $i (i32.const 0))
      loop $loop
        ;; syms[offs[len[i]]] = i
        (i32.store16 offset=414
          (local.tee $val
            (i32.load16_u offset=318
              (local.tee $addr
                (i32.shl
                  (i32.load8_u offset=0 (local.get $i))
                  (i32.const 1)))))
          (local.get $i))

        ;; offs[len[i]] += 2
        (i32.store16 offset=318
          (local.get $addr)
          (i32.add (local.get $val) (i32.const 2)))

        (br_if $loop
          (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 1)))
                    (local.get $huffman-len)))
      end
      (br $next-code (local.tee $i (i32.const 0)))

    end $final-read-lit  ;; state 5
      (if (i32.lt_u (local.get $read-code) (i32.const 256))
        (then
          ;; write literal data
          (i32.store8
            (local.get $dst)
            (local.get $read-code))
          (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
          (br $next-code (i32.const 0)))
        (else
          (if (i32.eq (local.get $read-code) (i32.const 256))
            (then
              ;; if bfinal, we're done. Otherwise, read another block.
              (br_if 8 (local.get $dst) (local.get $bfinal))
              (local.set $read-bit-count (i32.const 3))
              (local.set $state (i32.const 0))
              (br $main-loop))
            (else
              ;; write back-reference...
              ;; First, calculate the length.
              (local.set $min (i32.const 3))
              (local.set $max (i32.const 29))
              (local.set $shift (i32.const 2))
              (local.set $read-code
                (i32.sub (local.get $read-code) (i32.const 257)))
              (br $calc-length-dist)))))

    end $final-read-dist  ;; state 7
      (local.set $min (i32.const 1))
      (local.set $max (i32.const 31))
      (local.set $shift (i32.const 1))
      (local.set $read-code
        (i32.sub (local.get $read-code) (local.get $hlit)))

      ;; fallthrough
    end $calc-length-dist  ;; state 5,7
      (local.set $read-bit-count
        (select
            (i32.sub (i32.shr_u (local.get $read-code) (local.get $shift))
                     (i32.const 1))
            (i32.const 0)
            (i32.and (i32.gt_u (local.get $read-code) (local.get $min))
                     (i32.lt_u (local.get $read-code) (local.get $max)))))

      (local.set $length-dist
        (i32.add
            (local.get $min)
            (select
              (select
                (i32.shl
                  (i32.add
                    (i32.add (local.get $min) (i32.const 1))
                    (i32.and (local.get $read-code) (local.get $min)))
                  (local.get $read-bit-count))
                (i32.const 255)
                (i32.lt_u (local.get $read-code) (local.get $max)))
              (local.get $read-code)
              (i32.gt_u (local.get $read-code) (local.get $min)))))

      ;; if the extra bits != 0, then read them, then go to state 6/8
      (br_if $inc-state (local.get $read-bit-count))
      ;; otherwise fallthrough with additional value of 0
      (local.set $read-bits (i32.const 0))

      ;; fallthrough
    end $extra-length-dist-bits  ;; state 5,6,7,8
      (local.set $length-dist
        (i32.add (local.get $length-dist) (local.get $read-bits)))

      (if (result i32) (i32.lt_u (local.get $state) (i32.const 7))
        (then
          (local.set $copy-len (local.get $length-dist))
          (local.set $state (i32.const 7))
          (i32.const 16))  ;; read from the distance tree
        (else
          ;; copy from [dst-dist,dst-dist+len] to [dst,dst+len]
          (local.set $dst
            (call $memcpy
              (local.get $dst)
              (i32.sub (local.get $dst) (local.get $length-dist))
              (i32.add (local.get $dst) (local.get $copy-len))))

          (local.set $state (i32.const 5))
          (i32.const 0)))  ;; read from the lit/len tree

      ;; fallthrough
    end $next-code
      (local.set $read-code-index (; (result i32) ;))
      (local.set $read-bit-count (i32.const 1))
      (local.tee $read-code (i32.const 0))
      (br $main-loop)

    end $inc-state
      (local.set $state (i32.add (local.get $state) (i32.const 1)))
      (br $main-loop)
  end
  unreachable
)
