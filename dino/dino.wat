(import "Math" "random" (func $random (result f32)))

;; 0x0                Input: 1=up, 2=down, 3=up+down
;; [0x4, 913)         See below
;; [1000, 2520)       Decompressed 1-bit runs
;; [2520, 9320)       Decompressed graphics @ 8bpp
;; [0x5000, 0x1c000)  Color[300*75]  canvas
(memory (export "mem") 2)

(global $timer (mut i32) (i32.const 0))
(global $score (mut i32) (i32.const 0))
(global $dino_state (mut i32) (i32.const 0))
(global $jump_vel (mut f32) (f32.const 0))
(global $speed (mut f32) (f32.const -0.5))

(data (i32.const 4)
  ;; =4
  ;; objects  14 * 9 bytes = 126 bytes
  ;; obstacles x 3
  ;; kind       x  y
  (i8 1)  (f32 300 55)
  (i8 1)  (f32 600 55)
  (i8 1)  (f32 900 55)

  ;; =31 dino
  (i8 11) (f32 22 50)

  ;; ground x 6
  (i8 7)  (f32   0 67)
  (i8 8)  (f32  64 67)
  (i8 9)  (f32 128 67)
  (i8 7)  (f32 192 67)
  (i8 8)  (f32 256 67)
  (i8 9)  (f32 320 67)

  ;; clouds x 4
  (i8 6)  (f32   0 40)
  (i8 6)  (f32 128 40)
  (i8 6)  (f32 256 40)
  (i8 6)  (f32 384 40)
  ;; end=130

  ;; info  14 * 7 bytes = 98 bytes
  ;;  id anim  img  +4x  y +y *4dx
  (i8  0    0   30   75 46  0   4)  ;;  0 cactus1
  (i8  0    0   35   75 54  0   4)  ;;  1 cactus2
  (i8  0    0   40   75 54  0   4)  ;;  2 cactus3
  (i8  0    0   45   75 54  0   4)  ;;  3 cactus4
  (i8  0    0   50   75 46  0   4)  ;;  4 cactus5
  (i8  0    3   75   75 25 25   5)  ;;  5 bird
  (i8  1    0   55   30 15 25   1)  ;;  6 cloud
  (i8  2    0   60    0 67  0   4)  ;;  7 ground1
  (i8  2    0   65    0 67  0   4)  ;;  8 ground2
  (i8  2    0   70    0 67  0   4)  ;;  9 ground3
  (i8  3    0    5    0  0  0   0)  ;; 10 dino stand
  (i8  3    1   10    0  0  0   0)  ;; 11 dino run
  (i8  3    2   20    0  0  0   0)  ;; 12 dino duck
  (i8  3    0    0    0  0  0   0)  ;; 13 dino dead
  ;; end=228

  ;; random id  3 * 2 bytes = 6 bytes
  (i8 0 6)
  (i8 6 1)
  (i8 7 3)
  ;; end=234

  ;; anims (y addend)  4 * 4 bytes = 16 bytes
  (i8 0 0 0 0)  ;; 0 none
  (i8 0 0 0 0)  ;; 1 run
  (i8 9 9 9 9)  ;; 2 duck
  (i8 0 0 3 3)  ;; 3 bird
  ;; end=250

  ;; anims (img addend)  4 * 4 bytes = 16 bytes
  (i8 0  0  0  0)  ;; 0 none
  (i8 0  5  0  5)  ;; 1 run
  (i8 0  5  0  5)  ;; 2 duck
  (i8 0  0  5  5)  ;; 3 bird
  ;; end=266

  ;; images  17 * 5 bytes = 85 bytes
  ;;   w  h col   data
  (i8 20 22  83) (i16 2592)  ;; dead     = 0
  (i8 20 22  83) (i16 3032)  ;; stand    = 5
  (i8 20 22  83) (i16 3472)  ;; run1     = 10
  (i8 20 22  83) (i16 3912)  ;; run2     = 15
  (i8 28 13  83) (i16 4352)  ;; duck1    = 20
  (i8 28 13  83) (i16 4716)  ;; duck2    = 25
  (i8 13 26  83) (i16 5080)  ;; cactus1  = 30
  (i8 19 18  83) (i16 5418)  ;; cactus2  = 35
  (i8 28 18  83) (i16 5760)  ;; cactus3  = 40
  (i8  9 18  83) (i16 6264)  ;; cactus4  = 45
  (i8 40 26  83) (i16 6426)  ;; cactus5  = 50
  (i8 26  8 218) (i16 7466)  ;; cloud    = 55
  (i8 64  5  83) (i16 7674)  ;; ground1  = 60
  (i8 64  5  83) (i16 7994)  ;; ground2  = 65
  (i8 64  5  83) (i16 8314)  ;; ground3  = 70
  (i8 23 14  83) (i16 8634)  ;; bird1    = 75
  (i8 23 16  83) (i16 8956)  ;; bird2    = 80
  ;; end=351

  ;; compressed graphics data
  "\91\c5\95\29\95\88\28\95\29\0d\18\72\28\81\65\71\66\42\4a\23\19\41\6e\7e"
  "\9c\ab\c9\e7\13\e2\32\e1\41\e1\32\f2\40\b8\aa\12\07\3c\08\ea\85\e3\87\0c"
  "\cb\c3\c4\03\c9\43\02\61\48\11\79\91\78\a0\78\20\c1\78\18\8c\a1\94\87\8f"
  "\8b\07\96\87\9d\07\a5\07\52\96\43\9b\78\98\90\19\79\10\09\79\d8\d4\21\20"
  "\40\15\62\64\42\1e\c4\b7\28\e8\64\a1\20\91\90\90\90\0a\0b\82\a6\f0\b1\83"
  "\32\05\40\60\e8\9c\a0\dc\dc\d8\48\84\c4\44\d0\84\84\c4\c4\88\02\21\a0\50"
  "\60\2a\16\14\26\15\14\55\7c\25\75\63\43\d0\08\4e\0c\08\80\d1\30\20\09\46"
  "\63\10\32\60\44\41\42\42\e0\0b\00\04\15\30\c7\c1\55\41\51\22\31\21\d2\24"
  "\31\21\44\52\64\21\24\36\85\24\36\57\25\36\37\67\a8\00\04\86\41\50\10\20"
  "\07\8c\0a\a3\12\21\2a\36\36\29\0f\2a\4a\19\4d\49\38\6c\58\2c\70\82\92\70"
  "\42\4a\d1\38\54\0c\89\90\e3\30\90\12\c7\87\10\12\e6\68\14\6a\42\d0\91\28"
  "\0c\c9\9c\83\21\20\73\28\18\21\21\21\43\22\c1\90\05\01\63\c5\a1\28\1c\59"
  "\99\0a\41\48\b2\62\28\08\38\81\08\c3\42\8c\28\09\87\c4\10\a1\d4\db\03\49"
  "\c5\83\c4\c9\8b\85\0c\92\4b\c5\43\05\c5\83\49\c4\3c\08\10\81\4c\20\18\15"
  "\0f\1b\0f\1f\2a\1f\05\62\84\23\e3\61\92\08\50\02\71\b8\40\79\20\1b\82\00"
  "\13\57\3a\1c\32\1e\50\50\16\31\3c\3c\44\e0\0c\00\bb\82\50\91\c1\30\fc\24"
  "\50\1e\6c\1e\8a\1e\42\84\7c\a4\b8\c2\d4\e2\f0\5d\fd\21\90\b9\37\ff\52\1e"
  "\6a\1e\a8\1e\c4\1e\02\94\00\ae\e7\b2\36\3d\d0\3c\94\3c\98\3c\58\38\85\84"
  "\84\49\48\48\84\49\89\09\49\85\04\49\48\c9\08\0a\c5\81\0c\22\a9\a8\c0\20"
  "\09\89\a0\99\11\11\a1\19\91\90\a0\a0\30\d0\41\50\21\31\08\4e\72\06\02\86"
  "\d0\f0\70\08\19\09\2a\91\61\20\41\a2\03\00\68\20\48\4c\68\28\00\24\02\20"
  "\38\30\48\42\a2\42\46\02\31\8b\03\49\c9\08\f9\1e\0d\09\9a\a1\18\0a\09\01"
  ;; end=879

  ;; dead.ppm => 2592
  ;; stand.ppm => 3032
  ;; run1.ppm => 3472
  ;; run2.ppm => 3912
  ;; duck1.ppm => 4352
  ;; duck2.ppm => 4716
  ;; cactus1.ppm => 5080
  ;; cactus2.ppm => 5418
  ;; cactus3.ppm => 5760
  ;; cactus4.ppm => 6264
  ;; cactus5.ppm => 6426
  ;; cloud.ppm => 7466
  ;; ground1b.ppm => 7674
  ;; ground2b.ppm => 7994
  ;; ground3b.ppm => 8314
  ;; bird1.ppm => 8634
  ;; bird2.ppm => 8956
  ;; 0.ppm => 9324
  ;; 1.ppm => 9339
  ;; 2.ppm => 9354
  ;; 3.ppm => 9369
  ;; 4.ppm => 9384
  ;; 5.ppm => 9399
  ;; 6.ppm => 9414
  ;; 7.ppm => 9429
  ;; 8.ppm => 9444
  ;; 9.ppm => 9459
  ;; gameover.ppm => 9474
)

