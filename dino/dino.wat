(import "Math" "random" (func $random (result f32)))

;; 0x0                Input: 1=up, 2=down, 3=up+down
;; [0x4, 0x5000)      See below
;; [0x5000, 0x1c000)  Color[300*75]  canvas
(memory (export "mem") 2)

(global $f0 f32 (f32.const 0))
(global $f50 f32 (f32.const 50))

(global $timer (mut i32) (i32.const 0))
(global $score (mut i32) (i32.const 0))
(global $dino_state (mut i32) (i32.const 0))
(global $jump_vel (mut f32) (f32.const 0))
(global $speed (mut f32) (f32.const -0.5))

(data (i32.const 40)
  ;; objects  14 * 9 bytes = 126 bytes
  ;; =4 dino
  ;;    kind       y  x
  ;; (i8 11) (f32 50 22)

  ;; obstacles x 3
  ;; (i8 1)  (f32 55 300)
  ;; (i8 1)  (f32 55 600)
  ;; (i8 1)  (f32 55 900)

  ;; ground x 6
  (i8 7)  (f32 67   0)
  (i8 7)  (f32 67  64)
  (i8 7)  (f32 67 128)
  (i8 7)  (f32 67 192)
  (i8 7)  (f32 67 256)
  (i8 7)  (f32 67 320)

  ;; clouds x 4
  (i8 6)  (f32 40   0)
  (i8 6)  (f32 40 128)
  (i8 6)  (f32 40 256)
  (i8 6)  (f32 40 384)
  ;; end=130

  ;; info  12 * 7 bytes = 84 bytes
  ;;  id anim  img  +4x  y +y *4dx
  (i8  0    0   18   75 46  0   4)  ;;  0 cactus1
  (i8  0    0   21   75 54  0   4)  ;;  1 cactus2
  (i8  0    0   24   75 54  0   4)  ;;  2 cactus3
  (i8  0    0   27   75 54  0   4)  ;;  3 cactus4
  (i8  0    0   30   75 46  0   4)  ;;  4 cactus5
  (i8  0    3   39   75 25 25   5)  ;;  5 bird
  (i8  1    0   33   30 15 25   1)  ;;  6 cloud
  (i8  2    0   36    0 67  0   4)  ;;  7 ground
  (i8  3    0    3    0  0  0   0)  ;;  8 dino stand
  (i8  3    1    6    0  0  0   0)  ;;  9 dino run
  (i8  3    2   12    0  0  0   0)  ;; 10 dino duck
  (i8  3    0    0    0  0  0   0)  ;; 11 dino dead
  ;; end=214

  ;; random id  3 * 2 bytes = 6 bytes
  (i8 0 6)
  (i8 6 1)
  (i8 7 1)
  ;; end=220

  ;; anims (y addend)  4 * 4 bytes = 16 bytes
  (i8 0 0 0 0)  ;; 0 none
  (i8 0 0 0 0)  ;; 1 run
  (i8 9 9 9 9)  ;; 2 duck
  (i8 0 0 3 3)  ;; 3 bird
  ;; end=236

  ;; anims (img addend)  4 * 4 bytes = 16 bytes
  (i8 0  0  0  0)  ;; 0 none
  (i8 0  3  0  3)  ;; 1 run
  (i8 0  3  0  3)  ;; 2 duck
  (i8 0  0  3  3)  ;; 3 bird
  ;; end=252

  ;; images  15 * 3 bytes = 45 bytes
  ;; whcol     data
  (i8  0) (i16 0)     ;; dead     = 0
  (i8  0) (i16 440)   ;; stand    = 3
  (i8  0) (i16 880)   ;; run1     = 6
  (i8  0) (i16 1320)  ;; run2     = 9
  (i8  3) (i16 1760)  ;; duck1    = 12
  (i8  3) (i16 2124)  ;; duck2    = 15
  (i8  6) (i16 2488)  ;; cactus1  = 18
  (i8  9) (i16 2826)  ;; cactus2  = 21
  (i8 12) (i16 3168)  ;; cactus3  = 24
  (i8 15) (i16 3672)  ;; cactus4  = 27
  (i8 18) (i16 3834)  ;; cactus5  = 30
  (i8 21) (i16 4874)  ;; cloud    = 33
  (i8 24) (i16 5082)  ;; ground   = 36
  (i8 27) (i16 5402)  ;; bird1    = 39
  (i8 30) (i16 5724)  ;; bird2    = 42
  ;; end=297

  ;; width,height,color  13 * 3 = 39 bytes
  ;; collision only occurs w/ color 172
  (i8 20 22 171)  ;;  0 dead,stand,run1,run2
  (i8 28 13 171)  ;;  3 duck1,duck2
  (i8 13 26 172)  ;;  6 cactus1
  (i8 19 18 172)  ;;  9 cactus2
  (i8 28 18 172)  ;; 12 cactus3
  (i8  9 18 172)  ;; 15 cactus4
  (i8 40 26 172)  ;; 18 cactus5
  (i8 26  8  37)  ;; 21 cloud
  (i8 64  5 171)  ;; 24 ground
  (i8 23 14 172)  ;; 27 bird1
  (i8 23 16 172)  ;; 30 bird2
  (i8  3  5 172)  ;; 33 digits
  (i8 50  8 172)  ;; 36 gameover
  ;; end=336

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
  "\0f\1b\0f\1f\2a\1f\45\71\84\23\e3\21\e5\c1\e6\a1\e8\21\44\c8\47\8a\2b\4c"
  "\2d\0e\df\d5\1f\02\99\7b\f3\2f\e5\a1\e6\81\ea\41\ec\21\40\09\e0\7a\2e\6b"
  "\d3\03\cd\43\c9\83\c9\83\85\53\48\48\98\84\84\44\98\94\98\90\54\48\90\84"
  "\94\8c\a0\50\1c\c8\20\92\8a\0a\0c\92\90\08\9a\19\11\11\9a\11\09\09\0a\0a"
  "\03\1d\04\15\12\83\e0\24\67\20\60\08\0d\0f\87\90\91\a0\12\19\06\12\24\3a"
  "\00\80\06\82\c4\84\86\02\40\22\00\82\03\83\24\24\2a\64\24\10\b3\38\90\94"
  "\8c\90\ef\d1\90\a0\19\8a\a1\90\10"
  ;; end=827 (size=491 bytes)

  ;; first pass decompressed output [827, 2317)
  ;; second pass decompressed ouput [2317, 8957)

  ;; 0.ppm => 6092
  ;; gameover.ppm => 6242
)

