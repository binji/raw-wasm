(import "Math" "random" (func $random (result f32)))

;; Memory map:
;;
;; [0x0000 .. 0x00001]  x, y mouse position
;; [0x0002 .. 0x00002]  mouse buttons
;; [0x0003 .. 0x00004]  x, y mouse click position
;; [0x00c0 .. 0x00100]  16 RGBA colors       u32[16]
;; [0x0100 .. 0x00500]  16x16 emojis 4bpp    u8[8][128]
;; [0x0500 .. 0x00550]  8x8 digits 1bpp      u8[10][8]
;; [0x0550 .. 0x00598]  18 match patterns    u32[18]
;; [0x0598 .. 0x00628]  18 shift masks       u64[18]
;; [0x0700 .. 0x00740]  8x8 grid bitmap      u64[8]
;; [0x0900 .. 0x00a00]  current offset  {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x0a00 .. 0x00b00]  start offset    {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x0b00 .. 0x00c00]  end offset      {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x0c00 .. 0x00d00]  time [0..1)     f32[64]
;; [0x0d00 .. 0x01075]  compressed data
;; [0x1100 .. 0x11090]  150x150xRGBA data (4 bytes per pixel)
(memory (export "mem") 2)

(global $score (mut i32) (i32.const 0))
(global $matched (mut i64) (i64.const -1))
(global $state (mut i32) (i32.const 0))  ;; init
(global $animating (mut i32) (i32.const 1))

(global $prev-mouse-bit (mut i64) (i64.const 0))
(global $click-mouse-bit (mut i64) (i64.const 0))

