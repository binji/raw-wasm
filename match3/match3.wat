(import "Math" "random" (func $random (result f32)))

;; Memory map:
;;
;; [0x00000 .. 0x00001]  x, y mouse position
;; [0x00002 .. 0x00002]  mouse buttons
;; [0x00003 .. 0x00004]  x, y mouse click position
;; [0x000c0 .. 0x00100]  16 RGBA colors       u32[16]
;; [0x00100 .. 0x00500]  16x16 emojis 4bpp    u8[8][128]
;; [0x00500 .. 0x00550]  8x8 digits 1bpp      u8[10][8]
;; [0x00550 .. 0x00598]  18 match patterns    u32[18]
;; [0x00598 .. 0x00628]  18 shift masks       u64[18]
;; [0x03000 .. 0x03040]  8x8 grid bitmap   u64[8]
;; [0x03200 .. 0x03300]  current offset  {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x03300 .. 0x03400]  start offset    {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x03400 .. 0x03500]  end offset      {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x03500 .. 0x03600]  time [0..1)     f32[64]
;; [0x10000 .. 0x25f90]  150x150xRGBA data (4 bytes per pixel)
(memory (export "mem") 3)

(global $score (mut i32) (i32.const 0))
(global $matched (mut i64) (i64.const -1))
(global $state (mut i32) (i32.const 2))  ;; removing
(global $animating (mut i32) (i32.const 1))

(global $prev-mouse-bit (mut i64) (i64.const 0))
(global $click-mouse-bit (mut i64) (i64.const 0))

