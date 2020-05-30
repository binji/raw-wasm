(import "Math" "random" (func $random (result f32)))
(import "Math" "sin" (func $sin (param f32) (result f32)))

;; 0..0x27f       : sprite data
;; 0x280..0x28a   : strings
;; 0x290..0x2b4   : palette
;; 0x2c0          : left
;; 0x2c1          : right
;; 0x300..0x1fff  : (x, y) for each snake node
;; 0x2400..       : 1bpp screen
;; 0x15000..      : 4bpp screen
(memory (export "mem") 6)

(global $mode (mut i32) (i32.const 0))
(global $angle (mut i32) (i32.const 0))
(global $speed (mut f32) (f32.const 0))
(global $turnspeed (mut i32) (i32.const 0))
(global $x (mut f32) (f32.const 0))
(global $y (mut f32) (f32.const 0))
(global $dx (mut f32) (f32.const 0))
(global $dy (mut f32) (f32.const 0))
(global $len (mut i32) (i32.const 0))
(global $tolen (mut i32) (i32.const 0))
(global $foodx (mut i32) (i32.const 0))
(global $foody (mut i32) (i32.const 0))
(global $timer (mut i32) (i32.const 30))
(global $score (mut i32) (i32.const 0))
(global $shake (mut f32) (f32.const 0))