(func (export "run")
  (local $src i32)
  (local $dst i32)
  (local $dist i32)
  (local $copy-end i32)
  (local $byte-or-len i32)
  (local $i i32)
  (local $grid-offset i32)
  (local $random-grid i32)
  (local $t-addr i32)
  (local $i-addr i32)
  (local $a i32)
  (local $mouse-src*4 i32)
  (local $click-mouse-src*4 i32)
  (local $x i32)
  (local $divisor i32)
  (local $mouse-bit i64)
  (local $empty i64)
  (local $idx i64)
  (local $1<<idx i64)
  (local $above-bits i64)
  (local $above-idx i64)
  (local $mouse-dx f32)
  (local $mouse-dy f32)
  (local $t f32)
  (local $mul-t f32)

  ;; clear screen to transparent black
  (loop $loop
    ;; mem[0x1100 + i] = 0
    (i32.store offset=0x1100 (local.get $i) (i32.const 0))

    ;; i += 4
    ;; loop if i < 90000
    (br_if $loop
      (i32.lt_s
        (local.tee $i (i32.add (local.get $i) (i32.const 4)))
        (i32.const 90000))))

  block $done
  block $matched
  block $falling
  block $removing
  block $init
  block $reset-prev-mouse
  block $mouse-down
  block $idle
    (br_table $init $idle $mouse-down $removing $falling (global.get $state))

  end $idle

    ;; Animate mouse-bit scaling up, as long as it isn't the same as
    ;; prev-mouse-bit: mouse-bit & ~prev-mouse-bit
    (call $animate-cells
      (i64.and
        (local.tee $mouse-bit
          (call $get-mouse-bit
            (i32.load8_u (i32.const 0))   ;; mousex
            (i32.load8_u (i32.const 1)))) ;; mousey
        (i64.xor (global.get $prev-mouse-bit) (i64.const -1)))
      (i32.const 0x08_08_fc_fc))

    (global.set $click-mouse-bit (local.get $mouse-bit))

    ;; If the mouse was not clicked, or if it is an invalid cell, then skip.
    (br_if $reset-prev-mouse
      (i32.or
        (i32.eqz (i32.load8_u (i32.const 2)))
        (i64.eqz (local.get $mouse-bit))))

    ;; Save the current mouse x/y.
    (i32.store16 (i32.const 3) (i32.load16_u (i32.const 0)))

    ;; Set the current state to $mouse-down.
    (global.set $state (i32.const 2))

    (br $reset-prev-mouse)

  end $mouse-down

    ;; if abs(mouse-dx) < abs(mouse-dy) ...
    (if (result f32)
        (f32.lt
          (f32.abs
            ;; mouse-dx = mouse-x - mouse-click-x
            (local.tee $mouse-dx
              (f32.convert_i32_s
                (i32.sub (i32.load8_u (i32.const 0))
                         (i32.load8_u (i32.const 3))))))
          (f32.abs
            ;; mouse-dy = mouse-y - mouse-click-y
            (local.tee $mouse-dy
              (f32.convert_i32_s
                (i32.sub (i32.load8_u (i32.const 1))
                         (i32.load8_u (i32.const 4)))))))
      (then
        ;; mouse-dy = copysign(min(abs(mouse-dy), 17), mouse-dy)
        (local.set $mouse-dy
          (f32.copysign
            (f32.min (f32.abs (local.get $mouse-dy)) (f32.const 17))
            (local.get $mouse-dy)))
        ;; mouse-dx = 0
        (f32.const 0))
      (else
        ;; mouse-dy = 0
        (local.set $mouse-dy (f32.const 0))
        ;; mouse-dx = copysign(min(abs(mouse-dx), 17), mouse-dx)
        (f32.copysign
          (f32.min (f32.abs (local.get $mouse-dx)) (f32.const 17))
          (local.get $mouse-dx))))

    (local.set $mouse-src*4
      (call $bit-to-src*4
        (local.tee $mouse-bit
          (call $get-mouse-bit
            (i32.add (i32.trunc_f32_s (local.tee $mouse-dx (; `if` result ;)))
                     (i32.load8_u (i32.const 3)))
            (i32.add (i32.trunc_f32_s (local.get $mouse-dy))
                     (i32.load8_u (i32.const 4)))))))

    ;; end[click-mouse-bit].x = mouse-dx
    ;; end[click-mouse-bit].y = mouse-dy
    (i32.store16 offset=0xb00
      (local.tee $click-mouse-src*4
        (call $bit-to-src*4 (global.get $click-mouse-bit)))
      (i32.or
        (i32.shl
          (i32.trunc_f32_s (local.get $mouse-dy))
          (i32.const 8))
        (i32.trunc_f32_s (local.get $mouse-dx))))

    ;; If mouse-bit != 0 && mouse-bit != click-mouse-bit
    (if (i32.and
          (i32.eqz (i64.eqz (local.get $mouse-bit)))
          (i64.ne (global.get $click-mouse-bit) (local.get $mouse-bit)))
      (then
        ;; end[mouse-bit].x = -mouse-dx
        ;; end[mouse-bit].y = -mouse-dy
        (i32.store16 offset=0xb00
          (local.get $mouse-src*4)
          (i32.or
            (i32.shl
              (i32.trunc_f32_s (f32.neg (local.get $mouse-dy)))
              (i32.const 8))
            (i32.trunc_f32_s (f32.neg (local.get $mouse-dx)))))))

    ;; If the button is no longer pressed, go back to idle.
    (br_if $reset-prev-mouse (i32.load8_u (i32.const 2)))

    (global.set $state (i32.const 1))

    ;; If mouse-bit is not valid or is different from clicked cell, then
    ;; exit the `if`.
    (br_if $reset-prev-mouse
      (i32.or
        (i64.eqz (local.get $mouse-bit))
        (i64.eq (global.get $click-mouse-bit) (local.get $mouse-bit))))

    ;; swap the mouse-bit-mouse-bit bits in all grids.
    (call $swap-all-grids-bits
      (local.get $mouse-bit)
      (global.get $click-mouse-bit))

    (global.set $matched (call $match-all-grids-patterns (i32.const 8)))

    ;; Try to find matches. If none, then reset the swap.
    (if (i64.eqz (global.get $matched))
      (then
        ;; Swap back
        (call $swap-all-grids-bits
          (local.get $mouse-bit)
          (global.get $click-mouse-bit))

        ;; And animate them back to their original place
        (call $animate-cells
          (i64.or (local.get $mouse-bit) (global.get $click-mouse-bit))
          (i32.const 0)))
      (else
        ;; force the cells back to 0,0
        (i32.store16 offset=0x900
          (local.get $mouse-src*4) (i32.const 0))
        (i32.store16 offset=0x900
          (local.get $click-mouse-src*4) (i32.const 0))
        (i32.store16 offset=0xb00
          (local.get $mouse-src*4) (i32.const 0))
        (i32.store16 offset=0xb00
          (local.get $click-mouse-src*4) (i32.const 0))

        (br $matched)))

  end $reset-prev-mouse

    ;; Reset prev-mouse-bit, as long as it isn't the same as mouse-bit:
    ;; prev-mouse-bit & ~mouse-bit
    (call $animate-cells
      (i64.and
        (global.get $prev-mouse-bit)
        (i64.xor (local.get $mouse-bit) (i64.const -1)))
      (i32.const 0))

    (global.set $prev-mouse-bit (local.get $mouse-bit))
    (br $done)

  end $init

    ;; Decompress from [0xd00,0x1075] -> 0xc4.
    ;;
    ;; While src < 0x1075:
    ;;   byte = readbyte()
    ;;   if byte <= 12:
    ;;     len = byte + 3
    ;;     dist = readbyte()
    ;;     copy data from mem[dst-dist:dst-dist+len] to mem[dst:dst+len]
    ;;   else:
    ;;     mem[dst] = byte + 137
    ;;
    (loop $loop
      (if (result i32)
          (i32.le_s
            (local.tee $byte-or-len (i32.load8_u offset=0xd00 (local.get $src)))
            (i32.const 12))
        (then
          ;; back-reference
          (local.set $copy-end
            (i32.add (i32.add (local.get $dst) (local.get $byte-or-len))
                     (i32.const 3)))

          (loop $copy-loop
            (i32.store8 offset=0xc4
              (local.get $dst)
              (i32.load8_u offset=0xc4
                (i32.sub (local.get $dst)
                         (i32.load8_u offset=0xd01 (local.get $src)))))

            (br_if $copy-loop
              (i32.lt_s (local.tee $dst (i32.add (local.get $dst) (i32.const 1)))
                        (local.get $copy-end))))

          ;; src addend
          (i32.const 2))
        (else
          ;; literal data
          (i32.store8 offset=0xc3
            (local.tee $dst (i32.add (local.get $dst) (i32.const 1)))
            (i32.add (local.get $byte-or-len) (i32.const 137)))

          ;; src addend
          (i32.const 1)))

      (br_if $loop
        (i32.lt_s (local.tee $src (i32.add (; result ;) (local.get $src)))
                  (i32.const 0x375))))

    ;; fallthrough

  end $removing

    (br_if $done (global.get $animating))

    ;; Remove the matched cells...
    (loop $loop
      ;; grid-bitmap[grid-offset] &= ~pattern
      (i64.store offset=0x700
        (local.get $grid-offset)
        (i64.and
          (i64.load offset=0x700 (local.get $grid-offset))
          (i64.xor (global.get $matched) (i64.const -1))))

      ;; grid-offset += 8
      ;; loop if grid-offset < 64
      (br_if $loop
        (i32.lt_u
          (local.tee $grid-offset
            (i32.add (local.get $grid-offset) (i32.const 8)))
          (i32.const 64))))

    ;; ... and move down cells to fill the holes
    (local.set $empty (global.get $matched))
    (block $move-down-exit
      (loop $move-down-loop
        ;; Exit the loop if there are no further bits.
        (br_if $move-down-exit (i64.eqz (local.get $empty)))

        (local.set $1<<idx
          (i64.shl
            (i64.const 1)
            ;; Get the index of the lowest set bit
            (local.tee $idx (i64.ctz (local.get $empty)))))

        ;; If there is not a cell above this one...
        (if (i64.eqz
              ;; Find the next cell above that is not empty: invert the empty
              ;; pattern and mask it with a column, shifted by idx.
              (local.tee $above-bits
                (i64.and
                  (i64.xor (local.get $empty) (i64.const -1))
                  (i64.shl (i64.const 0x0101010101010101) (local.get $idx)))))
          (then
            ;; then we need to fill with a new random cell.
            ;;
            ;; random-grid = int(random() * 8) << 3
            ;; grid-bitmap[random-grid] |= (1 << idx)
            (i64.store offset=0x700
              (local.tee $random-grid
                (i32.shl
                  (i32.trunc_f32_u (f32.mul (call $random) (f32.const 8)))
                  (i32.const 3)))
              (i64.or
                (i64.load offset=0x700 (local.get $random-grid))
                (local.get $1<<idx)))

            ;; Set above-idx so it is always the maximum value (used below)
            (local.set $above-idx (i64.add (local.get $idx) (i64.const 56))))
          (else
            ;; If there is cell above, move iti down
            (call $swap-all-grids-bits
              (i64.shl
                (i64.const 1)
                ;; Find the lowest set bit in $above-bits
                (local.tee $above-idx (i64.ctz (local.get $above-bits))))
              (local.get $1<<idx))

            ;; Set above-bit in empty so we will fill it.
            (local.set $empty
              (i64.or (local.get $empty)
                      (i64.shl (i64.const 1) (local.get $above-idx))))))

        ;; Reset the x,w,h to 0, but set the y pixel offset to the y cell
        ;; difference * 17.
        (i64.store32 offset=0x900
          (i32.wrap_i64
            (i64.shl (local.get $idx) (i64.const 2)))
          (i64.shl
            (i64.and
              (i64.mul
                (i64.shr_s
                  (i64.sub (local.get $idx) (local.get $above-idx))
                  (i64.const 3))
                (i64.const 17))
              (i64.const 0xff))
            (i64.const 8)))

        ;; Now animate it back to 0.
        (call $animate-cells (local.get $1<<idx) (i32.const 0))

        ;; Clear this bit (it has now been filled).
        (local.set $empty
          (i64.and
            (local.get $empty)
            (i64.sub (local.get $empty) (i64.const 1))))

        ;; Always loop
        (br $move-down-loop)))

    ;; Set state to $falling
    (global.set $state (i32.const 4))

    (br $done)

  end $falling

    (br_if $done (global.get $animating))

    ;; If there are no matches (including swaps)...
    (if (i64.eqz (call $match-all-grids-patterns (i32.const 72)))
      (then
        ;; ... then reset the entire board.
        (global.set $matched (i64.const -1))

        ;; Reset the score (use -64 since 64 will be added below)
        (global.set $score (i32.const -64)))
      (else
        ;; Otherwise, check whether any new matches (without swaps) occurred.
        (global.set $matched (call $match-all-grids-patterns (i32.const 8)))))

  end $matched

    ;; Add score
    (global.set $score
      (i32.add
        (global.get $score)
        (i32.wrap_i64 (i64.popcnt (global.get $matched)))))

    ;; Animate the matched cells
    (call $animate-cells (global.get $matched) (i32.const 0xf1_f1_08_08))

    ;; If there are new matches, then remove them, otherwise go back to $idle
    (global.set $state
      (select (i32.const 1) (i32.const 3) (i64.eqz (global.get $matched))))

  end $done

  ;; Animate
  ;; mul-t = 1
  (local.set $mul-t (f32.const 1))

  (loop $animate-loop
    ;; ilerp = (a,b,t) => return a + (b - a) * t
    ;; easeOutCubic(t) = t => t * (3 + t * (t - 3))
    ;; current[i] = ilerp(start[i], end[i], easeOutCubic(t))
    (i32.store8 offset=0x900
      (local.get $i-addr)
      (i32.add
        (local.tee $a (i32.load8_s offset=0xa00 (local.get $i-addr)))
        (i32.trunc_f32_s
          (f32.mul
            (f32.convert_i32_s
              (i32.sub
                (i32.load8_s offset=0xb00 (local.get $i-addr))
                (local.get $a)))
            (f32.mul
              ;; t = Math.min(t[i] + speed, 1)
              (local.tee $t
                (f32.min
                  (f32.add
                    (f32.load offset=0xc00 (local.get $t-addr))
                    (f32.const 0.005))
                  (f32.const 1)))
              (f32.add
                (f32.const 3)
                (f32.mul
                  (local.get $t)
                  (f32.sub (local.get $t) (f32.const 3)))))))))
    ;; t[i] = t
    (f32.store offset=0xc00 (local.get $t-addr) (local.get $t))

    ;; mul-t *= t
    (local.set $mul-t (f32.mul (local.get $mul-t) (local.get $t)))

    ;; i-addr += 1
    ;; t-addr = i-addr & ~3
    (local.set $t-addr
      (i32.and
        (local.tee $i-addr (i32.add (local.get $i-addr) (i32.const 1)))
        (i32.const 0xfc)))

    ;; loop if i-addr < 256
    (br_if $animate-loop (i32.lt_s (local.get $i-addr) (i32.const 256))))

  ;; If all t values are 1 (i.e. all animations are finished), then multiplying
  ;; them together will also be 1.
  (global.set $animating (f32.ne (local.get $mul-t) (f32.const 1)))

  (call $draw-grids (i64.const -1))  ;; Mask with all 1s

  ;; Draw the moused-over cell again, so they're on top
  (call $draw-grids (local.get $mouse-bit))

  ;; Draw score
  (local.set $x (i32.const 111))
  (local.set $divisor (i32.const 1000))
  (loop $digit-loop
    (call $draw-sprite
      (local.tee $x (i32.add (local.get $x) (i32.const 8)))
      (i32.const 1)
      (i32.add
        (i32.const 0x400)
        (i32.shl
          (i32.rem_u
            (i32.div_u (global.get $score) (local.get $divisor))
            (i32.const 10))
          (i32.const 3)))
      (i32.const 8) (i32.const 8)
      (i32.const 8) (i32.const 8)
      (i32.const 3) (i32.const 7) (i32.const 1))

    ;; divisor /= 10
    ;; looop if divisor != 0
    (br_if $digit-loop
      (local.tee $divisor (i32.div_u (local.get $divisor) (i32.const 10)))))
)

