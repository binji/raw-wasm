;; Memory map:
;;
;; [0x00000 .. 0x00000]  X mouse position
;; [0x00001 .. 0x00001]  Y mouse position
;; [0x00002 .. 0x00002]  mouse buttons
;; [0x10000 .. 0x25f90]  150x150xRGBA data (4 bytes per pixel)
(memory (export "mem") 3)

(func (export "run")
  (call $clear-screen (i32.const 0xff_00_00_00))  ;; ABGR format

  (call $fill-rect
    (i32.load8_u (i32.const 0))  ;; X
    (i32.load8_u (i32.const 1))  ;; Y
    (i32.const 5)
    (i32.const 5)
    (select
      (i32.const 0xff_00_00_ff)  ;; Red
      (i32.const 0xff_ff_00_00)  ;; Blue
      (i32.load8_u (i32.const 2)))
  )
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

(func $put-pixel (param $x i32) (param $y i32) (param $color i32)
  ;; mem[0x10000 + (y * 150 + x) * 4] = color
  (i32.store offset=0x10000
    (i32.mul
      (i32.add
        (i32.mul (local.get $y) (i32.const 150))
        (local.get $x))
      (i32.const 4))
    (local.get $color))
)

(func $fill-rect (param $x i32) (param $y i32)
                 (param $w i32) (param $h i32)
                 (param $color i32)
  (local $i i32)
  (local $j i32)
  ;; for (j = 0; j < h; j++)
  (loop $y-loop
    (local.set $i (i32.const 0))
    ;; for (i = 0; i < w; i++)
    (loop $x-loop
      ;; put-pixel(x + i, y + j, color)
      (call $put-pixel
        (i32.add (local.get $x) (local.get $i))
        (i32.add (local.get $y) (local.get $j))
        (local.get $color))

      ;; i += 1
      (local.set $i (i32.add (local.get $i) (i32.const 1)))

      ;; loop if i < w
      (br_if $x-loop (i32.lt_s (local.get $i) (local.get $w)))
    )
    ;; j += 1
    (local.set $j (i32.add (local.get $j) (i32.const 1)))

    ;; loop if j < h
    (br_if $y-loop (i32.lt_s (local.get $j) (local.get $h)))
  )
)
