;; Memory map:
;;
;; [0x00000 .. 0x00001]  x, y mouse position
;; [0x00002 .. 0x00002]  mouse buttons
;; [0x00003 .. 0x00004]  x, y mouse click position
;; [0x000c0 .. 0x00100]  16 RGBA colors       u32[16]
;; [0x00100 .. 0x01100]  16x16x1 Bpp sprites  u8[8][256]
;; [0x03000 .. 0x03040]  8x8 grid bitmap  u64[8]
;; [0x03200 .. 0x03300]  current offset  {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x03300 .. 0x03400]  start offset    {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x03400 .. 0x03500]  end offset      {s8 x, s8 y, s8 w, s8 h}[64]
;; [0x03500 .. 0x03600]  time [0..1)     f32[64]
;; [0x10000 .. 0x25f90]  150x150xRGBA data (4 bytes per pixel)
(memory (export "mem") 3)

(data (i32.const 0x3000)
  ;; bitmap grid
  (i64
    0x0102040808040201   ;; cells 0
    0x0204081010080402   ;; cells 1
    0x0408102020100804   ;; cells 2
    0x0810204040201008   ;; cells 3
    0x1020408080402010   ;; cells 4
    0x2040800101804020   ;; cells 5
    0x4080010202018040   ;; cells 6
    0x8001020404020180   ;; cells 7
    )
)

;; Initialize all y-coordinates to -128
(func $start
  (local $i i32)
  (loop $loop
    ;; mem[0x3301 + i] = -128
    (i32.store8 offset=0x3301 (local.get $i) (i32.const -128))

    ;; i += 4
    (local.set $i (i32.add (local.get $i) (i32.const 4)))

    ;; loop if i < 256
    (br_if $loop (i32.lt_s (local.get $i) (i32.const 256)))
  )
)
(start $start)


(global $state (mut i32) (i32.const 0))

(global $prev-mouse-bit (mut i64) (i64.const 0))
(global $click-mouse-bit (mut i64) (i64.const 0))