(func $match-all-grids-patterns (param $last-pattern i32) (result i64)
  (local $result i64)
  (local $grid i64)
  (local $pattern i64)
  (local $shifts i64)
  (local $grid-offset i32)
  (local $i i32)

  (loop $grid-loop
    ;; grid = grids[i]
    (local.set $grid (i64.load offset=0x700 (local.get $grid-offset)))

    ;; i = 0;
    (local.set $i (i32.const 0))

    (loop $pattern-loop
      ;; pattern = match-patterns[i]
      (local.set $pattern (i64.load32_u offset=0x550 (local.get $i)))

      ;; shifts = match-shifts[i]
      (local.set $shifts
        (i64.load offset=0x598 (i32.shl (local.get $i) (i32.const 1))))

      (loop $bit-loop
        ;; if ((shifts & 1) && ((grid & pattern) == pattern)) ...
        (if (i32.and
              (i32.wrap_i64 (i64.and (local.get $shifts) (i64.const 1)))
              (i64.eq (i64.and (local.get $grid) (local.get $pattern))
                      (local.get $pattern)))
          (then
            ;; result |= pattern
            (local.set $result (i64.or (local.get $result) (local.get $pattern)))))

        ;; pattern <<= 1
        (local.set $pattern (i64.shl (local.get $pattern) (i64.const 1)))

        ;; shifts >>= 1
        ;; loop if shifts != 0
        (br_if $bit-loop
          (i32.eqz
            (i64.eqz
              (local.tee $shifts
                (i64.shr_u (local.get $shifts) (i64.const 1)))))))

      ;; i += 4
      ;; loop if i < last-pattern
      (br_if $pattern-loop
        (i32.lt_u
          (local.tee $i (i32.add (local.get $i) (i32.const 4)))
          (local.get $last-pattern))))

    ;; grid-offset += 8
    ;; loop if grid-offset < 64
    (br_if $grid-loop
      (i32.lt_u
        (local.tee $grid-offset (i32.add (local.get $grid-offset) (i32.const 8)))
        (i32.const 64))))

  ;; return result
  (local.get $result)
)

