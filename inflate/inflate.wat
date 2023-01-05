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
  ;; table). RFC1951 uses 18 instead of 21 below, but it's convenient to use 21
  ;; here so we can easily convert from code [16,17,18] to the number of
  ;; additional bits they need to read [2,3,7].
  ;;
  ;;     addr:1056   codelen literals  (size: 1b x 19 = 19)
  ;;
  (i8 16 17 21 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1 15)
)

;; Copy from ($dstend-$dst) bytes from $src to $dst. This deliberately does not
;; handle overlap, so it can be used to duplicate bytes (as required by
;; RFC1951).
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

;; Set at ($dstend-$dst) bytes to $val. This will always write at least one
;; byte!
(func $memset (param $val i32) (param $dst i32) (param $dstend i32) (result i32)
  (i32.store8 (local.get $dst) (local.get $val))
  (call $memcpy
    (i32.add (local.get $dst) (i32.const 1))
    (local.get $dst)
    (local.get $dstend))
)

;; Inflate a "raw" (i.e. no-gzip/zip header) DEFLATE encoded stream at $src,
;; and write the output to $dst. Returns the address of the end of output.
(func $inflate (export "inflate")
      (param $src i32) (param $dst i32) (result i32)
  (local $state i32)   ;; Current state of the decoder. See the br_table below.
  (local $bfinal i32)  ;; Non-zero if this is the final block to decode.
  (local $src-bit i32) ;; Current source location, as a bit index.
  (local $bits-to-read i32)  ;; Number of source bits to read (must be <25)
  (local $bits i32)          ;; Current bits that were read.
  (local $code i32)          ;; Current code that was decoded.
  (local $src+4 i32)         ;; Temp. memory to store $src + 4.
  (local $i i32)             ;; Temp. index, used when building huffman tables.
  (local $hlit i32)          ;; Number of huffman literals.
  (local $hlit+hdist i32)    ;; Number of huffman literals and distances.
  (local $hclen i32)         ;; Number of huffman code lengths codes.
  (local $huffman-len i32)   ;; Size of the huffman array.
  (local $hcend i32)         ;; Ending index when writing repeated huffman codes.
  (local $temp-addr i32)     ;; Temp. address used when building huffman tables.
  (local $val i32)           ;; Temp. value used when building huffman tables.
  (local $code-index i32)    ;; Current length index when decoding $code.

  (local $length-dist i32)   ;; Decoded length/distance value.
  (local $min i32)           ;; Minimum code used for length/dist calculation.
  (local $max i32)           ;; Maximum code used for length/dist calculation.
  (local $shift i32)         ;; Shift value used for length/dist calculation.
  (local $code>min i32)      ;; Temp. value storing whether $code > $min.
  (local $code<max i32)      ;; Temp. value storing whether $code < $max.

  (local $copy-len i32)      ;; Number of bytes to copy in back-reference.

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
      ;; Read $bits-to-read bits, and store them in $bits.
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
      ;; $bits contains 3 bits; the low bit is bfinal, and the top two bits are
      ;; btype.
      (local.set $bfinal (i32.and (local.get $bits) (i32.const 1)))
      ;; 0 => $stored, 1 => $fixed, 2 => $dynamic
      (br_table $stored $fixed $dynamic
        (i32.shr_u (local.get $bits) (i32.const 1)))

    end $stored
      ;; btype==0; copy uncompressed data. The source address is first aligned
      ;; to the nearest byte. It is then followed by two 16-bit values: LEN and
      ;; NLEN. LEN is the length of the uncompressed data in bytes, and NLEN is
      ;; LEN's one's complement.
      (local.set $dst
        (call $memcpy
          (local.get $dst)
          (local.tee $src+4
            (i32.add
              ;; Align src-bit to nearest byte boundary.
              (local.tee $src
                (i32.shr_u (i32.add (local.get $src-bit) (i32.const 7))
                           (i32.const 3)))
              (i32.const 4)))
          (i32.add
            (local.get $dst)
            (local.tee $copy-len (i32.load16_u (local.get $src))))))

      ;; Skip over uncompressed data.
      (local.set $src-bit
        (i32.shl
          (i32.add (local.get $src+4) (local.get $copy-len))
          (i32.const 3)))

      (br $next-block)

    end $fixed
      ;; btype==1; use fixed huffman tree. The lengths are encoded as follows:
      ;;
      ;;   range    len
      ;;   ============
      ;;   [  0,144)  8
      ;;   [144,256)  9
      ;;   [256,280)  7
      ;;   [280,288)  8
      ;;   [288,320)  5 + 16
      ;;
      ;; The codes from 288 through 320 are used for the distance codes, and
      ;; have 16 added to their length so they can be encoded in the same
      ;; huffman table.

      (local.set $huffman-len
        (call $memset (i32.const 21)  ;; 5 + 16
          (call $memset (i32.const 8)
            (call $memset (i32.const 7)
              (call $memset (i32.const 9)
                (call $memset (i32.const 8)
                  (i32.const 0)
                  (i32.const 144))
                (i32.const 256))
              (i32.const 280))
            (local.tee $hlit (i32.const 288)))
          (i32.const 320)))
      (br $build-huffman (i32.const 5))

    end $dynamic
      ;; Read 5 + 5 + 4 == 14 bits (see $dynamic-header below).
      (br $inc-state (i32.const 14))  ;; state 0->1

    end $dynamic-header  ;; state 1
      ;; hlit  = 257 + getBits(5)   Number of literal codes used
      ;; hdist =   1 + getBits(5)   Number of distance codes used
      ;; hclen =   4 + getBits(4)   Number of code length codes used
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

      ;; Add in the offset, and read the code symbol.
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
      ;; Values 0..15 are encoded as a literal length.
      (if (i32.lt_u (local.get $code) (i32.const 16))
        (then
          ;; When writing distance values, add 16 to the length so they are
          ;; stored in the "distance" tree instead of the "literal/length"
          ;; tree.
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
      ;; set length to 8 if $code==21 (the additional +3 happens below)
      (local.set $hcend
        (i32.add
          (local.get $i)
          (i32.shl
            (i32.eq (local.get $code) (i32.const 21))
            (i32.const 3))))
      ;; Set $bits-to-read to code - 14; see table above.
      (br $inc-state (i32.sub (local.get $code) (i32.const 14)))  ;; state 3->4

    end $dynamic-repeat-value ;; state 4
      ;; Set up to read another code in state 3.
      (local.set $bits-to-read (i32.const 1))
      (local.set $state (i32.const 3))

      ;; Set hcend (see below). All repeated codes add +3 (and code 21 adds
      ;; +11, and +8 has already been added above).
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

      ;; Final huffman table lengths have now been decoded, so build final
      ;; huffman table.
      (local.set $huffman-len (local.get $hlit+hdist))
      (br $build-huffman (i32.const 5))

    end $dynamic-read-codelen  ;; state 2
      ;; Write each length in the order specified by "codelen literals".
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

      ;; Calculate the number of codes with a given bit length, and store them
      ;; in the count array.
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

      ;; Calculate the offsets into the final symbol table of codes of a given
      ;; bit length.

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

      ;; Fill in the symbols array, given the offsets calculated above.
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
      ;; $code has the currently decoded code. If it is < 256, then it is a
      ;; literal value and can be written directly to the output.
      (if (i32.lt_u (local.get $code) (i32.const 256))
        (then
          ;; Write literal data
          (i32.store8
            (local.get $dst)
            (local.get $code))
          (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
          (br $next-code (i32.const 0))))

      ;; Finish the block if $code == 256
      (br_if $next-block (i32.eq (local.get $code) (i32.const 256)))

      ;; Otherwise the code is a back-reference...
      ;; First, calculate the length.
      (local.set $min (i32.const 3))
      (local.set $max (i32.const 28))
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

      ;; If state is 5 or 6, then we just calculated the length. If state is 7
      ;; or 8, then we just calculated the distance.
      (if (result i32) (i32.lt_u (local.get $state) (i32.const 7))
        (then
          ;; Store the length in $copy-len, and read the distance code.
          (local.set $copy-len (local.get $length-dist))
          (local.set $state (i32.const 7))
          (i32.const 16))  ;; read from the distance tree
        (else
          ;; Copy from [dst-dist,dst-dist+len] to [dst,dst+len]
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
      ;; If this is the final block, we're done. Otherwise, read another block.
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