(data (i32.const 0)
  ;; 0: big circle
  "\00\00\00\00\00\00\80\01\e0\07\f0\0f\f0\0f\f8\1f"
  "\f8\1f\f0\0f\f0\0f\e0\07\80\01\00\00\00\00\00\00"

  ;; 32: middle circle
  "\00\00\00\00\00\00\00\00\00\00\80\01\c0\03\e0\07"
  "\e0\07\c0\03\80\01\00\00\00\00\00\00\00\00\00\00"

  ;; 64: small circle
  "\00\00\00\00\00\00\00\00\00\00\00\00\80\01\c0\03"
  "\c0\03\80\01\00\00\00\00\00\00\00\00\00\00\00\00"

  ;; 96: S
  "\00\00\f0\07\f8\1f\fc\3f\3c\3e\1c\3c\80\3f\e0\1f"
  "\f0\07\f8\01\7c\38\7c\3c\fc\3f\f8\1f\e0\0f\00\00"

  ;; 128: N
  "\00\00\3c\38\3e\7c\1e\7e\1e\7f\1e\7f\9e\7f\de\7f"
  "\fe\7b\fe\79\fe\78\7e\78\7e\7c\3e\7c\1e\7c\00\00"

  ;; 160: A
  "\00\00\c0\01\c0\03\e0\07\f0\07\f0\0f\f8\0f\f8\1f"
  "\7c\3e\3c\3e\fe\3f\fe\7f\fe\7f\1e\78\0e\70\00\00"

  ;; 192: K
  "\00\00\00\70\1e\78\3e\78\fe\78\fc\7b\f8\7f\e0\7f"
  "\c0\7f\f0\7f\f8\7b\fe\78\7e\78\3e\78\0e\70\00\00"

  ;; 224: E
  "\00\00\fe\0f\fe\3f\fe\7f\fc\7f\00\7c\00\78\fc\7f"
  "\fc\7f\fc\7f\00\78\1c\7e\fe\7f\fe\3f\fe\0f\00\00"

  ;; 256: C
  "\00\00\f8\0f\fc\3f\fe\7f\fe\7f\1e\7c\00\78\00\78"
  "\00\78\00\78\00\78\3e\7e\fe\7f\fe\3f\fc\0f\00\00"

  ;; 288: R
  "\00\00\e0\1f\f8\3f\fc\3f\fc\3c\3c\38\3c\7c\fc\7f"
  "\fc\7f\f8\7f\f0\7f\f8\79\fe\78\7e\78\1e\70\00\00"

  ;; 320: O/0
  "\00\00\f0\07\f8\1f\fc\3f\fe\7f\3e\7c\1e\78\1e\78"
  "\1e\78\1e\78\3e\7c\7c\7e\fc\3f\f8\1f\f0\07\00\00"

  ;; 352: 1
  "\00\00\e0\01\e0\0f\e0\1f\e0\1f\e0\1d\e0\01\e0\01"
  "\c0\01\c0\01\c0\01\c0\03\fc\3f\fc\3f\fc\3f\00\00"

  ;; 384: 2
  "\00\00\e0\07\f0\1f\f8\1f\fc\3f\7c\7c\3c\7c\7c\38"
  "\f8\00\f8\01\f0\07\e0\0f\fe\3f\fe\7f\fe\7f\00\00"

  ;; 416: 3
  "\00\00\f8\0f\fc\3f\fe\7f\fe\7f\3e\78\fc\33\fe\07"
  "\fe\07\fe\03\3e\38\fe\7f\fe\7f\fc\3f\f8\1f\00\00"

  ;; 448: 4
  "\00\00\38\1e\3c\1e\3c\3e\3c\3c\3c\7c\3c\78\fc\7f"
  "\fc\7f\fc\3f\3c\00\3c\00\3c\00\3c\00\1c\00\00\00"

  ;; 480: 5
  "\00\00\fc\7f\fc\7f\fc\7f\00\78\00\78\f0\7f\f8\7f"
  "\fc\7f\3c\38\3c\00\7c\78\fc\7f\f8\7f\f0\3f\00\00"

  ;; 512: 6
  "\00\00\f8\0f\fc\1f\fc\3f\00\3e\00\3c\f0\7f\fc\7f"
  "\fc\7f\3e\7c\1e\7c\3e\7e\fe\3f\fc\3f\f8\0f\00\00"

  ;; 544: 7
  "\00\00\f8\3f\fe\7f\fe\7f\fe\3f\7e\00\7c\00\fc\00"
  "\f8\03\f0\07\e0\0f\c0\1f\80\3f\00\3f\00\1c\00\00"

  ;; 576: 8
  "\00\00\e0\07\f0\1f\f8\3f\7c\3e\3c\3c\3c\1e\f8\3f"
  "\fc\3f\fe\7f\3e\7c\1e\78\fe\3f\fc\3f\f8\1f\00\00"

  ;; 608: 9
  "\00\00\f0\1f\fc\3f\fc\7f\3e\7c\1e\78\1e\7e\fe\3f"
  "\fe\3f\fe\0f\3e\00\7e\78\fc\7f\f8\7f\f0\3f\00\00"

  ;; 640: SNAKE
  "\03\04\05\06\07"

  ;; 645: SCORE
  "\03\08\0a\09\07"

  ;; 650: 00000
  "\0a\0a\0a\0a\0a"
)

;; Palette data.
(data (i32.const 0x290)
  "\00\00\00\00"  ;; 0 0000 background
  "\28\A9\21\FF"  ;; 1 0001 snake
  "\28\A9\21\FF"  ;; 2 0010 snake head
  "\EE\EE\EE\FF"  ;; 3 0011 wall
  "\FF\FE\6B\FF"  ;; 4 0100 eye

  "\FF\21\37\FF"  ;; 5 0101 dead snake
  "\FF\21\37\FF"  ;; 6 0110 dead snake head
  "\00\00\00\00"  ;; 7 0111
  "\FF\27\B8\FF"  ;; 8 1000 food
)

(func $line (param $i i32) (param $di i32) (param $end i32) (param $color i32)
  (loop $loop
    (i32.store16 offset=0x2400
      (local.get $i)
      (local.get $color))
    (br_if $loop
      (i32.ne
        (local.tee $i (i32.add (local.get $i) (local.get $di)))
        (local.get $end)))))