(data (i32.const 0x4fdb)
  ;; Starting obstacles + dino
  ;; id        x   y
  (i8 9) (f32 50 22)   ;; dino
  (i8 1) (f32 55 300)  ;; obstacle1
  (i8 1) (f32 55 600)  ;; obstacle2
  (i8 1) (f32 55 900)  ;; obstacle3
  ;; Byte to replicate when clearing the screen.
  (i8 0xff)
)

(func $memcpy (param $dst i32) (param $src i32) (param $dstend i32)
  ;; Copy len bytes from $src to $dst. We can emulate a fill if the regions
  ;; overlap. Always copies at least one byte!
  (loop $copy
    (i32.store8 (local.get $dst) (i32.load8_u (local.get $src)))
    (local.set $src (i32.add (local.get $src) (i32.const 1)))
    (br_if $copy
      (i32.lt_u
        (local.tee $dst (i32.add (local.get $dst) (i32.const 1)))
        (local.get $dstend))))
)

(start $decompress)
(func $decompress
  (local $data_left i32)    ;; rest of currently read byte
  (local $bits_left i32)    ;; number of bits available
  (local $bits_to_read i32) ;; number of bits to read
  (local $read_data i32)    ;; currently read value
  (local $lit_count i32)    ;; number of 4-bit literals to read
  (local $ref_dist i32)     ;; backreference distance
  (local $src i32)
  (local $dst i32)
  (local $temp_dst i32)
  (local $state i32)        ;; see below

  (local $run_count i32)    ;; number of bits in this run
  (local $run_byte i32)     ;; byte to write

  (local.set $bits_to_read (i32.const 7))
  (local.set $dst (i32.const 827))

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
              (i32.load16_u offset=336 (local.get $src))
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
      ;; $memcpy always copies at least one byte. That may happen here but it's
      ;; OK because we'll not advance $dst, so the value we copied will be
      ;; overwritten.
      (call $memcpy
        (local.get $dst)
        (i32.sub (local.get $dst) (local.get $ref_dist))
        (local.tee $dst (i32.add (local.get $dst) (local.get $read_data))))

      (local.set $state (i32.const 0))
      (br $loop)

    ;; 2: read backreference distance
    end $2
      ;; Check for end, since compressed data ends with literals.
      (local.set $ref_dist (local.get $read_data))
      (local.set $state (i32.const 3))
      (br_if $loop (i32.lt_u (local.get $src) (i32.const 492)))
      ;; fall out of loop
  )

  ;; Second pass, decode 1bpp runs
  ;; $src == 492
  ;; $dst == 2317
  (local.set $src (i32.const 492))
  (loop $loop
    (if (local.tee $run_count (i32.load8_u offset=335 (local.get $src)))
      (then
        ;; Set first byte.
        (i32.store8 (local.get $dst) (local.get $run_byte))
        ;; Then replicate with memcpy.
        (call $memcpy
          (i32.add (local.get $dst) (i32.const 1))
          (local.get $dst)
          (local.tee $dst (i32.add (local.get $dst) (local.get $run_count))))))

    ;; Flip written byte between 0 and 1.
    (local.set $run_byte (i32.eqz (local.get $run_byte)))
    (br_if $loop
      (i32.lt_u
        (local.tee $src (i32.add (local.get $src) (i32.const 1)))
        (i32.const 1982))))
)

