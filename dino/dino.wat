(import "Math" "random" (func $random (result f32)))

;; 0x0                Left
;; 0x1                Right
;; 0x2                Up
;; 0x3                Down
;; [0x4, 0x0743)      Image data
;; [0x3000, 0x19000)  Color[300*75]  canvas
(memory (export "mem") 2)

(global $timer (mut i32) (i32.const 0))
(global $dino_state (mut i32) (i32.const 0))
(global $jump_vel (mut f32) (f32.const 0))
(global $speed (mut f32) (f32.const -2))

(data (i32.const 4)
  ;; =4 dead.ppm 20 22
  (i8 20 22 83)
  "\00\f8\07\c0\f8\00\ac\0f\c0\f8\00\fc\0f\c0\ff\00\fc\0f\c0\3f\01\3e\10\f0"
  "\03\c3\ff\70\fe\0b\ff\3f\f0\ff\03\fe\1f\c0\ff\01\f8\0f\00\7f\00\e0\06\00"
  "\46\00\20\04\00\c6\00"

  ;; =62 stand.ppm 20 22
  (i8 20 22 83)
  "\00\f8\07\c0\ff\00\ec\0f\c0\ff\00\fc\0f\c0\ff\00\7c\00\c0\3f\01\3e\10\f0"
  "\03\c3\ff\70\fe\0b\ff\3f\f0\ff\03\fe\1f\c0\ff\01\f8\0f\00\7f\00\e0\06\00"
  "\46\00\20\04\00\c6\00"

  ;; =120 run1.ppm 20 22
  (i8 20 22 83)
  "\00\f8\07\c0\ff\00\ec\0f\c0\ff\00\fc\0f\c0\ff\00\7c\00\c0\3f\01\3e\10\f0"
  "\03\c3\ff\70\fe\0b\ff\3f\f0\ff\03\fe\1f\c0\ff\01\f8\0f\00\7f\00\e0\1c\00"
  "\06\00\20\00\00\06\00"

  ;; =178 run2.ppm 20 22
  (i8 20 22 83)
  "\00\f8\07\c0\ff\00\ec\0f\c0\ff\00\fc\0f\c0\ff\00\7c\00\c0\3f\01\3e\10\f0"
  "\03\c3\ff\70\fe\0b\ff\3f\f0\ff\03\fe\1f\c0\ff\01\f8\0f\00\7f\00\60\06\00"
  "\4c\00\00\04\00\c0\00"

  ;; =236 duck1.ppm 28 13
  (i8 28 13 83)
  "\01\00\f8\77\f8\cf\ff\ff\ff\ef\ef\ff\ff\ff\fc\ff\ff\8f\ff\ff\ff\f0\ff\7f"
  "\00\fe\9f\3f\c0\8f\00\00\e4\18\00\c0\06\00\00\20\00\00\00\06\00\00"

  ;; =285 duck2.ppm 28 13
  (i8 28 13 83)
  "\01\00\f8\77\f8\cf\ff\ff\ff\ef\ef\ff\ff\ff\fc\ff\ff\8f\ff\ff\ff\f0\ff\7f"
  "\00\fe\9f\3f\c0\8f\00\00\9c\1b\00\c0\00\00\00\04\00\00\c0\00\00\00"

  ;; =334 cactus1.ppm 13 26
  (i8 13 26 83)
  "\e0\00\3e\c0\07\f8\00\1f\e0\03\7c\92\ef\f7\fd\be\df\f7\fb\7e\df\ef\fb\7d"
  "\ff\7f\ff\c7\3f\c0\07\f8\00\1f\e0\03\7c\80\0f\f0\01\3e\00"

  ;; =380 cactus2.ppm 19 18
  (i8 19 18 83)
  "\18\60\c0\01\07\4e\bb\70\db\9d\db\ee\dd\76\ef\b6\7b\b7\df\fb\f9\de\07\ff"
  "\0f\f8\7c\c0\81\03\0e\1c\70\e0\80\03\07\1c\38\e0\c0\01\07"

  ;; =426 cactus3.ppm 28 18
  (i8 28 18 83)
  "\38\e0\80\81\03\0e\18\b8\ed\b0\81\db\0e\db\b8\ed\b6\bd\db\6e\db\bb\ed\b6"
  "\bd\db\6e\db\fb\ed\f6\bd\cf\6e\fe\3f\ec\86\e7\c3\6f\18\38\f8\87\81\03\3e"
  "\18\38\e0\80\81\03\0e\18\38\e0\80\81\03\0e\18"

  ;; =492 cactus4.ppm 9 18
  (i8 9 18 83)
  "\38\70\e0\c0\bd\7b\f7\ee\dd\fb\f7\fd\f0\81\03\07\0e\1c\38\70\00"

  ;; =516 cactus5.ppm 40 26
  (i8 40 26 83)
  "\c0\00\00\00\06\e0\01\04\00\0f\e0\01\0e\00\0f\e0\01\0e\00\0f\e0\01\0e\70"
  "\0f\e0\01\6e\70\0f\e0\01\6e\70\0f\e2\19\6e\70\cf\e7\19\6e\70\cf\e7\19\6e"
  "\70\cf\e7\d9\7e\70\cf\e7\d9\3e\f2\cf\e7\d9\0e\e3\cf\e7\d9\0e\c3\cf\e7\d9"
  "\6e\1b\cf\fe\df\6e\1b\ff\fe\cf\6e\1b\7f\f8\c1\6f\1b\0f\e0\81\6f\1b\0f\e0"
  "\01\ee\1f\0f\e0\01\ce\0f\0f\e0\01\0e\03\0f\e0\01\0e\03\0f\e0\01\0e\03\0f"
  "\e0\01\0e\03\0f\e0\01\0e\03\0f"

  ;; =649 cloud.ppm 26 8
  (i8 26 8 218)
  "\00\f8\01\00\30\08\00\20\60\00\c0\40\0e\f0\00\c0\20\00\00\84\00\00\60\f1"
  "\ff\ff"

  ;; =678 ground1.ppm 32 5
  (i8 32 5 83)
  "\ff\ff\ff\ff\00\00\00\00\02\00\00\10\c0\00\00\00\00\00\c0\00"

  ;; =701 ground2.ppm 32 5
  (i8 32 5 83)
  "\ff\ff\ff\ff\00\00\00\00\00\00\00\08\00\00\00\00\10\40\00\00"

  ;; =724 ground3.ppm 32 5
  (i8 32 5 83)
  "\ff\ff\ff\ff\00\00\00\00\08\30\00\00\00\00\00\40\00\00\00\40"

  ;; =747 bird1.ppm 23 14
  (i8 23 14 83)
  "\80\01\00\c0\01\00\e0\01\00\e6\01\80\f3\01\e0\fb\01\f8\fd\01\fe\ff\00\c0"
  "\ff\00\c0\ff\3f\c0\ff\03\c0\ff\07\c0\7f\00\c0\1f\00"

  ;; =791 bird2.ppm 23 16
  (i8 23 16 83)
  "\30\00\00\1c\00\00\1f\00\c0\0f\00\f0\ff\07\00\fe\07\00\fe\ff\01\fe\1f\00"
  "\ff\3f\80\ff\03\c0\ff\00\e0\01\00\70\00\00\18\00\00\0c\00\00\02\00"

  ;; +836
)