(start $decompress)
(func $decompress
  (local $data_left i32)    ;; rest of currently read byte
  (local $bits_left i32)    ;; number of bits available
  (local $bits_to_read i32) ;; number of bits to read
  (local $read_data i32)    ;; currently read value
  (local $lit_count i32)    ;; number of 4-bit literals to read
  (local $ref_dist i32)     ;; backreference distance
  (local $ref_len i32)      ;; backreference length
  (local $i i32)            ;; index
  (local $src i32)
  (local $dst i32)
  (local $temp_dst i32)
  (local $state i32) ;; see below

  (local $run_count i32)    ;; number of bits in this run
  (local $run_byte i32)     ;; byte to write

  (local.set $bits_to_read (i32.const 7))
  (local.set $src (i32.const 351))
  (local.set $dst (i32.const 1000))

  ;; First pass, decode back-references.
  (loop $loop
    ;; Read in new bits when the number of bits left is less than 16. This
    ;; works because we never read more than 7 bits.
    (if
      (i32.lt_u (local.get $bits_left) (i32.const 16))
      (then
        ;; Read 16 bits into the top of $data_left
        (local.set $data_left
          (i32.or
            (local.get $data_left)
            (i32.shl
              (i32.load16_u (local.get $src))
              (local.get $bits_left))))
        ;; Add 16 bits to count
        (local.set $bits_left
          (i32.add (local.get $bits_left) (i32.const 16)))
        ;; Increment the src pointer
        (local.set $src (i32.add (local.get $src) (i32.const 2)))))

    ;; Save bits that were read (masked)
    (local.set $read_data
      (i32.and (local.get $data_left)
        (i32.sub
          (i32.shl (i32.const 1) (local.get $bits_to_read))
          (i32.const 1))))
    ;; Remove bits that were read from $data_left
    (local.set $data_left
      (i32.shr_u (local.get $data_left) (local.get $bits_to_read)))
    ;; Reduce the number of $bits_left
    (local.set $bits_left
      (i32.sub (local.get $bits_left) (local.get $bits_to_read)))

    block $2
    block $3
    block $goto2
    block $1
    block $0
      (br_table $0 $1 $2 $3 (local.get $state))

    ;; 0: read literal count (7 bits)
    end $0
      ;; skip if count is 0
      (br_if $goto2 (i32.eqz (local.tee $lit_count (local.get $read_data))))
      (local.set $state (i32.const 1))
      (local.set $bits_to_read (i32.const 4))
      (br $loop)

    ;; 1: read literal (4 bits)
    end $1
      (i32.store8 (local.get $dst) (local.get $read_data))
      (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
      (br_if $loop
        (local.tee $lit_count (i32.sub (local.get $lit_count) (i32.const 1))))
      ;; fallthrough

    end $goto2
      (local.set $state (i32.const 2))
      (local.set $bits_to_read (i32.const 7))
      (br $loop)

    ;; 3: read backreference length
    end $3
      (local.set $i (i32.const 0))
      ;; Copy len bytes from (dst - ref_dist) to dst
      (loop $copy
        (i32.store8
          (local.tee $temp_dst (i32.add (local.get $dst) (local.get $i)))
          (i32.load8_u (i32.sub (local.get $temp_dst) (local.get $ref_dist))))

        (br_if $copy
          (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 1)))
                    (local.get $read_data))))

      (local.set $dst (i32.add (local.get $dst) (local.get $read_data)))
      (local.set $state (i32.const 0))
      (br $loop)

    ;; 2: read backreference distance
    end $2
      ;; Check for end, since compressed data ends with literals.
      (local.set $ref_dist (local.get $read_data))
      (local.set $state (i32.const 3))
      (br_if $loop (i32.lt_u (local.get $src) (i32.const 878)))
      ;; fall out of loop
  )

  ;; Second pass, decode 1bpp runs
  (local.set $src (i32.const 1000))
  (local.set $dst (i32.const 2592))
  (loop $loop
    (if (local.tee $run_count (i32.load8_u (local.get $src)))
      (then
        (loop $byte_loop
          (i32.store8 (local.get $dst) (local.get $run_byte))
          (local.set $dst (i32.add (local.get $dst) (i32.const 1)))
          (br_if $byte_loop
            (local.tee $run_count
              (i32.sub (local.get $run_count) (i32.const 1)))))))

    ;; Flip written byte between 0 and 1.
    (local.set $run_byte (i32.eqz (local.get $run_byte)))
    (br_if $loop
      (i32.lt_u
        (local.tee $src (i32.add (local.get $src) (i32.const 1)))
        (i32.const 2592))))
)