(func (export "run")
  (local $mouse-bit i64)
  (local $mouse-dx f32)
  (local $mouse-dy f32)

  (call $clear-screen (i32.const 0)) ;; transparent black

  block $done
  block $mouse-down
  block $idle
    (br_table $idle $mouse-down (global.get $state))

  end $idle

    (local.set $mouse-bit
      (call $get-mouse-bit
        (i32.load8_u (i32.const 0))   ;; mousex
        (i32.load8_u (i32.const 1)))) ;; mousey

    ;; If the mouse grid position changed...
    (if (i64.ne (local.get $mouse-bit) (global.get $prev-mouse-bit))
      (then
        ;; If the new position is valid, then animate the bit
        (call $animate-cell (local.get $mouse-bit) (i32.const 0x08_08_fc_fc))

        ;; If the old position is valid, then animate the bit
        (call $animate-cell (global.get $prev-mouse-bit) (i32.const 0))

        (global.set $prev-mouse-bit (local.get $mouse-bit))))

    ;; If the mouse was clicked, and it is on a valid cell...
    (if (i32.and
          (i32.load8_u (i32.const 2))
          (i64.ne (local.get $mouse-bit) (i64.const 0)))
      (then
        ;; Save the current mouse x/y.
        (i32.store16 (i32.const 3) (i32.load16_u (i32.const 0)))

        ;; Set the current state to $mouse-down.
        (global.set $state (i32.const 1))
        (global.set $click-mouse-bit (local.get $mouse-bit))))

    (br $done)

  end $mouse-down

    ;; mouse-dx = mouse-x - mouse-click-x
    (local.set $mouse-dx
      (f32.convert_i32_s
        (i32.sub (i32.load8_u (i32.const 0)) (i32.load8_u (i32.const 3)))))
    ;; mouse-dy = mouse-y - mouse-click-y
    (local.set $mouse-dy
      (f32.convert_i32_s
        (i32.sub (i32.load8_u (i32.const 1)) (i32.load8_u (i32.const 4)))))

    ;; if abs(mouse-dx) < abs(mouse-dy) ...
    (if (f32.lt (f32.abs (local.get $mouse-dx)) (f32.abs (local.get $mouse-dy)))
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
    (i32.store8 offset=0x3400
      (call $bit-to-src*4 (global.get $click-mouse-bit))
      (i32.trunc_f32_s (local.get $mouse-dx)))
    ;; end[click-mouse-bit].y = mouse-dy
    (i32.store8 offset=0x3401
      (call $bit-to-src*4 (global.get $click-mouse-bit))
      (i32.trunc_f32_s (local.get $mouse-dy)))

    ;; If mouse-bit != 0 && mouse-bit != click-mouse-bit
    (if (i32.and
          (i64.ne (local.get $mouse-bit) (i64.const 0))
          (i64.ne (global.get $click-mouse-bit) (local.get $mouse-bit)))
      (then
        ;; end[mouse-bit].x = -mouse-dx
        (i32.store8 offset=0x3400
          (call $bit-to-src*4 (local.get $mouse-bit))
          (i32.trunc_f32_s (f32.neg (local.get $mouse-dx))))
        ;; end[mouse-bit].y = -mouse-dy
        (i32.store8 offset=0x3401
          (call $bit-to-src*4 (local.get $mouse-bit))
          (i32.trunc_f32_s (f32.neg (local.get $mouse-dy))))))

    (if (i64.ne (global.get $prev-mouse-bit) (local.get $mouse-bit))
      (then
        ;; If the old position is valid, then animate the cell.
        (call $animate-cell (global.get $prev-mouse-bit) (i32.const 0))

        (global.set $prev-mouse-bit (local.get $mouse-bit))))

    ;; If the button is no longer pressed, go back to idle.
    (if (i32.eqz (i32.load8_u (i32.const 2)))
      (then
        (global.set $state (i32.const 0))
        (call $animate-cell (global.get $prev-mouse-bit) (i32.const 0))
        (call $animate-cell (global.get $click-mouse-bit) (i32.const 0))))

    ;; Use the grid mouse position when the mouse was clicked for drawing below
    (local.set $mouse-bit (global.get $click-mouse-bit))


  end $done

  (call $animate)
  (call $draw-grids (i64.const -1))  ;; Mask with all 1s

  ;; Draw the moused-over cell again, so they're on top
  (call $draw-grids (local.get $mouse-bit))
)

(func $get-mouse-bit (param $x i32) (param $y i32) (result i64)
  ;; x -= 7
  (local.set $x (i32.sub (local.get $x) (i32.const 7)))
  ;; y = 142 - y
  (local.set $y (i32.sub (i32.const 142) (local.get $y)))

  ;; return ...
  (select
    ;; 1 << ((y / 17) * 8 + (x / 17))
    (i64.shl
      (i64.const 1)
      (i64.extend_i32_u
        (i32.add
          (i32.mul
            (i32.div_s (local.get $y) (i32.const 17))
            (i32.const 8))
          (i32.div_s (local.get $x) (i32.const 17)))))
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

(func $animate-cell (param $bit i64) (param $h_w_y_x i32)
  (local $src*4 i32)

  ;; return if $src == 0
  (br_if 0 (i64.eqz (local.get $bit)))

  (local.set $src*4 (call $bit-to-src*4 (local.get $bit)))

  ;; Set the start x/y/w/h to the current x/y/w/h.
  (i32.store offset=0x3300
    (local.get $src*4)
    (i32.load offset=0x3200 (local.get $src*4)))

  ;; Set the destination x/y/w/h
  (i32.store offset=0x3400 (local.get $src*4) (local.get $h_w_y_x))

  ;; Set the time value to 1 - time.
  (f32.store offset=0x3500
    (local.get $src*4)
    (f32.sub
      (f32.const 1)
      (f32.load offset=0x3500 (local.get $src*4))))
)

(func $draw-grids (param $mask i64)
  (local $i i32)
  (loop $loop

    (call $draw-grid
      (i64.and
        (i64.load offset=0x3000 (i32.shl (local.get $i) (i32.const 3)))
        (local.get $mask))
      (i32.add (i32.const 0x100) (i32.shl (local.get $i) (i32.const 8))))

    ;; i += 1
    (local.set $i (i32.add (local.get $i) (i32.const 1)))

    ;; loop if i < 8
    (br_if $loop (i32.lt_s (local.get $i) (i32.const 8)))
  )
)

(func $draw-grid (param $bits i64) (param $gfx-src i32)
  (local $idx i32)
  ;; Loop over all cells 0 to 63
  (loop $loop
    ;; Exit the function if bits == 0
    (br_if 1 (i64.eqz (local.get $bits)))

    ;; Get the index of the lowest set bit
    (local.set $idx (i32.wrap_i64 (i64.ctz (local.get $bits))))

    ;; Draw the cell at that index
    (call $draw-cell
      ;; x-coordinate: 7 + (idx & 7) * 17
      (i32.add
        (i32.const 7)
        (i32.mul
          (i32.and (local.get $idx) (i32.const 7))
          (i32.const 17)))
      ;; y-coordinate: (150 - 17 - 7) - (idx >> 3) * 17
      (i32.sub
        (i32.const 126)
        (i32.mul
          (i32.shr_u (local.get $idx) (i32.const 3))
          (i32.const 17)))
      ;; src => idx >> 2
      (i32.shl (local.get $idx) (i32.const 2))
      (local.get $gfx-src))

    ;; Clear the lowest set bit: bits &= bits - 1
    (local.set $bits
      (i64.and
        (local.get $bits)
        (i64.sub (local.get $bits) (i64.const 1))))

    ;; Always loop
    (br $loop)
  )
)

(func $draw-cell (param $x i32) (param $y i32) (param $i i32) (param $src i32) 
  (call $draw-sprite
    (i32.add
      (local.get $x)  ;; base x
      (i32.load8_s offset=0x3200 (local.get $i))) ;; x offset
    (i32.add
      (local.get $y)  ;; base y
      (i32.load8_s offset=0x3201 (local.get $i))) ;; y offset
    (local.get $src)
    (i32.const 16)  ;; sw
    (i32.const 16)  ;; sh
    (i32.add
      (i32.const 16)   ;; base w
      (i32.load8_s offset=0x3202 (local.get $i)))  ;; w offset
    (i32.add
      (i32.const 16)   ;; base h
      (i32.load8_s offset=0x3203 (local.get $i)))) ;; h offset
)

(func $clear-screen (param $color i32)
  (local $i i32)
  (loop $loop
    ;; mem[0x10000 + i] = color
    (i32.store offset=0x10000 (local.get $i) (local.get $color))

    ;; i += 4
    (local.set $i (i32.add (local.get $i) (i32.const 4)))

    ;; loop if i < 90000
    (br_if $loop (i32.lt_s (local.get $i) (i32.const 90000)))
  )
)

(func $put-pixel (param $x i32) (param $y i32) (param $palidx i32)
  ;; return if the x/y coordinate is out of bounds
  (br_if 0
    (i32.or
      (i32.ge_u (local.get $x) (i32.const 150))
      (i32.ge_u (local.get $y) (i32.const 150))))

  ;; color = mem[0xc0 + (palidx << 2)]
  ;; mem[0x10000 + (y * 150 + x) * 4] = color
  (i32.store offset=0x10000
    (i32.mul
      (i32.add
        (i32.mul (local.get $y) (i32.const 150))
        (local.get $x))
      (i32.const 4))
    (i32.load offset=0xc0
      (i32.shl (local.get $palidx) (i32.const 2))))
)

(func $draw-sprite (param $x i32) (param $y i32)
                   (param $src i32)
                   (param $sw i32) (param $sh i32)
                   (param $dw i32) (param $dh i32)
  (local $i i32)
  (local $j i32)
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
      ;; pixel = mem[src + (sw * j * dy + i * dx)]
      (local.set $palidx
        (i32.load8_u
          (i32.add
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
                  (local.get $dx))))
            (local.get $src))))

      ;; if (palidx != 0)
      (if (local.get $palidx)
        (then
          ;; put-pixel(x + i, y + j, palidx)
          (call $put-pixel
            (i32.add (local.get $x) (local.get $i))
            (i32.add (local.get $y) (local.get $j))
            (local.get $palidx))))

      ;; i += 1
      (local.set $i (i32.add (local.get $i) (i32.const 1)))

      ;; loop if i < w
      (br_if $x-loop (i32.lt_s (local.get $i) (local.get $dw)))
    )
    ;; j += 1
    (local.set $j (i32.add (local.get $j) (i32.const 1)))

    ;; loop if j < h
    (br_if $y-loop (i32.lt_s (local.get $j) (local.get $dh)))
  )
)

