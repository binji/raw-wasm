(memory (export "mem") 8)
(data (i32.const 1056)
  ;; == Temp huffman data ==
  ;;
  ;; This data is only used while building the huffman tree, and can be reused
  ;; afteward. The `lens` array holds the code lengths of each symbol in the
  ;; range [0,320). This has enough space to include both the literal/length
  ;; huffman tree (256 literals + 32 commands = 288 symbols) and the distance
  ;; huffman tree (32 symbols).
  ;;
  ;; Only 30 of the commands are used (286 and 287 are only needed for the
  ;; fixed huffman tree construction). Similarly, only 30 of the distance
  ;; symbols are used.
  ;;
  ;;     addr:0    lens    (size: 1b x 320 = 320)

  ;; == Persistent huffman data ==
  ;;
  ;; The `offs` array stores offsets into the `syms` table for codes of a given
  ;; length. This is used to place each symbol into the correct location in the
  ;; table. The maximum number of bits in a code is 15, but this table stores
  ;; both the literal/length codes (in range [0,16)) and distance codes (in
  ;; range [16,32)).
  ;;
  ;;     addr:320  offs    (size: 2b x  32 =  64)
  ;;
  ;; The `count` array stores the number of symbols with a given code length.
  ;; Like `offs`, it stores the counts for both the literal/length codes and
  ;; the distance codes.
  ;;
  ;;     addr:384  count   (size: 1b x  32 =  32)
  ;;
  ;; The `syms` array stores a mapping from a code to its symbol.
  ;;
  ;;     addr:416  syms    (size: 2b x 320 = 640)

  ;; == Constant data ==
  ;;
  ;; The `codelen literals` array stores a permutation of the symbol lengths
  ;; for the temporary huffman table (which is used to decode the final huffman
  ;; table).
  ;;
  ;;     addr:1056   codelen literals  (size: 1b x 19 = 19)
  ;;
  (i8 16 17 21 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15)
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
    (local.get $dstend))
)