;; objects  20 * 9 bytes = 180 bytes
(data (i32.const 900)
  ;; kind       x  y

  ;; obstacles x 4
  (i8 1)  (f32 300 55)
  (i8 1)  (f32 600 55)
  (i8 1)  (f32 900 55)

  ;; dino
  (i8 11) (f32 22 50)

  ;; ground x 12
  (i8 7)  (f32   0 67)
  (i8 8)  (f32  32 67)
  (i8 9)  (f32  64 67)
  (i8 7)  (f32  96 67)
  (i8 8)  (f32 128 67)
  (i8 9)  (f32 160 67)
  (i8 7)  (f32 192 67)
  (i8 8)  (f32 224 67)
  (i8 9)  (f32 256 67)
  (i8 7)  (f32 288 67)
  (i8 8)  (f32 320 67)
  (i8 9)  (f32 352 67)

  ;; clouds x 3
  (i8 6)  (f32   0 40)
  (i8 6)  (f32 128 40)
  (i8 6)  (f32 256 40)
  (i8 6)  (f32 384 40)

  ;; end=1080
)

;; info  14 * 11 bytes = 154 bytes
(data (i32.const 1100)
  ;;  id anim       img      +4x  y +y     *dx
  (i8  0    0) (i16 334) (i8  75 46  0) (f32 1)     ;;  0 cactus1
  (i8  0    0) (i16 380) (i8  75 54  0) (f32 1)     ;;  1 cactus2
  (i8  0    0) (i16 426) (i8  75 54  0) (f32 1)     ;;  2 cactus3
  (i8  0    0) (i16 492) (i8  75 54  0) (f32 1)     ;;  3 cactus4
  (i8  0    0) (i16 516) (i8  75 46  0) (f32 1)     ;;  4 cactus5
  (i8  0    3) (i16 747) (i8  75 25 25) (f32 1.25)  ;;  5 bird
  (i8  1    0) (i16 649) (i8  30 15 25) (f32 0.25)  ;;  6 cloud
  (i8  2    0) (i16 678) (i8   0 67  0) (f32 1)     ;;  7 ground1
  (i8  2    0) (i16 701) (i8   0 67  0) (f32 1)     ;;  8 ground2
  (i8  2    0) (i16 724) (i8   0 67  0) (f32 1)     ;;  9 ground3
  (i8  3    0) (i16  62) (i8   0  0  0) (f32 0)     ;; 10 dino stand
  (i8  3    1) (i16 120) (i8   0  0  0) (f32 0)     ;; 11 dino run
  (i8  3    2) (i16 236) (i8   0  0  0) (f32 0)     ;; 12 dino duck
  (i8  3    0) (i16   4) (i8   0  0  0) (f32 0)     ;; 13 dino dead
  ;; end=1254
)