(func $digit (param $i i32) (param $div i32)
  (i32.store8 offset=650
    (local.get $i)
    (i32.add
      (i32.rem_u
        (i32.div_u
          (global.get $score)
          (local.get $div))
        (i32.const 10))
      (i32.const 10))))

(func $score (param i32)
  (global.set $score (local.get 0))
  (call $digit (i32.const 0) (i32.const 10000))
  (call $digit (i32.const 1) (i32.const 1000))
  (call $digit (i32.const 2) (i32.const 100))
)

(func $start
  ;; reset snake color
  (i32.store (i32.const 0x294) (i32.const 0xff21a928))
  (i32.store (i32.const 0x298) (i32.const 0xff21a928))
  (global.set $x (f32.const 80))
  (global.set $y (f32.const 180))
  (global.set $angle (i32.const 1024))
  (global.set $speed (f32.const 0.6))
  (global.set $turnspeed (i32.const 12))
  (global.set $len (i32.const 0))
  (global.set $tolen (i32.const 40))
  (call $score (i32.const 0))
  (call $newfood)
)
(start $start)

(func $rand (param i32) (result i32)
  (i32.trunc_f32_u
    (f32.mul
      (f32.convert_i32_u (local.get 0))
      (call $random)))
)

(func $newfood
  (global.set $foodx (i32.add (call $rand (i32.const 200)) (i32.const 20)))
  (global.set $foody (i32.add (call $rand (i32.const 270)) (i32.const 30)))
)

(func $shake (param i32) (result i32)
  (i32.trunc_f32_s
    (f32.add
      (f32.convert_i32_s (local.get 0))
      (f32.mul
        (global.get $shake)
        (f32.sub (call $random) (f32.const 0.5))))))

(func $blit (param $px i32) (param $py i32) (param $data i32) (param $color i32)
            (result i32)
  (local $res i32)
  (local $addr i32)
  (local $bits i32)

  (local.set $px (call $shake (local.get $px)))
  (local.set $py (call $shake (local.get $py)))

  ;; calculate pixel address
  (local.set $addr
    (i32.add
      (i32.mul (local.get $py) (i32.const 240))
      (local.get $px)))

  ;; reuse px, py as loop variables.
  (local.set $py (i32.const 16))

  (loop $yloop
    (local.set $px (i32.const 16))
    (local.set $bits (i32.load16_u (local.get $data)))
    (local.set $data (i32.add (local.get $data) (i32.const 2)))
    (loop $xloop

      (local.set $bits (i32.rotl (local.get $bits) (i32.const 1)))
      (if
        (i32.and (local.get $bits) (i32.const 0x10000))
        (then
          ;; or together all previous bits, before drawing.
          (local.set $res
            (i32.or
              (local.get $res)
              (i32.load8_u offset=0x2400 (local.get $addr))))

          ;; draw new color
          (i32.store8 offset=0x2400
            (local.get $addr)
            (local.get $color))))

      (local.set $addr (i32.add (local.get $addr) (i32.const 1)))

      (br_if $xloop
        (local.tee $px (i32.sub (local.get $px) (i32.const 1)))))

    (local.set $addr (i32.add (local.get $addr) (i32.const 224)))

    (br_if $yloop
      (local.tee $py (i32.sub (local.get $py) (i32.const 1)))))

  (local.get $res)
)

(func $eye (param $xoff f32) (param $color i32) (result i32)
  (call $blit
    (i32.trunc_f32_s
      (f32.add
        (f32.add
          (global.get $x)
          (f32.mul (global.get $dx) (f32.const 8)))
        (f32.mul (global.get $dy) (local.get $xoff))))
    (i32.trunc_f32_s
      (f32.add
        (f32.add
          (global.get $y)
          (f32.mul (global.get $dy) (f32.const 8)))
        (f32.mul (global.get $dx) (f32.neg (local.get $xoff)))))
    (i32.const 64)
    (local.get $color))
)