(func $swap-all-grids-bits (param $a i64) (param $b i64)
  (local $grid-offset i32)
  (local $bits i64)
  (local $a|b i64)

  (loop $loop
    ;; if popcnt(bits & (a | b)) == 1  ;; i.e. bits are different
    (if (i64.eq
          (i64.popcnt
            (i64.and
              ;; bits = mem[grid-offset]
              (local.tee $bits
                (i64.load offset=0x700 (local.get $grid-offset)))
              (local.tee $a|b (i64.or (local.get $a) (local.get $b)))))
            (i64.const 1))
      (then
        ;; mem[grid-offset] = bits ^ (a | b)
        (i64.store offset=0x700
          (local.get $grid-offset)
          (i64.xor (local.get $bits) (local.get $a|b)))))

    ;; grid-offset += 8
    ;; loop if grid-offset < 64
    (br_if $loop
      (i32.lt_s
        (local.tee $grid-offset
          (i32.add (local.get $grid-offset) (i32.const 8)))
        (i32.const 64))))
)

(func $get-mouse-bit (param $x i32) (param $y i32) (result i64)
  ;; return ...
  (select
    ;; 1 << ((y / 17) * 8 + (x / 17))
    (i64.shl
      (i64.const 1)
      (i64.extend_i32_u
        (i32.add
          (i32.mul
            (i32.div_s
              ;; y = 142 - y
              (local.tee $y (i32.sub (i32.const 142) (local.get $y)))
              (i32.const 17))
            (i32.const 8))
          (i32.div_s
            ;; x -= 7
            (local.tee $x (i32.sub (local.get $x) (i32.const 7)))
            (i32.const 17)))))
    ;; -1
    (i64.const 0)
    ;; if (x < 136) && (y < 136)
    (i32.and
      (i32.lt_s (local.get $x) (i32.const 136))
      (i32.lt_s (local.get $y) (i32.const 136))))
)