(func $inflate (export "inflate")
      (param $src i32) (param $dst i32) (result i32)
  (local $state i32)
  (local $bfinal i32)
  (local $src-bit i32)
  (local $bits-to-read i32)
  (local $bits i32)
  (local $code i32)
  (local $src+4 i32)
  (local $i i32)
  (local $hlit i32)
  (local $hlit+hdist i32)
  (local $hclen i32)
  (local $huffman-len i32)
  (local $hcend i32)
  (local $temp-addr i32)
  (local $val i32)
  (local $code-index i32)

  (local $length-dist i32)
  (local $min i32)
  (local $max i32)
  (local $shift i32)
  (local $code>min i32)
  (local $code<max i32)

  (local $copy-len i32)

  (local.set $src-bit
    (i32.shl
      (local.get $src)
      (local.tee $bits-to-read (i32.const 3))))

  loop $main-loop (result i32)
    block $inc-state (result i32)
    block $next-block
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
      (local.set $bits
        (i32.and
          (i32.shr_u
            (i32.load (i32.shr_u (local.get $src-bit) (i32.const 3)))
            (i32.and (local.get $src-bit) (i32.const 7)))
          (i32.sub
            (i32.shl (i32.const 1) (local.get $bits-to-read))
            (i32.const 1))))
      (local.set $src-bit
        (i32.add (local.get $src-bit) (local.get $bits-to-read)))

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
      (local.set $bfinal (i32.and (local.get $bits) (i32.const 1)))
      ;; 0 => $stored, 1 => $fixed, 2 => $dynamic
      (br_table $stored $fixed $dynamic
        (i32.shr_u (local.get $bits) (i32.const 1)))

    end $stored
      ;; copy uncompressed data
      (local.set $dst
        (call $memcpy
          (local.get $dst)
          (local.tee $src+4
            (i32.add
              ;; align src-bit to nearest byte boundary
              (local.tee $src
                (i32.shr_u (i32.add (local.get $src-bit) (i32.const 7))
                           (i32.const 3)))
              (i32.const 4)))
          (i32.add
            (local.get $dst)
            (local.tee $copy-len (i32.load16_u (local.get $src))))))

      ;; skip over uncompressed data
      (local.set $src-bit
        (i32.shl
          (i32.add (local.get $src+4) (local.get $copy-len))
          (i32.const 3)))

      (br $next-block)

    end $fixed
      ;; use fixed huffman tree
      (local.set $huffman-len
        (call $memset (i32.const 21)  ;; 5 + 16
          (call $memset (i32.const 8)
            (call $memset (i32.const 9)
              (call $memset (i32.const 7)
                (call $memset (i32.const 8)
                  (i32.const 0)
                  (i32.const 144))
                (i32.const 256))
              (i32.const 280))
            (i32.const 288))
          (i32.const 320)))
      (br $build-huffman (i32.const 5))

    end $dynamic
      ;; read 5 + 5 + 4 == 14 bits
      (br $inc-state (i32.const 14))  ;; state 0->1

    end $dynamic-header  ;; state 1
      ;; hlit  = 257 + getBits(5)
      ;; hdist =   1 + getBits(5)
      ;; hclen =   4 + getBits(4)
      (local.set $hlit+hdist
        (i32.add
          (i32.add
            (i32.and
              (i32.shr_u (local.get $bits) (i32.const 5))
              (i32.const 31))
            (local.tee $hlit
              (i32.add
                (i32.and (local.get $bits) (i32.const 31))
                (i32.const 257))))
          (i32.const 1)))
      (local.set $hclen
        (i32.add
          (i32.shr_u (local.get $bits) (i32.const 10))
          (i32.const 4)))
      ;; Clear lens array
      (call $memset
        (local.tee $i (i32.const 0))
        (i32.const 0)
        (local.tee $huffman-len (i32.const 22)))
      (br $inc-state (i32.const 3))  ;; read 3 bits * hclen

    end $read-code           ;; state 3,5,7
      ;; If we subtract and the code goes negative, then we've found which
      ;; range it belongs to. Otherwise we need to read another bit.
      (br_if $main-loop
        (i32.ge_s
          (local.tee $code
            (i32.sub
              ;; shift in lowest bit
              (i32.or
                (i32.shl (local.get $code) (i32.const 1))
                (local.get $bits))
              ;; read count[++i]
              (i32.load8_u offset=384
                (local.tee $code-index
                  (i32.add (local.get $code-index) (i32.const 1))))))
          (i32.const 0)))

      ;; add in the offset, and read the code symbol.
      (local.set $code
        (i32.load16_u offset=416
          (i32.add
            (i32.load16_u offset=320
              (i32.shl (local.get $code-index) (i32.const 1)))
            (i32.shl (local.get $code) (i32.const 1)))))

      ;; state == 3  => $dynamic-read-table
      ;; state == 5  => $final-read-lit
      ;; state == 7  => $final-read-dist
      (br_table $dynamic-read-table $final-read-lit $final-read-dist
        (i32.shr_u (i32.sub (local.get $state) (i32.const 3)) (i32.const 1)))

    end $dynamic-read-table
      (if (i32.lt_u (local.get $code) (i32.const 16))
        (then
          ;; write literal value to lens. When writing distance values, add 16
          ;; to the length so they are stored in the other tree.
          (local.set $val
            (i32.add
              (local.get $code)
              (i32.shl
                (i32.ge_u (local.get $i) (local.get $hlit))
                (i32.const 4))))
          (br $dynamic-repeat-loop (i32.add (local.get $i) (i32.const 1)))))

      ;; 16 => repeat last length, 3 + getBits(2) times
      ;; 17 => put zero length, 3 + getBits(3) times
      ;; 21 => put zero length, 11 + getBits(7) times
      (local.set $val
        (i32.mul
          (i32.eq (local.get $code) (i32.const 16))
          (local.get $val)))
      ;; set length to 8 if $code==18 (additional +3 happens below)
      (local.set $hcend
        (i32.add
          (local.get $i)
          (i32.shl
            (i32.eq (local.get $code) (i32.const 21))
            (i32.const 3))))
      ;; set $bits-to-read to code - 14; see table above.
      (br $inc-state (i32.sub (local.get $code) (i32.const 14)))  ;; state 3->4

    end $dynamic-repeat-value ;; state 4
      (local.set $bits-to-read (i32.const 1))
      (local.set $state (i32.const 3))

      ;; set hcend (see below)
      (i32.add
        (i32.add (local.get $bits) (local.get $hcend))
        (i32.const 3))

      ;; fallthrough
    end $dynamic-repeat-loop
      (local.set $hcend (; (result i32) ;))
      (local.set $i
        (call $memset (local.get $val) (local.get $i) (local.get $hcend)))
      (br_if $next-code
        (i32.const 0)
        (i32.lt_u (local.get $i) (local.get $hlit+hdist)))
      ;; (drop)

      ;; final huffman table is decompressed, so build it.
      (local.set $huffman-len (local.get $hlit+hdist))
      (br $build-huffman (i32.const 5))

    end $dynamic-read-codelen  ;; state 2
      ;; write each length in the order specified by "codelen literals"
      (i32.store8 offset=0
        (i32.load8_u offset=1056 (local.get $i))
        (local.get $bits))
      (br_if $main-loop
        (i32.lt_u
          (local.tee $i (i32.add (local.get $i) (i32.const 1)))
          (local.get $hclen)))

      (i32.const 3) ;; go to state 3 after building huffman
      ;; fallthrough
    end $build-huffman
      (local.set $state (; (result i32) ;))
      ;; clear offs + count
      (call $memset (i32.const 0) (i32.const 320) (i32.const 416))
      ;; (drop)

      (local.set $i (local.get $huffman-len))
      loop $loop
        ;; count[len[i]] += 1
        (i32.store8 offset=384
          (local.tee $temp-addr
            (i32.load8_u offset=0
              (local.tee $i (i32.sub (local.get $i) (i32.const 1)))))
          (i32.add
            (i32.load8_u offset=384 (local.get $temp-addr))
            (i32.const 1)))

        (br_if $loop (local.get $i))
      end

      ;; set offs values
      ;; (local.set $i (i32.const 0))
      loop $loop
        ;; offs[i+1] = offs[i] + 2*count[i/2]
        ;;  2* so that the offset is an offset into syms (u16)
        ;;  i/2 because i is a u16 index, but count is u8 array
        (i32.store16 offset=322
          (local.get $i)
          (i32.add
            (i32.load16_u offset=320 (local.get $i))
            (i32.shl
              (i32.load8_u offset=384 (i32.shr_u (local.get $i) (i32.const 1)))
              (i32.const 1))))

        (br_if $loop
          (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 2)))
                    (i32.const 62)))
      end

      ;; set syms values
      (local.set $i (i32.const 0))
      loop $loop
        ;; syms[offs[len[i]]] = i
        (i32.store16 offset=416
          (local.tee $val
            (i32.load16_u offset=320
              (local.tee $temp-addr
                (i32.shl
                  (i32.load8_u offset=0 (local.get $i))
                  (i32.const 1)))))
          (local.get $i))

        ;; offs[len[i]] += 2
        (i32.store16 offset=320
          (local.get $temp-addr)
          (i32.add (local.get $val) (i32.const 2)))

        (br_if $loop
          (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 1)))
                    (local.get $huffman-len)))
      end
      (br $next-code (local.tee $i (i32.const 0)))

    end $final-read-lit  ;; state 5
      (if (i32.lt_u (local.get $code) (i32.const 256))
        (then
          ;; Write literal data
          (i32.store8
            (local.get $dst)
            (local.get $code))
          (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
          (br $next-code (i32.const 0))))

      ;; Finish block if code == 256
      (br_if $next-block (i32.eq (local.get $code) (i32.const 256)))

      ;; Otherwise write back-reference...
      ;; First, calculate the length.
      (local.set $min (i32.const 3))
      (local.set $max (i32.const 29))
      (local.set $shift (i32.const 2))
      (local.set $code (i32.sub (local.get $code) (i32.const 257)))
      (br $calc-length-dist)

    end $final-read-dist  ;; state 7
      ;; Next calculate distance
      (local.set $min
        (local.tee $shift (i32.const 1)))
      (local.set $max (i32.const 31))
      (local.set $code (i32.sub (local.get $code) (local.get $hlit)))

      ;; fallthrough
    end $calc-length-dist  ;; state 5,7

      ;; The length and distance values are specified in RFC1951 using tables,
      ;; but can be computed programmatically using the same expression. If the
      ;; code is normalized so it starts at 0, so that:
      ;;
      ;;   The length code is in the range [0,29]
      ;;   The distance code is in the range [0,30]
      ;;
      ;; The number of extra bits is:
      ;;
      ;;          code <  min  =>  0
      ;;   min <= code <  max  =>  (code >> shift) - 1
      ;;          code == max  =>  0
      ;;
      ;; The base value is:
      ;;
      ;;          code <  min  =>  min + code
      ;;   min <= code <  max  =>  min + ((min + 1 + (code & min)) << extra_bits)
      ;;          code == max  =>  min + 255
      ;;
      ;; (Note that the $max value for distance is deliberately chosen so it
      ;; will never occur.)
      (local.set $length-dist
        (i32.add
          (local.get $min)
          (select
            (select
              (i32.shl
                (i32.add
                  (i32.add (local.get $min) (i32.const 1))
                  (i32.and (local.get $code) (local.get $min)))
                (local.tee $bits-to-read
                  (select
                    (i32.sub
                      (i32.shr_u (local.get $code) (local.get $shift))
                      (i32.const 1))
                    (i32.const 0)
                    (i32.and
                      (local.tee $code>min
                        (i32.gt_u (local.get $code) (local.get $min)))
                      (local.tee $code<max
                        (i32.lt_u (local.get $code) (local.get $max)))))))
              (i32.const 255)
              (local.get $code<max))
            (local.get $code)
            (local.get $code>min))))

      ;; if the extra bits != 0, then read them, then go to state 6/8
      (drop
        (br_if $inc-state (local.get $bits-to-read) (local.get $bits-to-read)))
      ;; otherwise fallthrough with additional value of 0
      (local.set $bits (i32.const 0))

      ;; fallthrough
    end $extra-length-dist-bits  ;; state 5,6,7,8
      (local.set $length-dist
        (i32.add (local.get $length-dist) (local.get $bits)))

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
      (local.set $code-index (; (result i32) ;))
      (local.set $bits-to-read (i32.const 1))
      (local.set $code (i32.const 0))
      (br $main-loop)

    end $next-block
      ;; if this is the final block, we're done. Otherwise, read another block.
      (br_if 2 (local.get $dst) (local.get $bfinal))
      (local.set $bits-to-read (i32.const 3))
      (local.set $state (i32.const 0))
      (br $main-loop)

    end $inc-state
      (local.set $bits-to-read (; (result i32) ;))
      (local.set $state (i32.add (local.get $state) (i32.const 1)))
      (br $main-loop)
  end
)