(func $drawsnake (param $color i32) (param $eyecolor i32) (result i32)
  (local $i i32)

  (if (result i32)
    (global.get $len)
    (then
      (local.set $i (i32.shl (global.get $len) (i32.const 2)))

      (loop $loop
        (drop
          (call $blit
            (i32.load16_s offset=0x2fc (local.get $i))
            (i32.load16_s offset=0x2fe (local.get $i))
            (i32.const 0)
            (local.get $color)))
        (br_if $loop
          (local.tee $i (i32.sub (local.get $i) (i32.const 4)))))

      ;; draw the head in a different color, so it has no collision.
      (drop
        (call $blit
          (i32.trunc_f32_s (global.get $x))
          (i32.trunc_f32_s (global.get $y))
          (i32.const 0)
          (i32.add (local.get $color) (i32.const 1))))

      ;; if one of the eyes hit something, return the color.
      (i32.or
        (call $eye (f32.const 2.5) (local.get $eyecolor))
        (call $eye (f32.const -2.5) (local.get $eyecolor))))
    (else
      ;; didn't hit anything.
      (i32.const 0)))
)

(func $drawfood
  (drop
    (call $blit
      (global.get $foodx) (global.get $foody) (i32.const 32) (i32.const 8))))

(func $inccolor (param $addr i32) (param $amount i32)
  (i32.store
    (local.get $addr)
    (i32.add (i32.load (local.get $addr)) (local.get $amount))))

(func $snake (param $input i32)
  (local $i i32)

  (local.set $i (i32.shl (global.get $tolen) (i32.const 2)))
  (loop $loop
    ;; move node[i] -> node[i+1]
    (i32.store offset=0x2fc (local.get $i)
      (i32.load offset=0x2f8 (local.get $i)))
    (br_if $loop
      (local.tee $i (i32.sub (local.get $i) (i32.const 4)))))

  ;; write old head x/y to front.
  (i32.store16 offset=0x300 (i32.const 0) (i32.trunc_f32_s (global.get $x)))
  (i32.store16 offset=0x302 (i32.const 0) (i32.trunc_f32_s (global.get $y)))

  ;; rotate snake from input
  (global.set $angle
    (i32.and
      (i32.add
        (global.get $angle)
        (i32.mul (local.get $input) (global.get $turnspeed)))
    (i32.const 0xfff)))

  ;; calculate new dx and dy
  (global.set $dx
    (call $sin
      (f32.mul (f32.convert_i32_s (i32.add (global.get $angle) (i32.const 1024)))
      (f32.const 0.0015339807878856412))))
  (global.set $dy
    (call $sin
      (f32.mul (f32.convert_i32_s (global.get $angle))
      (f32.const 0.0015339807878856412))))

  ;; x += dx
  (global.set $x
    (f32.add
      (global.get $x)
      (f32.mul (global.get $dx) (global.get $speed))))
  ;; y += dy
  (global.set $y
    (f32.add
      (global.get $y)
      (f32.mul (global.get $dy) (global.get $speed))))

  ;; make snake longer, if necessary
  (if
    (i32.lt_u (global.get $len) (global.get $tolen))
    (then
      (global.set $len (i32.add (global.get $len) (i32.const 1)))))

  (local.set $i (call $drawsnake (i32.const 1) (i32.const 4)))

  ;; if we hit a color w/ low bit set, die.
  (if (i32.and (local.get $i) (i32.const 1))
    (then
      (global.set $mode (i32.const 2))
      (global.set $shake (f32.const 5))
      (global.set $timer (i32.const 0))))

  ;; if hit food
  (if (i32.and (local.get $i) (i32.const 8))
    (then
      (call $newfood)
      ;; shake screen
      (global.set $shake (f32.const 2))
      ;; update turn speed, and clamp
      (if (i32.lt_u (global.get $turnspeed) (i32.const 40))
        (then
          (global.set $turnspeed (i32.add (global.get $turnspeed) (i32.const 1)))
          ;; update speed
          (global.set $speed (f32.add (global.get $speed) (f32.const 0.05)))
          ;; change snake color
          (call $inccolor (i32.const 0x294) (i32.const 0x307))
          (call $inccolor (i32.const 0x298) (i32.const 0x307))))

      ;; update snake length, and clamp
      (if (i32.lt_u (global.get $tolen) (i32.const 900))
        (then (global.set $tolen (i32.add (global.get $tolen) (i32.const 10)))))
      ;; update score
      (call $score (i32.add (global.get $score) (i32.const 100)))))
)