(func $blit
      (param $x i32) (param $y i32) (param $w i32) (param $h i32)
      (param $color i32) (param $src_addr i32) (result i32)
  (local $dst_addr i32)
  (local $tmp_dst_addr i32)
  (local $src_stride i32)
  (local $ix i32)
  (local $hit i32)

  (local.set $src_stride (local.get $w))

  ;; if (x < 0)
  (if
    (i32.lt_s (local.get $x) (i32.const 0))
    (then
      ;; reduce width by x
      (local.set $w (i32.add (local.get $w) (local.get $x)))

      ;; advance src_addr by x
      (local.set $src_addr (i32.sub (local.get $src_addr) (local.get $x)))

      ;; set x to 0
      (local.set $x (i32.const 0)))
    (else
      ;; if (x + w > SCREEN_WIDTH)
      (if
        (i32.gt_s (i32.add (local.get $x) (local.get $w)) (i32.const 300))
        (then
          ;; w = SCREEN_WIDTH - x
          (local.set $w (i32.sub (i32.const 300) (local.get $x)))))))

  ;; if (w <= 0 || h <= 0) { return 0; }
  (if
    (i32.or
      (i32.le_s (local.get $w) (i32.const 0))
      (i32.le_s (local.get $h) (i32.const 0)))
    (then
      (return (i32.const 0))))

  ;; dst_addr = y * SCREEN_WIDTH + x
  (local.set $dst_addr
    (i32.add (i32.mul (local.get $y) (i32.const 300)) (local.get $x)))

  (loop $yloop
    ;; ix = 0;
    (local.set $ix (i32.const 0))

    (loop $xloop
      ;; data = i8_mem[src_addr]
      (if (i32.load8_u (i32.add (local.get $src_addr) (local.get $ix)))
        (then
          ;; get old pixel
          (local.set $hit
            (i32.or
              (local.get $hit)
              (i32.ne
                (i32.load offset=0x5000
                  (local.tee $tmp_dst_addr
                    (i32.shl (i32.add (local.get $dst_addr)
                                      (local.get $ix))
                             (i32.const 2))))
                (i32.const -1))))
          ;; set new pixel
          (i32.store offset=0x5000
            (local.get $tmp_dst_addr) (local.get $color))))

      ;; loop while (++ix < w)
      (br_if $xloop
        (i32.lt_s
          (local.tee $ix (i32.add (local.get $ix) (i32.const 1)))
          (local.get $w))))

    ;; dst_addr += SCREEN_WIDTH
    (local.set $dst_addr (i32.add (local.get $dst_addr) (i32.const 300)))
    ;; src_addr += src_stride;
    (local.set $src_addr (i32.add (local.get $src_addr) (local.get $src_stride)))

    ;; loop while (--h != 0)
    (br_if $yloop
      (local.tee $h (i32.sub (local.get $h) (i32.const 1)))))

  (local.get $hit)
)