(func $animate
  (local $t-addr i32)
  (local $i-addr i32)
  (local $t f32)

  (loop $loop
    ;; t = Math.min(t[i] + speed, 1)
    (local.set $t
      (f32.min
        (f32.add
          (f32.load offset=0x3500 (local.get $t-addr))
          (f32.const 0.005))
        (f32.const 1)))

    ;; current[i] = ilerp(start[i], end[i], easeOutCubic(t))
    (i32.store8 offset=0x3200
      (local.get $i-addr)
      (call $ilerp
        (i32.load8_s offset=0x3300 (local.get $i-addr))
        (i32.load8_s offset=0x3400 (local.get $i-addr))
        (call $ease-out-cubic (local.get $t))))
    ;; t[i] = t
    (f32.store offset=0x3500 (local.get $t-addr) (local.get $t))

    ;; i-addr += 1
    (local.set $i-addr (i32.add (local.get $i-addr) (i32.const 1)))
    ;; t-addr = i-addr & ~3
    (local.set $t-addr (i32.and (local.get $i-addr) (i32.const 0xfc)))
    (br_if $loop (i32.lt_s (local.get $i-addr) (i32.const 256)))
  )
)

(func $ease-out-cubic (param $t f32) (result f32)
  ;; return t * (3 + t * (t - 3))
  (f32.mul
    (local.get $t)
    (f32.add
      (f32.const 3)
      (f32.mul
        (local.get $t)
        (f32.sub (local.get $t) (f32.const 3)))))
)