;; random id  3 * 2 bytes = 6 bytes
(data (i32.const 1254)
  (i8 0 6)
  (i8 6 1)
  (i8 7 3)
  ;; end=1260
)

;; anims (y addend)  4 * 4 bytes = 16 bytes
(data (i32.const 1260)
  (i8 0 0 0 0)  ;; 0 none
  (i8 0 0 0 0)  ;; 1 run
  (i8 9 9 9 9)  ;; 2 duck
  (i8 0 0 3 3)  ;; 3 bird
  ;; end=1276
)

;; anims (img addend)  4 * 4 bytes = 16 bytes
(data (i32.const 1276)
  (i8 0  0  0  0)  ;; 0 none
  (i8 0 58  0 58)  ;; 1 run
  (i8 0 49  0 49)  ;; 2 duck
  (i8 0  0 44 44)  ;; 3 bird
  ;; end=1292
)


(func $blit (param $obj i32) (result i32)
  (local $kind i32)
  (local $anim i32)
  (local $x i32)
  (local $y i32)
  (local $img i32)
  (local $info i32)

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
  (local $hit i32)
  (local $bits i32)
  (local $data i64)

  (local.set $kind (i32.load8_u (local.get $obj)))
  (local.set $info (i32.mul (local.get $kind) (i32.const 11)))
  (local.set $anim
    (i32.add
      (i32.shl (i32.load8_u offset=1101 (local.get $info)) (i32.const 2))
      (i32.shr_u (global.get $timer) (i32.const 2))))
  (local.set $img
    (i32.add
      (i32.load16_u offset=1102 (local.get $info))
      (i32.load8_u offset=1276 (local.get $anim))))

  (local.set $x (i32.trunc_f32_s (f32.load offset=1 (local.get $obj))))
  (local.set $y
    (i32.add
      (i32.trunc_f32_s (f32.load offset=5 (local.get $obj)))
      (i32.load8_u offset=1260 (local.get $anim))))

  (local.set $w (i32.load8_u (local.get $img)))
  (local.set $h (i32.load8_u offset=1 (local.get $img)))
  ;; TODO(fix)
  (local.set $color
    (i32.shl
      (i32.sub
        (i32.const 255)
        (i32.load8_u offset=2 (local.get $img)))
      (i32.const 24)))
  (local.set $src_addr (i32.add (local.get $img) (i32.const 3)))

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
          (local.set $hit
            (i32.or
              (local.get $hit)
              (i32.ne
                (i32.load (local.get $dst_addr))
                (i32.const -1))))

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

  (i32.and
    (local.get $hit)  ;; hit a non-white pixel
    (i32.ge_u (local.get $kind) (i32.const 10))) ;; is a dino
)