(func $number (param $num i32) (param $x i32) (param $y i32)
  (loop $loop
    (drop
      (call $blit
        (local.tee $x
          (i32.sub
            (local.get $x)
            (i32.const 4)))
        (local.get $y)
        (i32.const 3) (i32.const 5)
        (i32.const 0xac_000000)
        (i32.add
          (i32.const 9324)
          (i32.mul
            (i32.rem_u (local.get $num) (i32.const 10))
            (i32.const 15)))))
    (br_if $loop (local.tee $num (i32.div_u (local.get $num) (i32.const 10)))))
)

(func (export "run")
  (local $i i32)
  (local $obj i32)
  (local $input i32)
  (local $dino_id i32)
  (local $kind i32)
  (local $anim i32)
  (local $img i32)
  (local $info i32)
  (local $rand_info i32)

  (local $x f32)
  (local $y f32)

  ;; clear screen
  (loop $loop
    (i64.store offset=0x5000
      (local.get $i)
      (i64.const 0xffffffff_ffffffff))

    ;; loop on x
    (br_if $loop
      (i32.lt_s
        (local.tee $i (i32.add (local.get $i) (i32.const 8)))
        (i32.const 90000))))

  ;; Animation timer
  (global.set $timer (i32.add (global.get $timer) (i32.const 1)))

  (global.set $speed
    (f32.max
      (f32.sub (global.get $speed) (f32.const 0.001953125))
      (f32.const -1)))

  (local.set $input (i32.load8_u (i32.const 0)))
  (local.set $y (f32.load (i32.const 36)))  ;; dino.y

  block $done
  block $playing
  block $falling
  block $rising
  block $running
  block $dead
    (br_table $running $rising $falling $dead (global.get $dino_state))

  end $dead
    (local.set $dino_id (i32.const 13))
    (global.set $speed (f32.const 0))
    ;; GAME OVER
    (call $blit
      (i32.const 125) (i32.const 33)
      (i32.const 50) (i32.const 8)
      (i32.const 0xac_000000)
      (i32.const 9474))

    ;; If any button pressed, reset.
    (if (i32.and
          (i32.ne (local.get $input) (i32.const 0))
          ;; Wait at least 20 frames before restarting.
          (i32.gt_u
            (i32.sub (global.get $timer) (global.get $score))
            (i32.const 20)))
      (then
        ;; only need to reset score, dino state, and obstacles.
        (global.set $score (i32.const 0))
        (global.set $timer (i32.const 0))
        (global.set $dino_state (i32.const 0))
        (global.set $jump_vel (f32.const 0))
        (global.set $speed (f32.const -0.5))
        (local.set $dino_id (i32.const 11))
        (local.set $y (f32.const 50))

        ;; reset obstacles
        (i64.store (i32.const 4)  (i64.const 0x5c0000_43960000_01))
        (i64.store (i32.const 12) (i64.const 0x0000_44160000_01_42))
        (i64.store (i32.const 20) (i64.const 0x00_44610000_01_425c))
        (i32.store (i32.const 28) (i32.const 0x0b_425c00))))

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
    (br $playing)

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
        (global.set $jump_vel (f32.const 0))))

    ;; fallthrough
  end $playing
    (global.set $score (i32.add (global.get $score) (i32.const 1)))

    ;; fallthrough
  end $done

  ;; Update dino id and y-coordinate.
  (i32.store8 (i32.const 31) (local.get $dino_id))
  (f32.store (i32.const 36) (local.get $y))

  ;; update objects
  (local.set $obj (i32.const 4))
  (loop $loop
    ;;; Draw and check for collision.
    (if
      (i32.and
        ;; hit a non-white pixel
        (call $blit
          ;; x
          (i32.trunc_f32_s (f32.load offset=1 (local.get $obj)))
          ;; y
          (i32.add
            (i32.trunc_f32_s (f32.load offset=5 (local.get $obj)))
            (i32.load8_u offset=234
              (local.tee $anim
                (i32.add
                  (i32.shl
                    (i32.load8_u offset=131
                      (local.tee $info
                        (i32.mul
                          (local.tee $kind (i32.load8_u (local.get $obj)))
                          (i32.const 7))))
                    (i32.const 2))
                  (i32.shr_u
                    (i32.and (global.get $timer) (i32.const 15))
                    (i32.const 2))))))
          ;; w
          (i32.load8_u offset=266
            (local.tee $img
              (i32.add
                (i32.load8_u offset=132 (local.get $info))
                (i32.load8_u offset=250 (local.get $anim)))))
          ;; h
          (i32.load8_u offset=267 (local.get $img))
          ;; color
          ;; TODO: simplify
          (i32.shl
            (i32.sub
              (i32.const 255)
              (i32.load8_u offset=268 (local.get $img)))
            (i32.const 24))
          ;; src_addr
          (i32.load16_u offset=269 (local.get $img)))
         ;; is a dino
        (i32.ge_u (local.get $kind) (i32.const 10)))
        (then
          ;; Set state to dead.
          (global.set $dino_state (i32.const 3))))

    ;;; Move
    (if
      ;; If object goes off screen to the left...
      (f32.lt
        (local.tee $x
          (f32.add
            (f32.load offset=1 (local.get $obj))
            (f32.mul
              (f32.convert_i32_u (i32.load8_u offset=136 (local.get $info)))
              (global.get $speed))))
        (f32.const -64))
      (then
        ;; Write new object kind.
        (i32.store8
          (local.get $obj)
          (local.tee $info
            (i32.add
              (i32.trunc_f32_s
                (f32.mul
                  ;; Pick a random item.
                  (call $random)
                  (f32.convert_i32_u
                    (i32.load8_u offset=229
                      (local.tee $rand_info
                        (i32.shl
                          (i32.load8_u offset=130 (local.get $info))
                          (i32.const 1)))))))
              (i32.load8_u offset=228 (local.get $rand_info)))))

        ;; Set new object x (stored below).
        (local.set $x
          (f32.add
            (f32.add
              (local.get $x)
              (f32.const 384))
            (f32.convert_i32_u
              (i32.shl
                (i32.load8_u offset=133
                  (local.tee $kind (i32.mul (local.get $info) (i32.const 7))))
                (i32.const 3)))))

        ;; Write new object y.
        (f32.store offset=5
          (local.get $obj)
          (f32.add
            (f32.convert_i32_u
              (i32.load8_u offset=134 (local.get $kind)))
            (f32.mul
              (call $random)
              (f32.convert_i32_u
                (i32.load8_u offset=135 (local.get $kind))))))))

    ;; Write object x coordinate.
    (f32.store offset=1 (local.get $obj) (local.get $x))

    ;; loop over all objects.
    (br_if $loop
      (i32.lt_s
        (local.tee $obj (i32.add (local.get $obj) (i32.const 9)))
        (i32.const 130))))

  ;; draw score
  (call $number (global.get $score) (i32.const 300) (i32.const 4))
)