(func $bit-to-src*4 (param $bit i64) (result i32)
  (i32.shl (i32.wrap_i64 (i64.ctz (local.get $bit))) (i32.const 2))
)

(func $animate-cells (param $bits i64) (param $h_w_y_x i32)
  (local $src*4 i32)

  (loop $loop
    ;; Exit the function if there are no further bits.
    (br_if 1 (i64.eqz (local.get $bits)))

    ;; Set the start x/y/w/h to the current x/y/w/h.
    (i32.store offset=0xa00
      (local.tee $src*4 (call $bit-to-src*4 (local.get $bits)))
      (i32.load offset=0x900 (local.get $src*4)))

    ;; Set the destination x/y/w/h
    (i32.store offset=0xb00 (local.get $src*4) (local.get $h_w_y_x))

    ;; Set the time value to 1 - time.
    (f32.store offset=0xc00
      (local.get $src*4)
      (f32.sub
        (f32.const 1)
        (f32.load offset=0xc00 (local.get $src*4))))

    ;; Clear the lowest set bit: bits &= bits - 1
    (local.set $bits
      (i64.and
        (local.get $bits)
        (i64.sub (local.get $bits) (i64.const 1))))

    ;; Always loop
    (br $loop)
  )
)

(func $draw-grids (param $mask i64)
  (local $grid-offset i32)
  (local $cell-idx i32)
  (local $anim-idx i32)
  (local $bits i64)

  (loop $grid-loop
    ;; bits = grid[grid-offset] & mask
    (local.set $bits
      (i64.and
        (i64.load offset=0x700 (local.get $grid-offset))
        (local.get $mask)))

    (block $cell-exit
      (loop $cell-loop
        ;; Break out of the loop if bits == 0
        (br_if $cell-exit (i64.eqz (local.get $bits)))

        ;; Draw the cell at that index
        (call $draw-sprite
          (i32.add
            ;; base x-coordinate: 7 + (idx & 7) * 17
            (i32.add
              (i32.const 7)
              (i32.mul
                (i32.and
                  ;; Get the index of the lowest set bit
                  (local.tee $cell-idx
                    (i32.wrap_i64 (i64.ctz (local.get $bits))))
                  (i32.const 7))
                (i32.const 17)))
            ;; x offset
            (i32.load8_s offset=0x900
              (local.tee $anim-idx
                (i32.shl (local.get $cell-idx) (i32.const 2)))))
          (i32.add
            ;; base y-coordinate: (150 - 17 - 7) - (idx >> 3) * 17
            (i32.sub
              (i32.const 126)
              (i32.mul
                (i32.shr_u (local.get $cell-idx) (i32.const 3))
                (i32.const 17)))
             ;; y offset
            (i32.load8_s offset=0x901 (local.get $anim-idx)))
          ;; src
          (i32.shl (local.get $grid-offset) (i32.const 4))
          ;; sw / sh
          (i32.const 16) (i32.const 16)
          ;; base w
          (i32.add
            (i32.const 16)
            ;; w offset
            (i32.load8_s offset=0x902 (local.get $anim-idx)))
          ;; base h
          (i32.add
            (i32.const 16)
            ;; h offset
            (i32.load8_s offset=0x903 (local.get $anim-idx)))
          (i32.const 1)
          (i32.const 1)
          (i32.const 0xf))

        ;; Clear the lowest set bit: bits &= bits - 1
        (local.set $bits
          (i64.and
            (local.get $bits)
            (i64.sub (local.get $bits) (i64.const 1))))

        ;; Always loop
        (br $cell-loop)))

    ;; grid-offset += 8
    ;; loop if grid-offset < 64
    (br_if $grid-loop
      (i32.lt_s
        (local.tee $grid-offset (i32.add (local.get $grid-offset) (i32.const 8)))
        (i32.const 64))))
)