(func $ilerp (param $a i32) (param $b i32) (param $t f32) (result i32)
  ;; return a + (b - a) * t
  (i32.add
    (local.get $a)
    (i32.trunc_f32_s
      (f32.mul
        (f32.convert_i32_s (i32.sub (local.get $b) (local.get $a)))
        (local.get $t))))
)

(data (i32.const 0xc0)
  ;; 16 palette entries
  "\00\00\00\00\df\71\26\ff\fb\f2\36\ff\66\39\31\ff"
  "\ac\32\32\ff\63\9b\ff\ff\5f\cd\e4\ff\d9\57\63\ff"
  "\cb\db\fc\ff\8f\56\3b\ff\45\28\3c\ff\5b\6e\e1\ff"
  "\99\e5\50\ff\46\00\60\ff\80\00\94\ff\ff\ff\ff\ff"

  ;; sprite data
  "\00\00\00\00\00\00\01\01\01\01\00\00\00\00\00\00"
  "\00\00\00\00\01\01\02\02\02\02\01\01\00\00\00\00"
  "\00\00\00\01\02\02\02\02\02\02\02\02\01\00\00\00"
  "\00\00\01\02\02\02\02\02\02\02\02\02\02\01\00\00"
  "\00\01\02\02\02\02\03\03\02\02\03\03\02\02\01\00"
  "\00\01\02\02\02\02\03\03\02\02\03\03\02\02\01\00"
  "\01\02\02\02\02\02\03\03\02\02\03\03\02\02\02\01"
  "\01\02\03\02\02\02\03\03\02\02\03\03\02\03\02\01"
  "\01\02\03\03\02\02\02\02\02\02\02\02\02\03\02\01"
  "\01\02\03\03\03\03\03\03\03\03\03\03\03\03\02\01"
  "\00\01\02\03\0f\0f\0f\0f\0f\0f\0f\0f\03\02\01\00"
  "\00\01\02\02\03\03\03\03\03\03\03\03\02\02\01\00"
  "\00\00\01\02\02\03\03\03\03\03\03\02\02\01\00\00"
  "\00\00\00\01\02\02\02\03\03\03\02\02\01\00\00\00"
  "\00\00\00\00\01\01\02\02\02\02\01\01\00\00\00\00"
  "\00\00\00\00\00\00\01\01\01\01\00\00\00\00\00\00"
  "\00\00\00\01\00\00\01\01\01\01\00\00\01\00\00\00"
  "\00\00\01\04\01\01\02\02\02\02\01\01\04\01\00\00"
  "\01\01\04\04\04\01\01\01\02\01\01\04\04\04\01\01"
  "\04\04\04\04\04\04\04\04\01\04\04\04\04\04\04\04"
  "\04\04\04\04\04\04\04\01\02\04\04\04\04\04\04\04"
  "\01\04\04\04\04\04\01\02\02\01\04\04\04\04\04\01"
  "\01\04\04\04\04\04\01\02\02\01\04\04\04\04\04\01"
  "\01\04\04\01\04\04\01\02\02\01\04\04\01\04\04\01"
  "\00\04\01\02\01\04\01\02\02\01\04\01\02\01\04\00"
  "\00\01\02\01\01\01\01\01\01\01\01\01\01\02\01\00"
  "\00\01\02\03\0f\0f\0f\0f\0f\0f\0f\0f\03\02\01\00"
  "\00\01\02\02\03\03\03\03\03\03\03\03\01\02\01\00"
  "\00\00\01\02\02\03\0f\0f\0f\0f\0f\01\02\01\00\00"
  "\00\00\00\01\02\02\01\03\03\03\01\02\01\00\00\00"
  "\00\00\00\00\01\01\02\02\02\02\01\01\00\00\00\00"
  "\00\00\00\00\00\00\01\01\01\01\00\00\00\00\00\00"
  "\00\00\00\00\00\00\01\01\01\01\00\00\00\00\00\00"
  "\00\00\00\00\01\01\04\04\04\04\01\01\00\00\00\00"
  "\00\00\00\01\04\04\04\04\04\04\04\04\01\00\00\00"
  "\00\00\01\04\04\04\04\04\04\04\04\04\04\01\00\00"
  "\00\01\04\04\04\03\03\04\04\03\03\04\04\04\01\00"
  "\00\01\04\04\03\03\04\04\04\04\03\03\04\04\01\00"
  "\01\04\04\03\03\04\04\04\04\04\04\03\03\04\04\01"
  "\01\04\04\04\04\04\04\04\04\04\04\04\04\04\04\01"
  "\01\04\04\04\04\03\03\04\04\03\03\04\04\04\04\01"
  "\01\04\04\05\04\03\03\04\04\03\03\04\04\04\04\01"
  "\00\01\04\06\04\04\04\04\04\04\04\04\04\04\01\00"
  "\00\01\05\06\05\04\04\04\04\04\04\04\04\04\01\00"
  "\00\05\06\06\06\05\03\03\03\03\03\04\04\01\00\00"
  "\00\05\06\06\06\05\03\07\03\07\03\04\01\00\00\00"
  "\00\00\05\06\05\01\03\07\07\07\03\01\00\00\00\00"
  "\00\00\00\05\00\00\01\07\07\07\00\00\00\00\00\00"
  "\00\00\00\00\00\00\06\06\06\06\00\00\00\00\00\00"
  "\00\00\00\00\06\06\05\05\05\05\06\06\00\00\00\00"
  "\00\00\00\06\05\05\05\05\05\05\05\05\06\00\00\00"
  "\00\00\06\05\05\05\05\05\05\05\05\05\05\06\00\00"
  "\00\06\05\05\05\05\05\05\05\05\05\05\05\05\06\00"
  "\00\06\05\05\05\05\05\05\05\05\05\05\05\05\06\00"
  "\06\05\05\05\05\03\03\05\05\05\03\03\05\05\05\06"
  "\06\05\05\05\05\03\03\05\05\05\03\03\05\05\05\06"
  "\06\05\05\05\05\05\05\05\05\05\05\05\05\05\05\06"
  "\06\05\05\05\05\05\05\05\05\05\05\05\05\05\05\06"
  "\08\06\05\05\0f\03\0f\0f\03\0f\0f\03\0f\05\06\00"
  "\08\06\05\05\03\03\03\03\03\03\03\03\03\05\06\00"
  "\08\00\08\05\0f\03\0f\0f\03\0f\0f\03\0f\06\08\00"
  "\00\00\08\06\05\05\05\05\05\05\05\05\06\00\08\00"
  "\00\00\08\00\06\06\05\05\05\05\06\06\08\00\08\00"
  "\00\00\00\00\08\00\06\06\06\06\00\00\08\00\00\00"
  "\00\00\00\00\00\00\03\03\03\03\00\00\00\00\00\00"
  "\00\00\00\00\00\03\03\03\03\03\03\00\00\00\00\00"
  "\00\03\03\00\03\03\03\03\03\03\03\03\00\03\03\00"
  "\03\03\03\03\03\03\03\09\09\09\03\03\03\03\03\03"
  "\03\03\03\03\03\03\09\09\09\09\03\03\03\03\03\03"
  "\03\0a\0a\0a\0a\0a\09\09\09\09\09\0a\0a\0a\0a\03"
  "\03\01\02\02\02\0a\0a\0a\0a\0a\0a\0a\02\02\01\03"
  "\00\01\02\02\02\02\02\02\02\02\02\02\02\02\01\00"
  "\00\01\02\02\02\02\03\03\02\02\03\03\02\02\01\00"
  "\00\01\02\02\02\02\03\03\02\02\03\03\02\02\01\00"
  "\00\01\02\02\02\02\02\02\02\02\02\02\02\02\01\00"
  "\00\01\02\02\03\03\03\03\03\03\03\03\02\02\01\00"
  "\00\00\01\02\02\03\03\03\03\03\03\02\02\01\00\00"
  "\00\00\00\01\02\02\02\03\03\03\02\02\01\00\00\00"
  "\00\00\00\00\01\01\02\02\02\02\01\01\00\00\00\00"
  "\00\00\00\00\00\00\01\01\01\01\00\00\00\00\00\00"
  "\00\00\00\00\00\00\0b\0b\0b\0b\00\00\00\00\00\00"
  "\00\00\00\00\0b\0b\0f\0f\0f\0f\0b\0b\00\00\00\00"
  "\00\00\00\0b\08\0f\08\0f\08\0f\08\0f\0b\00\00\00"
  "\00\00\0b\08\05\03\05\08\05\08\05\03\05\0b\00\00"
  "\00\0b\05\05\03\0f\03\05\05\05\03\0f\03\05\0b\00"
  "\00\0b\05\03\0f\0f\0f\03\05\03\0f\0f\0f\03\0b\00"
  "\0b\05\05\03\0f\0f\0f\03\05\03\0f\0f\0f\03\05\0b"
  "\0b\0c\0c\03\0f\0f\0f\03\0c\03\0f\0f\0f\03\0c\0b"
  "\0b\0c\0c\0c\03\0f\03\0c\0c\0c\03\0f\03\0c\0c\0b"
  "\01\02\0c\02\0c\02\0c\02\03\03\02\0c\02\0c\02\01"
  "\00\01\02\02\02\02\02\03\03\03\03\02\02\02\01\00"
  "\00\01\01\01\02\02\02\03\03\03\03\02\02\01\01\00"
  "\00\01\02\02\01\02\02\03\03\03\03\02\01\02\02\01"
  "\00\01\02\02\01\02\02\02\03\03\02\02\01\02\02\01"
  "\01\02\02\02\01\01\02\02\02\02\01\01\01\02\02\01"
  "\01\02\02\01\00\00\01\01\01\01\00\00\00\01\02\02"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\0d\00\00\00\00\00\00\00\00\00\00\00\00\00\00\0d"
  "\0d\0d\00\00\00\00\00\00\00\00\00\00\00\00\0d\0d"
  "\0d\0e\0d\0d\00\0d\0d\0d\0d\0d\0d\0d\00\0d\0d\0d"
  "\0d\0e\0e\0e\0d\0e\0e\0e\0e\0e\0e\0e\0d\0e\0e\0d"
  "\0d\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0d"
  "\00\0d\0d\0e\0e\0a\0a\0a\0e\0e\0e\0a\0a\0a\0d\0d"
  "\00\0d\0e\0e\0e\0e\0a\0a\0a\0e\0a\0a\0a\0e\0d\00"
  "\00\0d\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0d\00"
  "\00\0d\0e\0e\0e\0e\0e\0a\0a\0e\0a\0a\0e\0e\0d\00"
  "\00\0d\0e\0e\0e\0e\0e\0a\0a\0e\0a\0a\0e\0e\0d\00"
  "\00\00\0d\0e\0e\0e\0e\0e\0e\0e\0e\0e\0e\0d\00\00"
  "\00\00\0d\0e\0e\0e\0a\0a\0a\0a\0a\0a\0e\0d\00\00"
  "\00\00\00\0d\0e\0e\0e\0a\0a\0a\0a\0e\0d\00\00\00"
  "\00\00\00\00\0d\0d\0e\0e\0e\0e\0d\0d\00\00\00\00"
  "\00\00\00\00\00\00\0d\0d\0d\0d\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\03\03\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\03\03\03\00\00\00\00\00\00"
  "\00\00\00\00\00\00\0a\03\03\03\03\00\00\00\00\00"
  "\00\00\00\00\00\0a\0a\0a\0a\0a\0a\00\00\00\00\00"
  "\00\00\00\00\00\03\0a\0a\0a\0a\0a\0a\00\00\00\00"
  "\00\00\00\00\03\03\0f\0f\03\03\0f\0f\03\00\00\00"
  "\00\00\00\00\0a\0a\0f\0a\03\03\0f\0a\03\03\00\00"
  "\00\00\00\0a\0a\0a\0f\0f\0a\0a\0f\0f\0a\0a\00\00"
  "\00\00\00\03\03\0a\0a\0a\0a\0a\0a\0a\0a\0a\0a\00"
  "\00\00\03\03\03\03\03\03\03\03\03\03\03\03\03\00"
  "\00\0a\0a\03\03\03\0f\0f\0f\0f\0f\0f\03\03\03\03"
  "\00\0a\0a\0a\0a\0a\0a\0f\0f\0f\0f\0a\0a\0a\0a\0a"
  "\00\03\03\0a\0a\0a\0a\0a\0a\0a\0a\0a\0a\0a\0a\0a"
  "\00\00\00\03\03\03\03\03\03\03\03\03\03\03\03\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
)