(func $string (param $x i32) (param $y i32) (param $addr i32) (param $color i32)
  (local $endx i32)
  (local.set $endx (i32.add (local.get $x) (i32.const 85)))
  (loop $loop
    (drop
      (call $blit
        (local.get $x)
        (local.get $y)
        (i32.shl
          (i32.load8_u (local.get $addr))
          (i32.const 5))
        (local.get $color)))
    (local.set $addr (i32.add (local.get $addr) (i32.const 1)))
    (br_if $loop
      (i32.ne
        (local.tee $x (i32.add (local.get $x) (i32.const 17)))
        (local.get $endx)))))

(func (export "run")
  (local $i i32)
  (local $input i32)

  (global.set $timer (i32.add (global.get $timer) (i32.const 1)))
  (global.set $shake
    (f32.max (f32.sub (global.get $shake) (f32.const 0.1)) (f32.const 0)))

  (local.set $input
    (i32.sub
      (i32.load8_u offset=0x2c1 (i32.const 0))
      (i32.load8_u offset=0x2c0 (i32.const 0))))

  ;; clear screen
  (call $line (i32.const 0) (i32.const 2) (i32.const 76800) (i32.const 0))

  ;; top two rows
  (call $line (i32.const 0) (i32.const 2) (i32.const 480) (i32.const 0x303))
  ;; bottom two rows
  (call $line (i32.const 76320) (i32.const 2) (i32.const 76800) (i32.const 0x303))
  ;; left two columns
  (call $line (i32.const 480) (i32.const 240) (i32.const 76320) (i32.const 0x303))

  (call $line (i32.const 718) (i32.const 240) (i32.const 76558) (i32.const 0x303))

  ;; draw SCORE
  (call $string (i32.const 8) (i32.const 8) (i32.const 645) (i32.const 3))
  (call $string (i32.const 146) (i32.const 8) (i32.const 650) (i32.const 3))

  (block $done
    (block $button
      (block $title
        (block $playing
          (block $dead
            (br_table $title $playing $dead (global.get $mode)))

          ;; $dead
          (drop (call $drawsnake (i32.const 5) (i32.const 5)))
          (br $button))

        ;; $playing:
        (call $drawfood)  ;; draw before so it can be seen by snake.
        (call $snake (local.get $input))
        (call $drawfood)  ;; draw after so it is always displayed on top.
        (br $done))

      ;; $title
      ;; draw the snake going in a circle; force input
      (call $snake (i32.const -1)))

    ;; $button
    ;; draw SNAKE
    (call $string (i32.const 76) (i32.const 132) (i32.const 640) (i32.const 3))

    ;; start playing on input from user
    (if
      (i32.and
        (local.get $input)
        (i32.ge_u (global.get $timer) (i32.const 60)))
      (then
        (call $start)
        (global.set $mode (i32.const 1)))))

  ;; copy from 1bpp to 4bpp using palette
  (loop $loop
    (i32.store offset=0x15000
      (i32.shl (local.get $i) (i32.const 2))
      (i32.load offset=0x290
        (i32.shl
          (i32.load8_u offset=0x2400 (local.get $i))
          (i32.const 2))))
    (br_if $loop
      (i32.ne
        (local.tee $i (i32.add (local.get $i) (i32.const 1)))
        (i32.const 76800))))
)