(func $move (param $obj i32)
  (local $info i32)
  (local $rand_info i32)
  (local $kind i32)
  (local $x f32)
  (local $dx f32)

  (local.set $info (i32.mul (i32.load8_u (local.get $obj)) (i32.const 11)))
  (local.set $x
    (f32.add
      (f32.load offset=1 (local.get $obj))
      (f32.mul
        (f32.load offset=1107 (local.get $info))
        (global.get $speed))))

  (if
    (f32.lt (local.get $x) (f32.const -32))
    (then
      ;; Pick a random item.
      (local.set $rand_info
        (i32.shl
          (i32.load8_u offset=1100 (local.get $info))
          (i32.const 1)))

      (local.set $info
        (i32.add
          (i32.trunc_f32_s
            (f32.mul
              (call $random)
              (f32.convert_i32_s
                (i32.load8_u offset=1255 (local.get $rand_info)))))
          (i32.load8_u offset=1254 (local.get $rand_info))))

      (i32.store8 (local.get $obj) (local.get $info))

      (local.set $kind (i32.mul (local.get $info) (i32.const 11)))
      (local.set $x
        (f32.add
          (f32.add
            (local.get $x)
            (f32.const 352))
          (f32.convert_i32_s
            (i32.shl
              (i32.load8_u offset=1104 (local.get $kind))
              (i32.const 3)))))

      (f32.store offset=5
        (local.get $obj)
        (f32.add
          (f32.convert_i32_s (i32.load8_u offset=1105 (local.get $kind)))
          (f32.mul
            (call $random)
            (f32.convert_i32_s (i32.load8_u offset=1106 (local.get $kind))))))))

  (f32.store offset=1 (local.get $obj) (local.get $x)))

(func (export "run")
  (local $i i32)
  (local $input i32)
  (local $dino_id i32)
  (local $y f32)

  ;; clear screen
  (loop $loop
    (i64.store offset=0x3000
      (local.get $i)
      (i64.const 0xffffffff_ffffffff))

    ;; loop on x
    (br_if $loop
      (i32.lt_s
        (local.tee $i (i32.add (local.get $i) (i32.const 8)))
        (i32.const 90000))))

  ;; Run animation
  (global.set $timer
    (i32.and (i32.add (global.get $timer) (i32.const 1))
             (i32.const 15)))

  (global.set $speed
    (f32.max
      (f32.sub (global.get $speed) (f32.const 0.0078125))
      (f32.const -4)))

  (local.set $input (i32.load8_u (i32.const 0)))
  (local.set $y (f32.load (i32.const 932)))

  block $done
  block $falling
  block $rising
  block $running
  block $dead
    (br_table $running $rising $falling $dead (global.get $dino_state))

  end $dead
    (local.set $dino_id (i32.const 13))
    (global.set $speed (f32.const 0))
    (br $done)

  end $running
    ;; If down pressed, duck
    (local.set $dino_id
      (select
        (i32.const 12)
        (i32.const 11)
        (i32.eq (local.get $input) (i32.const 2))))

    ;; if up pressed, jump
    (if (i32.eq (local.get $input) (i32.const 1))
      (then
        (global.set $dino_state (i32.const 1))
        (global.set $jump_vel (f32.const -6))))
    (br $done)

  end $rising
    ;; Stop jumping if the button is released and we've reached the minimum
    ;; height, or we've reached the maximum height.
    (if
      (i32.or
        (i32.and
          (i32.ne (local.get $input) (i32.const 1))
          (f32.lt (local.get $y) (f32.const 30)))
        (f32.lt (local.get $y) (f32.const 10)))
      (then
        ;; start falling.
        (global.set $dino_state (i32.const 2))
        (global.set $jump_vel (f32.const -1))
        ))

    ;; fallthrough
  end $falling
    (local.set $dino_id (i32.const 10))
    (local.set $y (f32.add (local.get $y) (global.get $jump_vel)))
    (global.set $jump_vel (f32.add (global.get $jump_vel) (f32.const 0.4)))

    ;; Stop falling if the ground is reached.
    (if (f32.gt (local.get $y) (f32.const 50))
      (then
        (global.set $dino_state (i32.const 0))
        (local.set $y (f32.const 50))
        (global.set $jump_vel (f32.const 0))
        ))

  end $done

  (i32.store8 (i32.const 927) (local.get $dino_id))
  (f32.store (i32.const 932) (local.get $y))

  ;; update objects
  (local.set $i (i32.const 900))
  (loop $loop
    (if (call $blit (local.get $i))
      (then (global.set $dino_state (i32.const 3))))

    (call $move (local.get $i))

    ;; loop on x
    (br_if $loop
      (i32.lt_s
        (local.tee $i (i32.add (local.get $i) (i32.const 9)))
        (i32.const 1080))))

)
