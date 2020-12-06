(import "Math" "random" (func $random (result f32)))

;; [0x3000, 0x19000)  Color[300*75]  canvas
(memory (export "mem") 2)

(data (i32.const 4)
  ;; +0 dead.ppm 20 22
  (i8 20 22 83)
  "\00\f8\07\c0\f8\00\ac\0f\c0\f8\00\fc\0f\c0\ff\00\fc\0f\c0\3f\01\3e\10\f0"
  "\03\c3\ff\70\fe\0b\ff\3f\f0\ff\03\fe\1f\c0\ff\01\f8\0f\00\7f\00\e0\06\00"
  "\46\00\20\04\00\c6\00"

  ;; +58 stand.ppm 20 22
  (i8 20 22 83)
  "\00\f8\07\c0\ff\00\ec\0f\c0\ff\00\fc\0f\c0\ff\00\7c\00\c0\3f\01\3e\10\f0"
  "\03\c3\ff\70\fe\0b\ff\3f\f0\ff\03\fe\1f\c0\ff\01\f8\0f\00\7f\00\e0\06\00"
  "\46\00\20\04\00\c6\00"

  ;; +116 run1.ppm 20 22
  (i8 20 22 83)
  "\00\f8\07\c0\ff\00\ec\0f\c0\ff\00\fc\0f\c0\ff\00\7c\00\c0\3f\01\3e\10\f0"
  "\03\c3\ff\70\fe\0b\ff\3f\f0\ff\03\fe\1f\c0\ff\01\f8\0f\00\7f\00\e0\1c\00"
  "\06\00\20\00\00\06\00"

  ;; +174 run2.ppm 20 22
  (i8 20 22 83)
  "\00\f8\07\c0\ff\00\ec\0f\c0\ff\00\fc\0f\c0\ff\00\7c\00\c0\3f\01\3e\10\f0"
  "\03\c3\ff\70\fe\0b\ff\3f\f0\ff\03\fe\1f\c0\ff\01\f8\0f\00\7f\00\60\06\00"
  "\4c\00\00\04\00\c0\00"

  ;; +232 duck1.ppm 28 13
  (i8 28 13 83)
  "\01\00\f8\77\f8\cf\ff\ff\ff\ef\ef\ff\ff\ff\fc\ff\ff\8f\ff\ff\ff\f0\ff\7f"
  "\00\fe\9f\3f\c0\8f\00\00\e4\18\00\c0\06\00\00\20\00\00\00\06\00\00"

  ;; +281 duck2.ppm 28 13
  (i8 28 13 83)
  "\01\00\f8\77\f8\cf\ff\ff\ff\ef\ef\ff\ff\ff\fc\ff\ff\8f\ff\ff\ff\f0\ff\7f"
  "\00\fe\9f\3f\c0\8f\00\00\9c\1b\00\c0\00\00\00\04\00\00\c0\00\00\00"

  ;; +330 cactus1.ppm 13 26
  (i8 13 26 83)
  "\e0\00\3e\c0\07\f8\00\1f\e0\03\7c\92\ef\f7\fd\be\df\f7\fb\7e\df\ef\fb\7d"
  "\ff\7f\ff\c7\3f\c0\07\f8\00\1f\e0\03\7c\80\0f\f0\01\3e\00"

  ;; +376 cactus2.ppm 19 18
  (i8 19 18 83)
  "\18\60\c0\01\07\4e\bb\70\db\9d\db\ee\dd\76\ef\b6\7b\b7\df\fb\f9\de\07\ff"
  "\0f\f8\7c\c0\81\03\0e\1c\70\e0\80\03\07\1c\38\e0\c0\01\07"

  ;; +422 cactus3.ppm 28 18
  (i8 28 18 83)
  "\38\e0\80\81\03\0e\18\b8\ed\b0\81\db\0e\db\b8\ed\b6\bd\db\6e\db\bb\ed\b6"
  "\bd\db\6e\db\fb\ed\f6\bd\cf\6e\fe\3f\ec\86\e7\c3\6f\18\38\f8\87\81\03\3e"
  "\18\38\e0\80\81\03\0e\18\38\e0\80\81\03\0e\18"

  ;; +488 cactus4.ppm 9 18
  (i8 9 18 83)
  "\38\70\e0\c0\bd\7b\f7\ee\dd\fb\f7\fd\f0\81\03\07\0e\1c\38\70\00"

  ;; +512 cactus5.ppm 40 26
  (i8 40 26 83)
  "\c0\00\00\00\06\e0\01\04\00\0f\e0\01\0e\00\0f\e0\01\0e\00\0f\e0\01\0e\70"
  "\0f\e0\01\6e\70\0f\e0\01\6e\70\0f\e2\19\6e\70\cf\e7\19\6e\70\cf\e7\19\6e"
  "\70\cf\e7\d9\7e\70\cf\e7\d9\3e\f2\cf\e7\d9\0e\e3\cf\e7\d9\0e\c3\cf\e7\d9"
  "\6e\1b\cf\fe\df\6e\1b\ff\fe\cf\6e\1b\7f\f8\c1\6f\1b\0f\e0\81\6f\1b\0f\e0"
  "\01\ee\1f\0f\e0\01\ce\0f\0f\e0\01\0e\03\0f\e0\01\0e\03\0f\e0\01\0e\03\0f"
  "\e0\01\0e\03\0f\e0\01\0e\03\0f"

  ;; +645 cloud.ppm 26 8
  (i8 26 8 218)
  "\00\f8\01\00\30\08\00\20\60\00\c0\40\0e\f0\00\c0\20\00\00\84\00\00\60\f1"
  "\ff\ff"

  ;; +674 ground1.ppm 32 5
  (i8 32 5 83)
  "\ff\ff\ff\ff\00\00\00\00\02\00\00\10\c0\00\00\00\00\00\c0\00"

  ;; +697 ground2.ppm 32 5
  (i8 32 5 83)
  "\ff\ff\ff\ff\00\00\00\00\00\00\00\08\00\00\00\00\10\40\00\00"

  ;; +720 ground3.ppm 32 5
  (i8 32 5 83)
  "\ff\ff\ff\ff\00\00\00\00\08\30\00\00\00\00\00\40\00\00\00\40"
)

