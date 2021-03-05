;; Memory map:
;;
;; [0x00000 .. 0x00000]  X mouse position
;; [0x00001 .. 0x00001]  Y mouse position
;; [0x00002 .. 0x00002]  mouse buttons
;; [0x00100 .. 0x00500]  16x16xRGBA sprite data
;; [0x10000 .. 0x25f90]  150x150xRGBA data (4 bytes per pixel)
(memory (export "mem") 3)

(func (export "run")
  (call $clear-screen (i32.const 0)) ;; transparent black

  (call $draw-sprite
    (i32.const 0) (i32.const 0)
    (i32.const 16) (i32.const 16)
    (i32.const 0x100)
  )

  (call $draw-sprite
    (i32.load8_u (i32.const 0))  ;; X
    (i32.load8_u (i32.const 1))  ;; Y
    (i32.const 16)
    (i32.const 16)
    (i32.const 0x100)
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

(func $draw-sprite (param $x i32) (param $y i32)
                   (param $w i32) (param $h i32)
                   (param $src i32)
  (local $i i32)
  (local $j i32)
  (local $pixel i32)
  ;; for (j = 0; j < h; j++)
  (loop $y-loop
    (local.set $i (i32.const 0))
    ;; for (i = 0; i < w; i++)
    (loop $x-loop
      ;; pixel = mem[src + (w * j + i) * 4]
      (local.set $pixel
        (i32.load
          (i32.add
            (i32.mul
              (i32.add
                (i32.mul (local.get $w) (local.get $j))
                (local.get $i))
              (i32.const 4))
            (local.get $src))))

      ;; if (pixel != 0)
      (if (local.get $pixel)
        (then
          ;; put-pixel(x + i, y + j, pixel)
          (call $put-pixel
            (i32.add (local.get $x) (local.get $i))
            (i32.add (local.get $y) (local.get $j))
            (local.get $pixel))))

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

(data (i32.const 0x100)
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\df\71\26\ff\df\71\26\ff"
  "\df\71\26\ff\df\71\26\ff\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\df\71\26\ff\df\71\26\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\df\71\26\ff\df\71\26\ff"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\df\71\26\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\df\71\26\ff\00\00\00\00\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\df\71\26\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\df\71\26\ff\00\00\00\00\00\00\00\00"
  "\00\00\00\00\df\71\26\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\df\71\26\ff\00\00\00\00"
  "\00\00\00\00\df\71\26\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\df\71\26\ff\00\00\00\00"
  "\df\71\26\ff\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff\df\71\26\ff"
  "\df\71\26\ff\fb\f2\36\ff\66\39\31\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\66\39\31\ff\fb\f2\36\ff\df\71\26\ff"
  "\df\71\26\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\66\39\31\ff\fb\f2\36\ff\df\71\26\ff"
  "\df\71\26\ff\fb\f2\36\ff\66\39\31\ff\66\39\31\ff"
  "\66\39\31\ff\66\39\31\ff\66\39\31\ff\66\39\31\ff"
  "\66\39\31\ff\66\39\31\ff\66\39\31\ff\66\39\31\ff"
  "\66\39\31\ff\66\39\31\ff\fb\f2\36\ff\df\71\26\ff"
  "\00\00\00\00\df\71\26\ff\fb\f2\36\ff\66\39\31\ff"
  "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"
  "\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff"
  "\66\39\31\ff\fb\f2\36\ff\df\71\26\ff\00\00\00\00"
  "\00\00\00\00\df\71\26\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\66\39\31\ff\66\39\31\ff\66\39\31\ff\66\39\31\ff"
  "\66\39\31\ff\66\39\31\ff\66\39\31\ff\66\39\31\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\df\71\26\ff\00\00\00\00"
  "\00\00\00\00\00\00\00\00\df\71\26\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\66\39\31\ff\66\39\31\ff\66\39\31\ff"
  "\66\39\31\ff\66\39\31\ff\66\39\31\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\df\71\26\ff\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\df\71\26\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\fb\f2\36\ff\66\39\31\ff"
  "\66\39\31\ff\66\39\31\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\df\71\26\ff\00\00\00\00\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\df\71\26\ff\df\71\26\ff\fb\f2\36\ff\fb\f2\36\ff"
  "\fb\f2\36\ff\fb\f2\36\ff\df\71\26\ff\df\71\26\ff"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\df\71\26\ff\df\71\26\ff"
  "\df\71\26\ff\df\71\26\ff\00\00\00\00\00\00\00\00"
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00"
)