(func $draw-sprite (param $x i32) (param $y i32)
                   (param $src i32)
                   (param $sw i32) (param $sh i32)
                   (param $dw i32) (param $dh i32)
                   (param $pixels-per-byte i32)
                   (param $src-offset-mask i32)
                   (param $palidx-mask i32)
  (local $i i32)
  (local $j i32)
  (local $x+i i32)
  (local $y+j i32)
  (local $src-offset i32)
  (local $palidx i32)
  (local $dx f32)
  (local $dy f32)

  ;; dx = sw / dw
  (local.set $dx
    (f32.div (f32.convert_i32_s (local.get $sw))
             (f32.convert_i32_s (local.get $dw))))
  ;; dy = sh / dh
  (local.set $dy
    (f32.div (f32.convert_i32_s (local.get $sh))
             (f32.convert_i32_s (local.get $dh))))

  ;; for (j = 0; j < dh; j++)
  (loop $y-loop
    (local.set $i (i32.const 0))
    ;; for (i = 0; i < dw; i++)
    (loop $x-loop
      ;; src-offset = (sw * j * dy) + i * dx
      ;; palidx = (mem[src + (src-offset >> pixels-per-byte)] >>
      ;;           ((src-offset & src-offset-mask) << (3 - pixels-per-byte))) &
      ;;          palidx-mask;
      (local.set $palidx
        (i32.and
          (i32.shr_u
            (i32.load8_u offset=0x100
              (i32.add
                (local.get $src)
                (i32.shr_u
                  (local.tee $src-offset
                    (i32.add
                      (i32.mul
                        (local.get $sw)
                        (i32.trunc_f32_s
                          (f32.mul
                            (f32.convert_i32_s (local.get $j))
                            (local.get $dy))))
                      (i32.trunc_f32_s
                        (f32.mul
                          (f32.convert_i32_s (local.get $i))
                          (local.get $dx)))))
                  (local.get $pixels-per-byte))))
            (i32.shl
              (i32.and (local.get $src-offset) (local.get $src-offset-mask))
              (i32.sub (i32.const 3) (local.get $pixels-per-byte))))
          (local.get $palidx-mask)))

      ;; if (palidx != 0)
      (if (local.get $palidx)
        (then
          ;; skip if the x/y coordinate is out of bounds
          (br_if 0
            (i32.or
              (i32.ge_u
                (local.tee $x+i (i32.add (local.get $x) (local.get $i)))
                (i32.const 150))
              (i32.ge_u
                (local.tee $y+j (i32.add (local.get $y) (local.get $j)))
                (i32.const 150))))

          ;; color = mem[0xc0 + (palidx << 2)]
          ;; mem[0x1100 + (y * 150 + x) * 4] = color
          (i32.store offset=0x1100
            (i32.mul
              (i32.add
                (i32.mul (local.get $y+j) (i32.const 150))
                (local.get $x+i))
              (i32.const 4))
            (i32.load offset=0xc0
              (i32.shl (local.get $palidx) (i32.const 2))))))

      ;; loop if i < w
      (br_if $x-loop
        (i32.lt_s
          ;; i += 1
          (local.tee $i (i32.add (local.get $i) (i32.const 1)))
          (local.get $dw)))
    )
    ;; loop if j < h
    (br_if $y-loop
      (i32.lt_s
        ;; j += 1
        (local.tee $j (i32.add (local.get $j) (i32.const 1)))
        (local.get $dh)))
  )
)