(func $blit
      (param $x i32) (param $y i32)
      (param $whcol_addr i32)
      (param $src_addr i32) (result i32)
  (local $w i32)
  (local $h i32)
  (local $color i32)
  (local $dst_addr i32)
  (local $tmp_dst_addr i32)
  (local $src_stride i32)
  (local $ix i32)
  (local $hit i32)

  (local.set $src_stride
    (local.tee $w (i32.load8_u offset=297 (local.get $whcol_addr))))
  (local.set $h (i32.load8_u offset=298 (local.get $whcol_addr)))
  (local.set $color
    (i32.shl
      (i32.load8_u offset=299 (local.get $whcol_addr))
      (i32.const 24)))

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

  ;; if (w <= 0) { return 0; }
  (if (i32.gt_s (local.get $w) (i32.const 0))
    (then
      ;; dst_addr = y * SCREEN_WIDTH + x
      (local.set $dst_addr
        (i32.add (i32.mul (local.get $y) (i32.const 300)) (local.get $x)))

      (loop $yloop
        ;; ix = 0;
        (local.set $ix (i32.const 0))

        (loop $xloop
          ;; data = i8_mem[src_addr]
          (if (i32.load8_u offset=2317 (i32.add (local.get $src_addr) (local.get $ix)))
            (then
              ;; get alpha value of previous pixel. If it is 172, then it is an
              ;; obstacle.
              (local.set $hit
                (i32.or
                  (local.get $hit)
                  (i32.eq
                    (i32.load8_u offset=0x5003
                      (local.tee $tmp_dst_addr
                        (i32.shl (i32.add (local.get $dst_addr)
                                          (local.get $ix))
                                 (i32.const 2))))
                    (i32.const 172))))
              ;; set new pixel
              (i32.store offset=0x5000 (local.get $tmp_dst_addr) (local.get $color))))

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
      ))

  (local.get $hit)
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

  (local $ix i32)
  (local $iy i32)
  (local $num i32)

  (local $x f32)
  (local $y f32)

  ;; clear screen (the byte at 0x4fff is initialized to 0xff)
  (call $memcpy (i32.const 0x5000) (i32.const 0x4fff) (i32.const 0x1af90))

  ;; Animation timer
  (global.set $timer (i32.add (global.get $timer) (i32.const 1)))

  (global.set $speed
    (f32.max
      (f32.sub (global.get $speed) (f32.const 0.001953125))
      (f32.const -1)))

  (local.set $input (i32.load8_u (i32.const 0)))
  (local.set $y (f32.load (i32.const 5)))  ;; dino.y

  block $done
  block $playing
  block $falling
  block $rising
  block $running
  block $init
  block $dead
    (br_table $init $running $rising $falling $dead (global.get $dino_state))

  end $dead
    (local.set $dino_id (i32.const 11))
    (global.set $speed (global.get $f0))
    ;; GAME OVER
    (drop
      (call $blit
        ;; x y
        (i32.const 125) (i32.const 33)
        ;; whcol_addr
        (i32.const 36)
        ;; data
        (i32.const 6242)))

    ;; Wait until button pressed.
    (br_if $done
      (i32.or
        (i32.eqz (local.get $input))
        ;; Wait at least 20 frames before restarting.
        (i32.le_u
          (i32.sub (global.get $timer) (global.get $score))
          (i32.const 20))))

    ;; only need to reset score, dino state, and obstacles.
    (global.set $score (i32.const 0))
    (global.set $timer (i32.const 0))
    (global.set $jump_vel (global.get $f0))
    (global.set $speed (f32.const -0.5))

    ;; fallthrough
  end $init
    ;; init dino
    (local.set $dino_id (i32.const 9))
    (local.set $y (global.get $f50))

    ;; reset obstacles
    (global.set $dino_state (i32.const 1))
    (call $memcpy (i32.const 4) (i32.const 0x4fdb) (i32.const 40))

    ;; fallthrough
  end $running
    ;; If down pressed, duck (id=10) else stand (id=9)
    (local.set $dino_id
      (i32.add (i32.eq (local.get $input) (i32.const 2)) (i32.const 9)))

    ;; if up is not pressed, skip over jumping code
    (br_if $playing (i32.ne (local.get $input) (i32.const 1)))

    ;; start jumping.
    (global.set $dino_state (i32.const 2))
    (global.set $jump_vel (f32.const -6))

    ;; fallthrough
  end $rising
    ;; Stop jumping if the button is released and we've reached the minimum
    ;; height, or we've reached the maximum height.
    (br_if $falling
      (i32.and
        (i32.or
          (i32.eq (local.get $input) (i32.const 1))
          (f32.ge (local.get $y) (f32.const 30)))
        (f32.ge (local.get $y) (f32.const 10))))

    ;; start falling.
    (global.set $dino_state (i32.const 3))
    (global.set $jump_vel (f32.const -1))

    ;; fallthrough
  end $falling
    (local.set $dino_id (i32.const 8))
    (local.set $y (f32.add (local.get $y) (global.get $jump_vel)))
    (global.set $jump_vel (f32.add (global.get $jump_vel) (f32.const 0.4)))

    ;; Stop falling if the ground is reached.
    (br_if $playing (f32.le (local.get $y) (global.get $f50)))

    (global.set $dino_state (i32.const 1))
    (local.set $y (global.get $f50))
    (global.set $jump_vel (global.get $f0))

    ;; fallthrough
  end $playing
    (global.set $score (i32.add (global.get $score) (i32.const 1)))

    ;; fallthrough
  end $done

  ;; Update dino id and y-coordinate.
  (i32.store8 (i32.const 4) (local.get $dino_id))
  (f32.store (i32.const 5) (local.get $y))

  ;; loop over objects backward, drawing and moving
  (local.set $obj (i32.const 121))
  (loop $loop
    ;;; Draw and check for collision.
    (if
      (i32.and
        ;; hit a non-white pixel
        (call $blit
          ;; x
          (i32.trunc_f32_s (f32.load offset=5 (local.get $obj)))
          ;; y
          (i32.add
            (i32.trunc_f32_s (f32.load offset=1 (local.get $obj)))
            (i32.load8_u offset=220
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
          ;; whcol_addr
          (i32.load8_u offset=252
            (local.tee $img
              (i32.add
                (i32.load8_u offset=132 (local.get $info))
                (i32.load8_u offset=236 (local.get $anim)))))
          ;; src_addr
          (i32.load16_u offset=253 (local.get $img)))
         ;; is a dino
        (i32.ge_u (local.get $kind) (i32.const 8)))
        (then
          ;; Set state to dead.
          (global.set $dino_state (i32.const 4))))

    ;;; Move
    (if
      ;; If object goes off screen to the left...
      (f32.lt
        (local.tee $x
          (f32.add
            (f32.load offset=5 (local.get $obj))
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
                    (i32.load8_u offset=215
                      (local.tee $rand_info
                        (i32.shl
                          (i32.load8_u offset=130 (local.get $info))
                          (i32.const 1)))))))
              (i32.load8_u offset=214 (local.get $rand_info)))))

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
        (f32.store offset=1
          (local.get $obj)
          (f32.add
            (f32.convert_i32_u
              (i32.load8_u offset=134 (local.get $kind)))
            (f32.mul
              (call $random)
              (f32.convert_i32_u
                (i32.load8_u offset=135 (local.get $kind))))))))

    ;; Write object x coordinate.
    (f32.store offset=5 (local.get $obj) (local.get $x))

    ;; loop over all objects backward.
    (br_if $loop
      (i32.gt_s
        (local.tee $obj (i32.sub (local.get $obj) (i32.const 9)))
        (i32.const 0))))

  ;; draw score
  (local.set $num (global.get $score))
  (local.set $ix (i32.const 300))
  (loop $loop
    (drop
      (call $blit
        ;; x
        (local.tee $ix (i32.sub (local.get $ix) (i32.const 4)))
        ;; y
        (i32.const 4)
        ;; whcol_addr
        (i32.const 33)
        (i32.add
          (i32.const 6092)
          (i32.mul
            (i32.rem_u (local.get $num) (i32.const 10))
            (i32.const 15)))))
    (br_if $loop (local.tee $num (i32.div_u (local.get $num) (i32.const 10)))))
)