;; objects
(data (i32.const 746)
  ;; x dx y img
  (f32 22 0 40) (i16 62)
  (f32 0 -1.5 57) (i16 678)
  (f32 32 -1.5 57) (i16 678)
  (f32 64 -1.5 57) (i16 678)
  (f32 96 -1.5 57) (i16 678)
  (f32 128 -1.5 57) (i16 678)
  (f32 160 -1.5 57) (i16 678)
  (f32 192 -1.5 57) (i16 678)
  (f32 224 -1.5 57) (i16 678)
  (f32 256 -1.5 57) (i16 678)
  (f32 288 -1.5 57) (i16 678)
  (f32 320 -1.5 57) (i16 678)
  (f32 352 -1.5 57) (i16 678)
)

(func $blit (param $obj i32) (result i32)

  (local $x i32)
  (local $y i32)

  (local $w i32)
  (local $h i32)
  (local $src_addr i32)
  (local $color i32)

  (local $dst_addr i32)
  (local $src_stride_bits i32)
  (local $src_stride_bytes i32)
  (local $src_stride_rot i32)
  (local $rot i32)
  (local $ix i32)
  (local $result i32)
  (local $bits i32)
  (local $data i64)

  (local.set $x (i32.trunc_f32_s (f32.load (local.get $obj))))
  (local.set $y (i32.trunc_f32_s (f32.load offset=8 (local.get $obj))))
  (local.set $obj (i32.load16_u offset=12 (local.get $obj)))

  (local.set $w (i32.load8_u (local.get $obj)))
  (local.set $h (i32.load8_u offset=1 (local.get $obj)))
  ;; TODO(fix)
  (local.set $color
    (i32.shl
      (i32.sub
        (i32.const 255)
        (i32.load8_u offset=2 (local.get $obj)))
      (i32.const 24)))
  (local.set $src_addr (i32.add (local.get $obj) (i32.const 3)))

  ;; if (y < 0)
  (if
    (i32.lt_s (local.get $y) (i32.const 0))
    (then
      ;; y = -y
      (local.set $y (i32.sub (i32.const 0) (local.get $y)))
      ;; reduce height by y
      (local.set $h (i32.sub (local.get $h) (local.get $y)))

      ;; bits = w * y
      (local.set $bits (i32.mul (local.get $w) (local.get $y)))

      ;; advance src_addr by (w * y bits)
      (local.set $src_addr
        (i32.add
          (local.get $src_addr)
          (i32.shr_u
            (local.get $bits)
            (i32.const 3))))
      (local.set $rot
        (i32.and
          (local.get $bits)
          (i32.const 7)))

      (local.set $y (i32.const 0)))

    (else
      ;; if (y + h > SCREEN_HEIGHT)
      (if
        (i32.gt_s (i32.add (local.get $y) (local.get $h)) (i32.const 75))
        (then
          ;; h = SCREEN_HEIGHT - y
          (local.set $h
            (i32.sub
              (i32.const 75)
              (local.get $y)))))))

  ;; if (x < 0)
  (if
    (i32.lt_s (local.get $x) (i32.const 0))
    (then
      ;; x = -x
      (local.set $x (i32.sub (i32.const 0) (local.get $x)))
      ;; reduce width by x
      (local.set $w (i32.sub (local.get $w) (local.get $x)))

      ;; increase src_stride by x
      (local.set $src_stride_bits (local.get $x))

      ;; advance src_addr by x bits
      (local.set $src_addr
        (i32.add
          (local.get $src_addr)
          (i32.shr_u
            (local.get $x)
            (i32.const 3))))
      (local.set $rot
        (i32.add
          (local.get $rot)
          (i32.and
            (local.get $x)
            (i32.const 7))))

      (local.set $x (i32.const 0)))
    (else
      ;; if (x + w > SCREEN_WIDTH)
      (if
        (i32.gt_s (i32.add (local.get $x) (local.get $w)) (i32.const 300))
        (then
          ;; increase src_stride by clipped width (done below)
          (local.set $src_stride_bits
            (i32.sub (i32.add (local.get $x) (local.get $w)) (i32.const 300)))

          ;; w = SCREEN_WIDTH - x
          (local.set $w (i32.sub (i32.const 300) (local.get $x)))))))

  ;; if (w <= 0 || h <= 0) { return 0; }
  (if
    (i32.or
      (i32.le_s (local.get $w) (i32.const 0))
      (i32.le_s (local.get $h) (i32.const 0)))
    (then
      (return (i32.const 0))))

  ;; src_stride_bits += w
  (local.set $src_stride_bits
    (i32.add (local.get $src_stride_bits) (local.get $w)))

  ;; src_stride = src_stride_bits / 8
  (local.set $src_stride_bytes
    (i32.shr_u (local.get $src_stride_bits) (i32.const 3)))

  ;; src_stride_rot = src_stride_bits % 8
  (local.set $src_stride_rot
    (i32.and (local.get $src_stride_bits) (i32.const 7)))

  ;; dst_addr = 0x3000 + (y * SCREEN_WIDTH + x) * 4
  (local.set $dst_addr
    (i32.add
      (i32.const 0x3000)
      (i32.shl
        (i32.add
          (i32.mul
            (local.get $y)
            (i32.const 300))
          (local.get $x))
        (i32.const 2))))

  (loop $yloop
    ;; src_addr += rot / 8;
    (local.set $src_addr
      (i32.add
        (local.get $src_addr)
        (i32.shr_u (local.get $rot) (i32.const 3))))

    ;; rot %= 8;
    (local.set $rot (i32.and (local.get $rot) (i32.const 7)))

    ;; data = i64_mem[src_addr] >> rot;
    (local.set $data
      (i64.shr_u
        (i64.load (local.get $src_addr))
        (i64.extend_i32_u (local.get $rot))))

    ;; ix = 0;
    (local.set $ix (i32.const 0))

    (loop $xloop
      ;; if (data & 1)
      (if
        (i32.wrap_i64 (i64.and (local.get $data) (i64.const 1)))
        (then
          ;; get old pixel
          (local.set $result
            (i32.or
              (local.get $result)
              (i32.load (local.get $dst_addr))))

          ;; set new pixel
          (i32.store (local.get $dst_addr) (local.get $color))))

      ;; data >>= 1
      (local.set $data (i64.shr_u (local.get $data) (i64.const 1)))

      (local.set $dst_addr (i32.add (local.get $dst_addr) (i32.const 4)))

      ;; loop while (++ix < w)
      (br_if $xloop
        (i32.lt_s
          (local.tee $ix (i32.add (local.get $ix) (i32.const 1)))
          (local.get $w))))

    ;; dst_addr += SCREEN_WIDTH - w * 4;
    (local.set $dst_addr
      (i32.sub
        (i32.add
          (local.get $dst_addr)
          (i32.const 1200))
        (i32.shl (local.get $w) (i32.const 2))))
    ;; src_addr += src_stride;
    (local.set $src_addr
      (i32.add (local.get $src_addr) (local.get $src_stride_bytes)))
    ;; rot += src_stride_rot;
    (local.set $rot (i32.add (local.get $rot) (local.get $src_stride_rot)))

    ;; loop while (--h != 0)
    (br_if $yloop
      (local.tee $h (i32.sub (local.get $h) (i32.const 1)))))

  (local.get $result))

(func $move (param $obj i32)
  (local $x f32)
  (local.set $x
    (f32.add
      (f32.load (local.get $obj))
      (f32.load offset=4 (local.get $obj))))

  (if
    (f32.lt (local.get $x) (f32.const -32))
    (then
      (local.set $x
        (f32.add
          (local.get $x)
          (f32.const 352)))))

  (f32.store (local.get $obj) (local.get $x)))

(func (export "run")
  (local $i i32)

  ;; clear screen
  (loop $loop

    (i32.store offset=0x3000
      (local.get $i)
      (i32.const 0xff_ffffff))

    ;; loop on x
    (br_if $loop
      (i32.lt_s
        (local.tee $i (i32.add (local.get $i) (i32.const 4)))
        (i32.const 90000))))

  ;; blit dino
  (drop (call $blit (i32.const 746)))

  (local.set $i (i32.const 760))
  (loop $blit
    (drop (call $blit (local.get $i)))
    (call $move (local.get $i))

    ;; loop on x
    (br_if $blit
      (i32.lt_s
        (local.tee $i (i32.add (local.get $i) (i32.const 14)))
        (i32.const 928))))

  )