(data (i32.const 0xd00)
  "\56\e8\9d\76\72\69\ad\76\dd\b0\a8\76\01\01\23\a9"
  "\a9\76\da\12\76\76\d6\44\5b\76\50\ce\da\76\42\52"
  "\73\76\ff\cd\b2\76\bc\9f\b3\76\d2\e5\58\76\10\5c"
  "\c7\76\bd\77\d7\76\f7\77\0d\76\77\77\77\88\88\00"
  "\05\00\07\99\99\01\09\87\99\00\01\78\77\77\98\01"
  "\08\89\01\0f\aa\00\02\78\05\08\00\17\01\08\89\98"
  "\9a\01\08\a9\89\98\aa\01\28\01\08\02\01\89\87\a9"
  "\bb\00\01\9a\00\30\01\0f\00\49\98\a9\aa\aa\9a\89"
  "\01\58\a9\01\0f\06\68\05\78\87\01\08\00\18\c8\01"
  "\18\8c\77\88\cc\8c\88\89\c8\cc\88\cc\00\01\c8\01"
  "\05\cc\cc\8c\c9\03\0c\98\89\00\0c\06\08\8c\01\08"
  "\c8\8c\c7\98\c8\98\89\8c\89\7c\87\89\88\00\01\98"
  "\78\0b\80\98\01\80\bb\bb\8b\02\80\a8\01\0f\0c\80"
  "\08\08\00\73\01\09\87\01\73\01\90\02\7b\00\0f\ac"
  "\ca\ac\ca\cc\78\87\cc\aa\cc\00\03\78\c8\00\0d\00"
  "\13\01\88\02\21\c8\03\20\8c\c8\dc\03\08\87\ec\02"
  "\18\78\87\ed\cd\02\08\d7\ee\de\aa\aa\ca\8c\77\00"
  "\08\fa\fa\ca\00\58\ed\8d\fa\ff\8a\00\68\d7\77\f8"
  "\ff\03\80\ee\ee\03\07\dd\dd\01\09\e7\dd\00\01\7e"
  "\77\77\de\01\08\ed\03\0f\00\11\05\08\de\dd\ad\da"
  "\dd\aa\dd\ed\07\08\02\01\06\08\f0\dd\ab\bb\ba\ab"
  "\db\7e\f0\dd\00\ff\aa\da\7e\80\e0\01\10\eb\80\77"
  "\f0\02\3f\80\77\80\01\68\80\80\77\00\09\ee\77\00"
  "\07\77\77\aa\aa\02\80\a7\aa\aa\7a\00\06\7a\01\38"
  "\02\06\1a\21\01\0b\aa\aa\21\01\08\2a\32\32\21\21"
  "\31\32\b2\8a\99\29\32\32\32\99\a8\87\99\02\01\78"
  "\00\08\aa\00\02\09\08\04\18\01\3b\99\78\77\98\a9"
  "\aa\aa\9a\89\77\77\87\99\a9\01\0f\77\77\88\99\99"
  "\88\02\71\88\03\07\77\43\43\03\07\bb\bb\01\09\37"
  "\c0\00\01\83\77\77\13\ad\0d\0d\ad\3d\77\37\dd\ba"
  "\da\00\03\83\37\ad\bb\ab\00\03\83\e3\03\08\3d\53"
  "\b4\bb\ab\00\03\44\53\54\ba\4a\00\03\44\98\a4\a4"
  "\a4\aa\49\49\89\00\80\a9\aa\9a\00\80\88\01\08\89"
  "\00\88\00\81\9a\98\00\18\98\00\9f\98\89\98\99\01"
  "\80\00\08\89\01\80\87\99\03\83\77\77\85\03\07\57"
  "\65\03\08\65\75\65\57\65\65\00\04\75\76\75\76\76"
  "\76\75\66\01\06\00\01\66\57\75\36\32\76\36\32\65"
  "\57\76\76\32\72\32\72\85\00\08\01\01\01\08\36\72"
  "\32\07\08\77\02\31\66\77\00\08\32\32\32\00\08\57"
  "\00\36\72\01\66\65\76\76\03\65\65\04\6c\05\01\a7"
  "\7a\04\08\aa\03\08\b2\aa\02\11\27\32\32\82\02\17"
  "\00\48\01\08\aa\bb\aa\bb\01\19\32\2b\aa\2b\00\2a"
  "\27\32\bb\00\02\00\1f\2a\00\20\00\2a\aa\02\01\7a"
  "\27\b2\aa\bb\bb\bb\aa\aa\00\3e\c2\bb\2b\32\32\03"
  "\1f\00\42\a7\03\20\05\75\b5\f6\da\00\01\f6\b5\a7"
  "\b3\b3\a7\a7\a7\f5\f5\b5\f5\d7\f5\b6\7a\f6\f6\00"
  "\18\ef\af\da\f6\f5\dd\de\da\f6\f6\d7\d7\d7\f6\f6"
  "\7a\b6\f6\d7\f6\b6\b3\b5\7e\b6\f6\00\30\f6\f6\a7"
  "\8f\8f\83\83\83\93\b5\00\0d\00\03\00\30\f6\f5\a7"
  "\b5\95\7e\00\54\78\78\78\77\7a\7b\77\77\7c\79\77"
  "\77\7d\78\77\77\7b\00\6e\79\7c\00\18\7d\77\77\01"
  "\cb\84\02\24\79\77\78\79\78\77\79\00\2c\79\02\08"
  "\01\10\00\04\78\03\03\b6\04\01\76\02\01\77\77\04"
  "\0f\0c\08\0c\08\08\08\96\0c\01\f6\02\01\77\77\0c"
  "\08\0c\08\07\08\04\77\02\08\76"
)