(func (export "run")
  (local $i i32)
  (local $grid-offset i32)
  (local $idx*4 i32)
  (local $random-grid i32)
  (local $t-addr i32)
  (local $i-addr i32)
  (local $a i32)
  (local $mouse-bit i64)
  (local $empty i64)
  (local $idx i64)
  (local $above-bits i64)
  (local $above-idx i64)
  (local $mouse-dx f32)
  (local $mouse-dy f32)
  (local $t f32)
  (local $mul-t f32)

  ;; clear screen to transparent black
  (loop $loop
    ;; mem[0x10000 + i] = 0
    (i32.store offset=0x10000 (local.get $i) (i32.const 0))

    ;; i += 4
    ;; loop if i < 90000
    (br_if $loop
      (i32.lt_s
        (local.tee $i (i32.add (local.get $i) (i32.const 4)))
        (i32.const 90000))))

  block $done
  block $falling
  block $removing
  block $reset-prev-mouse
  block $mouse-down
  block $idle
    (br_table $idle $mouse-down $removing $falling (global.get $state))

  end $idle

    (local.set $mouse-bit
      (call $get-mouse-bit
        (i32.load8_u (i32.const 0))   ;; mousex
        (i32.load8_u (i32.const 1)))) ;; mousey

    ;; Animate mouse-bit scaling up, as long as it isn't the same as
    ;; prev-mouse-bit: mouse-bit & ~prev-mouse-bit
    (call $animate-cells
      (i64.and
        (local.get $mouse-bit)
        (i64.xor (global.get $prev-mouse-bit) (i64.const -1)))
      (i32.const 0x08_08_fc_fc))

    ;; If the mouse was clicked, and it is on a valid cell...
    (if (i32.and
          (i32.load8_u (i32.const 2))
          (i64.ne (local.get $mouse-bit) (i64.const 0)))
      (then
        ;; Save the current mouse x/y.
        (i32.store16 (i32.const 3) (i32.load16_u (i32.const 0)))

        ;; Set the current state to $mouse-down.
        (global.set $state (i32.const 1))))

    (global.set $click-mouse-bit (local.get $mouse-bit))
    (br $reset-prev-mouse)

  end $mouse-down

    ;; if abs(mouse-dx) < abs(mouse-dy) ...
    (if (f32.lt
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
        ;; mouse-dx = 0
        (local.set $mouse-dx (f32.const 0))
        ;; mouse-dy = copysign(min(abs(mouse-dy), 17), mouse-dy)
        (local.set $mouse-dy
          (f32.copysign
            (f32.min (f32.abs (local.get $mouse-dy)) (f32.const 17))
            (local.get $mouse-dy))))
      (else
        ;; mouse-dy = 0
        (local.set $mouse-dy (f32.const 0))
        ;; mouse-dx = copysign(min(abs(mouse-dx), 17), mouse-dx)
        (local.set $mouse-dx
          (f32.copysign
            (f32.min (f32.abs (local.get $mouse-dx)) (f32.const 17))
            (local.get $mouse-dx)))))

    (local.set $mouse-bit
      (call $get-mouse-bit
        (i32.add (i32.trunc_f32_s (local.get $mouse-dx))
                 (i32.load8_u (i32.const 3)))
        (i32.add (i32.trunc_f32_s (local.get $mouse-dy))
                 (i32.load8_u (i32.const 4)))))

    ;; end[click-mouse-bit].x = mouse-dx
    ;; end[click-mouse-bit].y = mouse-dy
    (i32.store16 offset=0x3400
      (call $bit-to-src*4 (global.get $click-mouse-bit))
      (i32.or
        (i32.shl
          (i32.trunc_f32_s (local.get $mouse-dy))
          (i32.const 8))
        (i32.trunc_f32_s (local.get $mouse-dx))))

    ;; If mouse-bit != 0 && mouse-bit != click-mouse-bit
    (if (i32.and
          (i64.ne (local.get $mouse-bit) (i64.const 0))
          (i64.ne (global.get $click-mouse-bit) (local.get $mouse-bit)))
      (then
        ;; end[mouse-bit].x = -mouse-dx
        ;; end[mouse-bit].y = -mouse-dy
        (i32.store16 offset=0x3400
          (call $bit-to-src*4 (local.get $mouse-bit))
          (i32.or
            (i32.shl
              (i32.trunc_f32_s (f32.neg (local.get $mouse-dy)))
              (i32.const 8))
            (i32.trunc_f32_s (f32.neg (local.get $mouse-dx)))))))

    ;; If the button is no longer pressed, go back to idle.
    (if (i32.eqz (i32.load8_u (i32.const 2)))
      (then
        (global.set $state (i32.const 0))

        ;; If mouse-bit is valid and is different from clicked cell...
        (if (i32.and
              (i64.ne (local.get $mouse-bit) (i64.const 0))
              (i64.ne (global.get $click-mouse-bit) (local.get $mouse-bit)))
          (then
            ;; swap the mouse-bit-mouse-bit bits in all grids.
            (call $swap-all-grids-bits
              (local.get $mouse-bit)
              (global.get $click-mouse-bit))

            (global.set $matched (call $match-all-grids-patterns (i32.const 8)))

            ;; Add score
            (global.set $score
              (i32.add
                (global.get $score)
                (i32.wrap_i64 (i64.popcnt (global.get $matched)))))

            ;; Try to find matches. If none, then reset the swap.
            (if (i64.ne (global.get $matched) (i64.const 0))
              (then
                ;; force the cells back to 0,0
                (i32.store16 offset=0x3200
                  (call $bit-to-src*4 (local.get $mouse-bit))
                  (i32.const 0))
                (i32.store16 offset=0x3200
                  (call $bit-to-src*4 (global.get $click-mouse-bit))
                  (i32.const 0))
                (i32.store16 offset=0x3400
                  (call $bit-to-src*4 (local.get $mouse-bit))
                  (i32.const 0))
                (i32.store16 offset=0x3400
                  (call $bit-to-src*4 (global.get $click-mouse-bit))
                  (i32.const 0))

                ;; Animate the matched cells
                (call $animate-cells
                  (global.get $matched)
                  (i32.const 0xf1_f1_08_08))

                ;; Set the current state to $removing
                (global.set $state (i32.const 2)))
              (else
                ;; Swap back
                (call $swap-all-grids-bits
                  (local.get $mouse-bit)
                  (global.get $click-mouse-bit))

                ;; And animate them back to their original place
                (call $animate-cells
                  (i64.or (local.get $mouse-bit) (global.get $click-mouse-bit))
                  (i32.const 0))))

          ))
        ))

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

  end $removing

    (br_if $done (global.get $animating))

    ;; Remove the matched cells...
    (loop $loop
      ;; grid-bitmap[grid-offset] &= ~pattern
      (i64.store offset=0x3000
        (local.get $grid-offset)
        (i64.and
          (i64.load offset=0x3000 (local.get $grid-offset))
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

        (local.set $idx*4
          (i32.wrap_i64
            (i64.shl
              ;; Get the index of the lowest set bit
              (local.tee $idx (i64.ctz (local.get $empty)))
              (i64.const 2))))

        ;; Find the lowest set bit in $above-bits
        (local.set $above-idx
          (i64.ctz
            ;; Find the next cell above that is not empty: invert the empty
            ;; pattern and mask it with a column, shifted by idx.
            (local.tee $above-bits
              (i64.and
                (i64.xor (local.get $empty) (i64.const -1))
                (i64.shl (i64.const 0x0101010101010101) (local.get $idx))))))

        ;; If there is a cell above this one...
        (if (i64.ne (local.get $above-bits) (i64.const 0))
          (then
            ;; Move the cell above down
            (call $swap-all-grids-bits
              (i64.shl (i64.const 1) (local.get $above-idx))
              (i64.shl (i64.const 1) (local.get $idx)))

            ;; Set above-bit in empty so we will fill it.
            (local.set $empty
              (i64.or (local.get $empty)
                      (i64.shl (i64.const 1) (local.get $above-idx)))))
          (else
            ;; If there is no bit above, then we need to fill with a new random
            ;; cell.
            ;;
            ;; random-grid = int(random() * 8) << 3
            ;; grid-bitmap[random-grid] |= (1 << idx)
            (i64.store offset=0x3000
              (local.tee $random-grid
                (i32.shl
                  (i32.trunc_f32_u (f32.mul (call $random) (f32.const 8)))
                  (i32.const 3)))
              (i64.or
                (i64.load offset=0x3000 (local.get $random-grid))
                (i64.shl (i64.const 1) (local.get $idx))))

            ;; Set above-idx so it is always the maximum value (used below)
            (local.set $above-idx (i64.add (local.get $idx) (i64.const 56)))))

        ;; Reset the x,y,w,h to 0
        (i32.store offset=0x3200 (local.get $idx*4) (i32.const 0))

        ;; Then set the y pixel offset to the y cell difference * 17.
        (i64.store8 offset=0x3201
          (local.get $idx*4)
          (i64.mul
            (i64.shr_s
              (i64.sub (local.get $idx) (local.get $above-idx))
              (i64.const 3))
            (i64.const 17)))

        ;; Now animate it back to 0.
        (call $animate-cells
          (i64.shl (i64.const 1) (local.get $idx))
          (i32.const 0))

        ;; Clear this bit (it has now been filled).
        (local.set $empty
          (i64.and
            (local.get $empty)
            (i64.sub (local.get $empty) (i64.const 1))))

        ;; Always loop
        (br $move-down-loop)))

    ;; Set state to $falling
    (global.set $state (i32.const 3))

    (br $done)

  end $falling

    (br_if $done (global.get $animating))

    ;; If there are no matches (including swaps)...
    (if (i64.eqz (call $match-all-grids-patterns (i32.const 72)))
      (then
        ;; ... then reset the entire board.
        (global.set $matched (i64.const -1))

        ;; Reset the score
        (global.set $score (i32.const 0)))
      (else
        ;; Otherwise, check whether any new matches (without swaps) occurred.
        (global.set $matched (call $match-all-grids-patterns (i32.const 8)))

        ;; Add score
        (global.set $score
          (i32.add
            (global.get $score)
            (i32.wrap_i64 (i64.popcnt (global.get $matched)))))
        ))

  ;; Animate the matched cells
  (call $animate-cells (global.get $matched) (i32.const 0xf1_f1_08_08))

  ;; If there are new matches, then remove them, otherwise go back to $idle
  (global.set $state
    (select (i32.const 0) (i32.const 2) (i64.eqz (global.get $matched))))

  end $done

  ;; Animate
  ;; mul-t = 1
  (local.set $mul-t (f32.const 1))

  (loop $animate-loop
    ;; ilerp = (a,b,t) => return a + (b - a) * t
    ;; easeOutCubic(t) = t => t * (3 + t * (t - 3))
    ;; current[i] = ilerp(start[i], end[i], easeOutCubic(t))
    (i32.store8 offset=0x3200
      (local.get $i-addr)
      (i32.add
        (local.tee $a (i32.load8_s offset=0x3300 (local.get $i-addr)))
        (i32.trunc_f32_s
          (f32.mul
            (f32.convert_i32_s
              (i32.sub
                (i32.load8_s offset=0x3400 (local.get $i-addr))
                (local.get $a)))
            (f32.mul
              ;; t = Math.min(t[i] + speed, 1)
              (local.tee $t
                (f32.min
                  (f32.add
                    (f32.load offset=0x3500 (local.get $t-addr))
                    (f32.const 0.005))
                  (f32.const 1)))
              (f32.add
                (f32.const 3)
                (f32.mul
                  (local.get $t)
                  (f32.sub (local.get $t) (f32.const 3)))))))))
    ;; t[i] = t
    (f32.store offset=0x3500 (local.get $t-addr) (local.get $t))

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
  (call $draw-digit (i32.const 135) (i32.const 1))
  (call $draw-digit (i32.const 127) (i32.const 10))
  (call $draw-digit (i32.const 119) (i32.const 100))
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
    (local.set $grid (i64.load offset=0x3000 (local.get $grid-offset)))

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
          (i64.ne
            (local.tee $shifts (i64.shr_u (local.get $shifts) (i64.const 1)))
            (i64.const 0))))

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
  (local $temp i64)

  (loop $loop
    ;; bits = mem[grid-idx]
    ;; temp = bits & (a | b)
    ;; if bits are different...
    (if (i32.and
          (i64.ne
            (local.tee $temp
              (i64.and
                (local.tee $bits
                  (i64.load offset=0x3000 (local.get $grid-offset)))
                (local.tee $a|b (i64.or (local.get $a) (local.get $b)))))
            (i64.const 0))
          (i64.ne (local.get $temp) (local.get $a|b)))
      (then
        ;; mem[grid-idx] = bits ^ (a | b)
        (i64.store offset=0x3000
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
    (i32.store offset=0x3300
      (local.tee $src*4 (call $bit-to-src*4 (local.get $bits)))
      (i32.load offset=0x3200 (local.get $src*4)))

    ;; Set the destination x/y/w/h
    (i32.store offset=0x3400 (local.get $src*4) (local.get $h_w_y_x))

    ;; Set the time value to 1 - time.
    (f32.store offset=0x3500
      (local.get $src*4)
      (f32.sub
        (f32.const 1)
        (f32.load offset=0x3500 (local.get $src*4))))

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
  (local $grid-idx i32)
  (local $cell-idx i32)
  (local $anim-idx i32)
  (local $bits i64)

  (loop $grid-loop
    ;; bits = grid[grid-idx] & mask
    (local.set $bits
      (i64.and
        (i64.load offset=0x3000 (i32.shl (local.get $grid-idx) (i32.const 3)))
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
            (i32.load8_s offset=0x3200
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
            (i32.load8_s offset=0x3201 (local.get $anim-idx)))
          ;; src
          (i32.add
            (i32.const 0x100)
            (i32.shl (local.get $grid-idx) (i32.const 7)))
          ;; sw / sh
          (i32.const 16) (i32.const 16)
          ;; base w
          (i32.add
            (i32.const 16)
            ;; w offset
            (i32.load8_s offset=0x3202 (local.get $anim-idx)))
          ;; base h
          (i32.add
            (i32.const 16)
            ;; h offset
            (i32.load8_s offset=0x3203 (local.get $anim-idx)))
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

    ;; grid-idx += 1
    ;; loop if grid-idx < 8
    (br_if $grid-loop
      (i32.lt_s
        (local.tee $grid-idx (i32.add (local.get $grid-idx) (i32.const 1)))
        (i32.const 8))))
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
            (i32.load8_u
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
          ;; mem[0x10000 + (y * 150 + x) * 4] = color
          (i32.store offset=0x10000
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

(func $draw-digit (param $x i32) (param $divisor i32)
  (local $i i32)
  (call $draw-sprite
    (local.get $x) (i32.const 1)
    (i32.add
      (i32.const 0x500)
      (i32.shl
        (i32.rem_u
          (i32.div_u (global.get $score) (local.get $divisor))
          (i32.const 10))
        (i32.const 3)))
    (i32.const 8) (i32.const 8)
    (i32.const 8) (i32.const 8)
    (i32.const 3) (i32.const 7) (i32.const 1)
  )
)

(data (i32.const 0xc0)
  ;; 16 palette entries
  "\00\00\00\00\df\71\26\ff\fb\f2\36\ff\66\39\31\ff"
  "\ac\32\32\ff\63\9b\ff\ff\5f\cd\e4\ff\d9\57\63\ff"
  "\cb\db\fc\ff\8f\56\3b\ff\45\28\3c\ff\5b\6e\e1\ff"
  "\99\e5\50\ff\46\00\60\ff\80\00\94\ff\ff\ff\ff\ff"

  ;; sprite data
  "\00\00\00\11\11\00\00\00"
  "\00\00\11\22\22\11\00\00"
  "\00\10\22\22\22\22\01\00"
  "\00\21\22\22\22\22\12\00"
  "\10\22\22\33\22\33\22\01"
  "\10\22\22\33\22\33\22\01"
  "\21\22\22\33\22\33\22\12"
  "\21\23\22\33\22\33\32\12"
  "\21\33\22\22\22\22\32\12"
  "\21\33\33\33\33\33\33\12"
  "\10\32\ff\ff\ff\ff\23\01"
  "\10\22\33\33\33\33\22\01"
  "\00\21\32\33\33\23\12\00"
  "\00\10\22\32\33\22\01\00"
  "\00\00\11\22\22\11\00\00"
  "\00\00\00\11\11\00\00\00"
  "\00\10\00\11\11\00\01\00"
  "\00\41\11\22\22\11\14\00"
  "\11\44\14\11\12\41\44\11"
  "\44\44\44\44\41\44\44\44"
  "\44\44\44\14\42\44\44\44"
  "\41\44\44\21\12\44\44\14"
  "\41\44\44\21\12\44\44\14"
  "\41\14\44\21\12\44\41\14"
  "\40\21\41\21\12\14\12\04"
  "\10\12\11\11\11\11\21\01"
  "\10\32\ff\ff\ff\ff\23\01"
  "\10\22\33\33\33\33\21\01"
  "\00\21\32\ff\ff\1f\12\00"
  "\00\10\22\31\33\21\01\00"
  "\00\00\11\22\22\11\00\00"
  "\00\00\00\11\11\00\00\00"
  "\00\00\00\11\11\00\00\00"
  "\00\00\11\44\44\11\00\00"
  "\00\10\44\44\44\44\01\00"
  "\00\41\44\44\44\44\14\00"
  "\10\44\34\43\34\43\44\01"
  "\10\44\33\44\44\33\44\01"
  "\41\34\43\44\44\34\43\14"
  "\41\44\44\44\44\44\44\14"
  "\41\44\34\43\34\43\44\14"
  "\41\54\34\43\34\43\44\14"
  "\10\64\44\44\44\44\44\01"
  "\10\65\45\44\44\44\44\01"
  "\50\66\56\33\33\43\14\00"
  "\50\66\56\73\73\43\01\00"
  "\00\65\15\73\77\13\00\00"
  "\00\50\00\71\77\00\00\00"
  "\00\00\00\66\66\00\00\00"
  "\00\00\66\55\55\66\00\00"
  "\00\60\55\55\55\55\06\00"
  "\00\56\55\55\55\55\65\00"
  "\60\55\55\55\55\55\55\06"
  "\60\55\55\55\55\55\55\06"
  "\56\55\35\53\55\33\55\65"
  "\56\55\35\53\55\33\55\65"
  "\56\55\55\55\55\55\55\65"
  "\56\55\55\55\55\55\55\65"
  "\68\55\3f\ff\f3\3f\5f\06"
  "\68\55\33\33\33\33\53\06"
  "\08\58\3f\ff\f3\3f\6f\08"
  "\00\68\55\55\55\55\06\08"
  "\00\08\66\55\55\66\08\08"
  "\00\00\08\66\66\00\08\00"
  "\00\00\00\33\33\00\00\00"
  "\00\00\30\33\33\03\00\00"
  "\30\03\33\33\33\33\30\03"
  "\33\33\33\93\99\33\33\33"
  "\33\33\33\99\99\33\33\33"
  "\a3\aa\aa\99\99\a9\aa\3a"
  "\13\22\a2\aa\aa\aa\22\31"
  "\10\22\22\22\22\22\22\01"
  "\10\22\22\33\22\33\22\01"
  "\10\22\22\33\22\33\22\01"
  "\10\22\22\22\22\22\22\01"
  "\10\22\33\33\33\33\22\01"
  "\00\21\32\33\33\23\12\00"
  "\00\10\22\32\33\22\01\00"
  "\00\00\11\22\22\11\00\00"
  "\00\00\00\11\11\00\00\00"
  "\00\00\00\bb\bb\00\00\00"
  "\00\00\bb\ff\ff\bb\00\00"
  "\00\b0\f8\f8\f8\f8\0b\00"
  "\00\8b\35\85\85\35\b5\00"
  "\b0\55\f3\53\55\f3\53\0b"
  "\b0\35\ff\3f\35\ff\3f\0b"
  "\5b\35\ff\3f\35\ff\3f\b5"
  "\cb\3c\ff\3f\3c\ff\3f\bc"
  "\cb\cc\f3\c3\cc\f3\c3\bc"
  "\21\2c\2c\2c\33\c2\c2\12"
  "\10\22\22\32\33\23\22\01"
  "\10\11\22\32\33\23\12\01"
  "\10\22\21\32\33\23\21\12"
  "\10\22\21\22\33\22\21\12"
  "\21\22\11\22\22\11\21\12"
  "\21\12\00\11\11\00\10\22"
  "\00\00\00\00\00\00\00\00"
  "\0d\00\00\00\00\00\00\d0"
  "\dd\00\00\00\00\00\00\dd"
  "\ed\dd\d0\dd\dd\dd\d0\dd"
  "\ed\ee\ed\ee\ee\ee\ed\de"
  "\ed\ee\ee\ee\ee\ee\ee\de"
  "\d0\ed\ae\aa\ee\ae\aa\dd"
  "\d0\ee\ee\aa\ea\aa\ea\0d"
  "\d0\ee\ee\ee\ee\ee\ee\0d"
  "\d0\ee\ee\ae\ea\aa\ee\0d"
  "\d0\ee\ee\ae\ea\aa\ee\0d"
  "\00\ed\ee\ee\ee\ee\de\00"
  "\00\ed\ee\aa\aa\aa\de\00"
  "\00\d0\ee\ae\aa\ea\0d\00"
  "\00\00\dd\ee\ee\dd\00\00"
  "\00\00\00\dd\dd\00\00\00"
  "\00\00\00\00\00\00\00\00"
  "\00\00\00\30\03\00\00\00"
  "\00\00\00\30\33\00\00\00"
  "\00\00\00\3a\33\03\00\00"
  "\00\00\a0\aa\aa\0a\00\00"
  "\00\00\30\aa\aa\aa\00\00"
  "\00\00\33\ff\33\ff\03\00"
  "\00\00\aa\af\33\af\33\00"
  "\00\a0\aa\ff\aa\ff\aa\00"
  "\00\30\a3\aa\aa\aa\aa\0a"
  "\00\33\33\33\33\33\33\03"
  "\a0\3a\33\ff\ff\ff\33\33"
  "\a0\aa\aa\fa\ff\af\aa\aa"
  "\30\a3\aa\aa\aa\aa\aa\aa"
  "\00\30\33\33\33\33\33\03"
  "\00\00\00\00\00\00\00\00"

  ;; digits
  "\3e\7f\63\63\63\63\7f\3e"  ;; 0
  "\30\3c\3c\30\30\30\7e\7e"  ;; 1
  "\3e\7e\60\7e\3f\03\7f\7f"  ;; 2
  "\3e\7f\63\78\38\63\7f\7e"  ;; 3
  "\66\67\63\7f\7f\60\60\60"  ;; 4
  "\7f\7f\03\3f\7f\60\7f\3f"  ;; 5
  "\3c\3e\07\3f\7f\63\7f\3e"  ;; 6
  "\7f\7f\30\18\18\0c\0c\0c"  ;; 7
  "\1c\3e\63\7f\3e\63\7f\3e"  ;; 8
  "\3e\7f\63\7f\7e\30\3e\1e"  ;; 9

  ;; match patterns
  (i32
    ;; ........    ........
    ;; ........    .......x
    ;; ........    .......x
    ;; .....xxx    .......x
     0x00000007  0x00010101

    ;; ........    ........    ........
    ;; ........    ........    ........
    ;; .....x..    ......x.    .......x
    ;; ......xx    .....x.x    .....xx.
     0x00000403  0x00000205  0x00000106

    ;; ........    ........    ........
    ;; ........    ........    ........
    ;; ......xx    .....x.x    .....xx.
    ;; .....x..    ......x.    .......x
     0x00000304  0x00000502  0x00000601

    ;; ........    ........
    ;; ........    ........
    ;; ........    ........
    ;; ....x.xx    ....xx.x
     0x0000000b  0x0000000d

    ;; ........    ........    ........
    ;; ......x.    .......x    .......x
    ;; .......x    ......x.    .......x
    ;; .......x    .......x    ......x.
     0x00020101  0x00010201  0x00010102

    ;; ........    ........    ........
    ;; .......x    ......x.    ......x.
    ;; ......x.    .......x    ......x.
    ;; ......x.    ......x.    .......x
     0x00010202  0x00020102  0x00020201

    ;; .......x    .......x
    ;; ........    .......x
    ;; .......x    ........
    ;; .......x    .......x
     0x01000101  0x01010001
  )

  ;; match shifts
  (i64
    ;;    ..xxxxxx            ........
    ;;    ..xxxxxx            ........
    ;;    ..xxxxxx            xxxxxxxx
    ;;    ..xxxxxx            xxxxxxxx
    ;;    ..xxxxxx            xxxxxxxx
    ;;    ..xxxxxx            xxxxxxxx
    ;;    ..xxxxxx            xxxxxxxx
    ;;    ..xxxxxx            xxxxxxxx
    0x3f3f3f3f3f3f3f3f  0x0000ffffffffffff

    ;;    ........            ........            ........
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    0x003f3f3f3f3f3f3f  0x003f3f3f3f3f3f3f  0x003f3f3f3f3f3f3f

    ;;    ........            ........            ........
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    ;;    ..xxxxxx            ..xxxxxx            ..xxxxxx
    0x003f3f3f3f3f3f3f  0x003f3f3f3f3f3f3f  0x003f3f3f3f3f3f3f

    ;;    ...xxxxx            ...xxxxx
    ;;    ...xxxxx            ...xxxxx
    ;;    ...xxxxx            ...xxxxx
    ;;    ...xxxxx            ...xxxxx
    ;;    ...xxxxx            ...xxxxx
    ;;    ...xxxxx            ...xxxxx
    ;;    ...xxxxx            ...xxxxx
    ;;    ...xxxxx            ...xxxxx
    0x1f1f1f1f1f1f1f1f  0x1f1f1f1f1f1f1f1f

    ;;    ........            ........            ........
    ;;    ........            ........            ........
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    0x00007f7f7f7f7f7f  0x00007f7f7f7f7f7f  0x00007f7f7f7f7f7f

    ;;    ........            ........            ........
    ;;    ........            ........            ........
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    ;;    .xxxxxxx            .xxxxxxx            .xxxxxxx
    0x00007f7f7f7f7f7f  0x00007f7f7f7f7f7f  0x00007f7f7f7f7f7f

    ;;    ........            ........
    ;;    ........            ........
    ;;    ........            ........
    ;;    xxxxxxxx            xxxxxxxx
    ;;    xxxxxxxx            xxxxxxxx
    ;;    xxxxxxxx            xxxxxxxx
    ;;    xxxxxxxx            xxxxxxxx
    ;;    xxxxxxxx            xxxxxxxx
    0x000000ffffffffff  0x000000ffffffffff
  )
)
