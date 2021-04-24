(import "Math" "random" (func $random (result f32)))

;; Memory map:
;;
;; [0x0000 .. 0x00001]  x, y mouse position
;; [0x0002 .. 0x00002]  mouse buttons
;; [0x0003 .. 0x00004]  x, y mouse click position
;; [0x00c0 .. 0x00100]  16 RGBA colors       u32[16]
;; [0x0100 .. 0x00500]  16x16 emojis 4bpp    u8[8][128]
;; [0x0500 .. 0x00550]  8x8 digits 1bpp      u8[10][8]
;; [0x0550 .. 0x00578]  gameover 1bpp        u8[5][8]
;; [0x0578 .. 0x005c0]  18 match patterns    u32[18]
;; [0x05c0 .. 0x00650]  18 shift masks       u64[18]
;; [0x0700 .. 0x00740]  8x8 grid bitmap      u64[8]
;; [0x0900 .. 0x00a00]  current offset  {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x0a00 .. 0x00b00]  start offset    {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x0b00 .. 0x00c00]  end offset      {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x0c00 .. 0x00d00]  time [0..1)     f32[64]
;; [0x0d00 .. 0x0109c]  compressed data
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
  block $gameover
  block $falling
  block $removing
  block $init
  block $reset-prev-mouse
  block $reset-all-mouse
  block $mouse-down
  block $idle
    (br_table $init $idle $mouse-down $removing $falling $gameover
      (global.get $state))

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

    ;; If mouse-bit is valid
    (if (i32.eqz (i64.eqz (local.get $mouse-bit)))
      (then
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

        ;; If mouse-bit != click-mouse-bit
        (if (i64.ne (global.get $click-mouse-bit) (local.get $mouse-bit))
          (then
            ;; end[mouse-bit].x = -mouse-dx
            ;; end[mouse-bit].y = -mouse-dy
            (i32.store16 offset=0xb00
              (local.get $mouse-src*4)
              (i32.or
                (i32.shl
                  (i32.trunc_f32_s (f32.neg (local.get $mouse-dy)))
                  (i32.const 8))
                (i32.trunc_f32_s (f32.neg (local.get $mouse-dx)))))))))

    ;; Skip the following if the button is still pressed.
    (br_if $reset-prev-mouse (i32.load8_u (i32.const 2)))

    (global.set $state (i32.const 1))

    ;; Skip the following if mouse-bit is not valid or is different from
    ;; the clicked cell. Since we know that the button was released, we branch
    ;; to $reset-all-mouse, which will reset the clicked mouse too.
    (br_if $reset-all-mouse
      (i32.or
        (i64.eqz (local.get $mouse-bit))
        (i64.eq (global.get $click-mouse-bit) (local.get $mouse-bit))))

    ;; swap the mouse-bit and click-mouse-bit bits in all grids.
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
          (global.get $click-mouse-bit)))
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

  ;; fallthrough

  end $reset-all-mouse

  ;; Animate mouse and click-mouse cells back to their original place
  (call $animate-cells
    (i64.or (local.get $mouse-bit) (global.get $click-mouse-bit))
    (i32.const 0))

  ;; fallthrough

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

    ;; Decompress from [0xd00,0x109c] -> 0xc4.
    ;;
    ;; While src < 0x109c:
    ;;   byte = readbyte()
    ;;   if byte <= 7:
    ;;     len = byte + 3
    ;;     dist = readbyte()
    ;;     copy data from mem[dst-dist:dst-dist+len] to mem[dst:dst+len]
    ;;   else:
    ;;     mem[dst] = byte + 230
    ;;
    (loop $loop
      (if (result i32)
          (i32.le_s
            (local.tee $byte-or-len (i32.load8_u offset=0xd00 (local.get $src)))
            (i32.const 7))
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
            (i32.add (local.get $byte-or-len) (i32.const 230)))

          ;; src addend
          (i32.const 1)))

      (br_if $loop
        (i32.lt_s (local.tee $src (i32.add (; result ;) (local.get $src)))
                  (i32.const 0x39c))))

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

    ;; Check whether any new matches (without swaps) occurred.
    (global.set $matched (call $match-all-grids-patterns (i32.const 8)))

    ;; If there are any matches (including swaps), then keep going.
    (br_if $matched
      (i32.eqz (i64.eqz (call $match-all-grids-patterns (i32.const 72)))))

    ;; otherwise fallthrough to gameover, with a brief animation.
    (call $animate-cells (i64.const -1) (i32.const 0x04_04_fe_fe))
    (global.set $state (i32.const 5))

  end $gameover

    ;; draw game over sprite
    (call $draw-sprite
      (i32.const 8) (i32.const 1)
      (i32.const 0x450)
      (i32.const 40) (i32.const 8)
      (i32.const 80) (i32.const 8)
      (i32.const 3) (i32.const 7) (i32.const 1))

    ;; don't reset until animation is finished and mouse is clicked
    (br_if $done (i32.or (global.get $animating)
                         (i32.eqz (i32.load8_u (i32.const 2)))))

    ;; Reset the entire board.
    (global.set $matched (i64.const -1))

    ;; Reset the score (use -64 since 64 will be added below)
    (global.set $score (i32.const -64))

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
      (local.set $pattern (i64.load32_u offset=0x578 (local.get $i)))

      ;; shifts = match-shifts[i]
      (local.set $shifts
        (i64.load offset=0x5c0 (i32.shl (local.get $i) (i32.const 1))))

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
              ;; y = 147 - y
              (local.tee $y (i32.sub (i32.const 147) (local.get $y)))
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
      (i32.lt_u (local.get $x) (i32.const 136))
      (i32.lt_u (local.get $y) (i32.const 136))))
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
            ;; base y-coordinate: (150 - 17 - 2) - (idx >> 3) * 17
            (i32.sub
              (i32.const 131)
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
  "\f9\8b\40\19\15\0c\50\19\80\53\4b\19\01\01\c6\4c"
  "\4c\19\7d\b5\19\19\79\e7\fe\19\f3\71\7d\19\e5\f5"
  "\16\19\a2\70\55\19\5f\42\56\19\75\88\fb\19\b3\ff"
  "\6a\19\60\1a\7a\19\9a\1a\b0\19\1a\1a\1a\2b\2b\00"
  "\05\00\07\3c\3c\01\09\2a\3c\00\01\1b\1a\1a\3b\01"
  "\08\2c\01\0f\4d\00\02\1b\05\08\00\17\01\08\2c\3b"
  "\3d\01\08\4c\2c\3b\4d\01\28\01\08\02\01\2c\2a\4c"
  "\5e\00\01\3d\00\30\01\0f\00\49\3b\4c\4d\4d\3d\2c"
  "\01\58\4c\01\0f\06\68\05\78\2a\01\08\00\18\6b\01"
  "\18\2f\1a\2b\6f\2f\2b\2c\6b\6f\2b\6f\00\01\6b\01"
  "\05\6f\6f\2f\6c\03\0c\3b\2c\00\0c\06\08\2f\01\08"
  "\6b\2f\6a\3b\6b\3b\2c\2f\2c\1f\2a\2c\2b\00\01\3b"
  "\1b\07\80\01\80\3b\01\80\5e\5e\2e\02\80\4b\01\0f"
  "\07\80\05\f8\05\08\00\73\01\09\2a\01\73\01\90\02"
  "\7b\00\0f\4f\6d\4f\6d\6f\1b\2a\6f\4d\6f\00\03\1b"
  "\6b\00\0d\00\13\01\88\02\21\6b\03\20\2f\6b\7f\03"
  "\08\2a\8f\02\18\1b\2a\90\70\02\08\7a\91\81\4d\4d"
  "\6d\2f\1a\00\08\9d\9d\6d\00\58\90\30\9d\a2\2d\00"
  "\68\7a\1a\9b\a2\03\80\91\91\03\07\80\80\01\09\8a"
  "\80\00\01\21\1a\1a\81\01\08\90\03\0f\00\11\05\08"
  "\81\80\50\7d\80\4d\80\90\07\08\02\01\06\08\93\80"
  "\4e\5e\5d\4e\7e\21\93\80\00\ff\4d\7d\21\23\83\01"
  "\10\8e\23\1a\93\02\3f\23\1a\23\01\68\23\23\1a\00"
  "\09\91\1a\00\07\1a\1a\4d\4d\02\80\4a\4d\4d\1d\00"
  "\06\1d\01\38\02\06\bd\c4\01\0b\4d\4d\c4\01\08\cd"
  "\d5\d5\c4\c4\d4\d5\55\2d\3c\cc\d5\d5\d5\3c\4b\2a"
  "\3c\02\01\1b\00\08\4d\00\02\07\08\06\18\01\3b\3c"
  "\1b\1a\3b\4c\4d\4d\3d\2c\1a\1a\2a\3c\4c\01\0f\1a"
  "\1a\2b\3c\3c\2b\02\71\2b\03\07\1a\e6\e6\03\07\5e"
  "\5e\01\09\da\63\00\01\26\1a\1a\b6\50\b0\b0\50\e0"
  "\1a\da\80\5d\7d\00\03\26\da\50\5e\4e\00\03\26\86"
  "\03\08\e0\f6\57\5e\4e\00\03\e7\f6\f7\5d\ed\00\03"
  "\e7\3b\47\47\47\4d\ec\ec\2c\00\80\4c\4d\3d\00\80"
  "\2b\01\08\2c\00\88\00\81\3d\3b\00\18\3b\00\9f\3b"
  "\2c\3b\3c\01\80\00\08\2c\01\80\2a\3c\03\83\1a\1a"
  "\28\03\07\fa\08\03\08\08\18\08\fa\08\08\00\04\18"
  "\19\18\19\19\19\18\09\01\06\00\01\09\fa\18\d9\d5"
  "\19\d9\d5\08\fa\19\19\d5\15\d5\15\28\00\08\01\01"
  "\01\08\d9\15\d5\07\08\1a\02\31\09\1a\00\08\d5\d5"
  "\d5\00\08\fa\00\36\15\01\66\08\19\19\03\65\08\04"
  "\6c\05\01\4a\1d\04\08\4d\03\08\55\4d\02\11\ca\d5"
  "\d5\25\02\17\00\48\01\08\4d\5e\4d\5e\01\19\d5\ce"
  "\4d\ce\00\2a\ca\d5\5e\00\02\00\1f\cd\00\20\00\2a"
  "\4d\02\01\1d\ca\55\4d\5e\5e\5e\4d\4d\00\3e\65\5e"
  "\ce\d5\d5\03\1f\00\42\4a\03\20\05\75\58\99\7d\00"
  "\01\99\58\4a\56\56\4a\4a\4a\98\98\58\98\7a\98\59"
  "\1d\99\99\00\18\92\52\7d\99\98\80\81\7d\99\99\7a"
  "\7a\7a\99\99\1d\59\99\7a\99\59\56\58\21\59\99\00"
  "\30\99\99\4a\32\32\26\26\26\36\58\00\0d\00\03\00"
  "\30\99\98\4a\58\38\a8\f3\38\6d\91\f9\15\b8\71\11"
  "\5b\c4\9c\6e\ab\f7\c5\b8\6e\11\f7\a5\b8\6e\91\6b"
  "\a4\00\0f\79\a4\b8\91\b1\68\a4\38\3d\b1\21\00\7c"
  "\1b\1b\1b\1a\1d\1e\1a\1a\1f\1c\1a\1a\20\1b\1a\1a"
  "\1e\00\96\1c\1f\00\18\20\1a\1a\01\f3\27\02\24\1c"
  "\1a\1b\1c\1b\1a\1c\00\2c\1c\02\08\01\10\00\04\1b"
  "\03\03\59\04\01\19\02\01\1a\1a\04\0f\07\08\07\08"
  "\07\08\07\08\1a\39\07\01\02\01\99\02\01\1a\1a\07"
  "\08\07\08\07\08\07\08\04\77\02\08\19"
)
