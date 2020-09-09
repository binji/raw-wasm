(import "Math" "random" (func $random (result f32)))

;; [0x0000, 0x0010)  u8[16]         v0..vf registers
;; [0x0010, 0x0012)  u8[16]         Key data
;; [0x0020, 0x0120)  u8[8*32]       1bpp screen data (stored in reverse)
;; [0x0120, 0x0170)  Char[16]       Font data
;; [0x0170, 0x0190)  u16[16]        Call stack
;; [0x0200, 0x1000)  u8[0x800]      Chip8 ROM
;; [0x1000, 0x3000)  Color[64*32]   canvas
(memory (export "mem") 1)

(global $pc (mut i32) (i32.const 0x200))
(global $sp (mut i32) (i32.const 0x18e))
(global $i (mut i32) (i32.const 0))
(global $delay (mut i32) (i32.const 0))

;; Font (taken from Octo's VIP font, see
;; https://github.com/JohnEarnest/Octo/blob/gh-pages/js/emulator.js)
(data (i32.const 0x120)
  "\F0\90\90\90\F0" ;; 0
  "\60\20\20\20\70" ;; 1
  "\F0\10\F0\80\F0" ;; 2
  "\F0\10\F0\10\F0" ;; 3
  "\A0\A0\F0\20\20" ;; 4
  "\F0\80\F0\10\F0" ;; 5
  "\F0\80\F0\90\F0" ;; 6
  "\F0\10\10\10\10" ;; 7
  "\F0\90\F0\90\F0" ;; 8
  "\F0\90\F0\10\F0" ;; 9
  "\F0\90\F0\90\90" ;; a
  "\F0\50\70\50\F0" ;; b
  "\F0\80\80\80\F0" ;; c
  "\F0\50\50\50\F0" ;; d
  "\F0\80\F0\80\F0" ;; e
  "\F0\80\F0\80\80" ;; f
)

(func (export "run") (param $cycles i32)
  (local $keys i32)
  (local $b0 i32)
  (local $x i32)
  (local $vx i32)
  (local $vy i32)
  (local $vf i32)
  (local $n i32)
  (local $nn i32)
  (local $nnn i32)
  (local $nextpc i32)
  (local $copy-src i32)
  (local $copy-dst i32)
  (local $j i32)
  (local $sprite-addr i32)
  (local $draw-src i32)
  (local $draw-dst i32)

  (local $sprite-row i64)
  (local $orig-row i64)

  (if (global.get $delay)
    (then
      (global.set $delay (i32.sub (global.get $delay) (i32.const 1)))))

  (block $exit-loop
  (loop $cycle
    (block $setpc (result i32)
    (block $nextpc
    (block $set-vx (result i32)
    (block $set-vf-vx (result i32)
    (block $skip (result i32)
    (block $do-copy
    (block $do-copy-update-i
    (block (block (block (block (block (block (block (block
    (block (block (block (block (block (block (block (block
      (local.set $nextpc (i32.add (global.get $pc) (i32.const 2)))
      ;; Each opcode is laid out as a 16-bit big-endian value. This code unpack
      ;; the various components so they can be easily used by the instructions
      ;; below. Note that `vx` and `vy` are the 8-bit values of the x and y
      ;; registers as encoded in the opcode.

      ;; fedcba9876543210
      ;; ================
      ;; ---b0---***nn***
      ;;     --x-**y*++n+
      ;;     ****nnn*****
      (local.set $vx
        (i32.load8_u
          (local.tee $x
            (i32.and
              (local.tee $b0 (i32.load8_u (global.get $pc)))
              (i32.const 0xf)))))
      (local.set $vy
        (i32.load8_u
          (i32.shr_u
            (local.tee $nn (i32.load8_u offset=1 (global.get $pc)))
            (i32.const 4))))
      (local.set $n (i32.and (local.get $nn) (i32.const 0xf)))
      (local.set $nnn
        (i32.or
          (i32.shl (local.get $x) (i32.const 8))
          (local.get $nn)))

      (br_table 0 2 1 3 4 5 6 7 8 9 10 11 12 13 14 15
        (i32.shr_u (local.get $b0) (i32.const 4)))

    )
    ;; 0x0???
    (if (local.get $n)
      (then
        ;; 0x00EE  return
        (global.set $sp (i32.add (global.get $sp) (i32.const 2)))
        (br $setpc (i32.load16_u (global.get $sp))))
      (else
        ;; 0x00E0  clear screen
        (local.set $copy-src (i32.const 0x3000)) ;; Uninit, so has zeroes.
        (local.set $copy-dst (i32.const 0x20))
        (local.set $x (i32.const 0x100))
        (br $do-copy)))

    )
    ;; 0x2NNN  call NNN
    (i32.store16 (global.get $sp) (local.get $nextpc))
    (global.set $sp (i32.sub (global.get $sp) (i32.const 2)))
    ;; fallthrough.

    )
    ;; 0x1NNN  PC = NNN
    (br $setpc (local.get $nnn))

    )
    ;; 0x3XNN  skip if v[x] == NN
    (br $skip (i32.eq (local.get $vx) (local.get $nn)))

    )
    ;; 0x4XNN  skip if v[x] != NN
    (br $skip (i32.ne (local.get $vx) (local.get $nn)))

    )
    ;; 0x5XY0  skip if v[x] == v[y]
    (br $skip (i32.eq (local.get $vx) (local.get $vy)))

    )
    ;; 0x6XNN  v[x] = NN
    (br $set-vx (local.get $nn))

    )
    ;; 0x7XNN  v[x] += NN
    (br $set-vx (i32.add (local.get $vx) (local.get $nn)))

    )
    ;; 0x8???

      (block (block (block (block (block (block (block (block (block
        (br_table 0 1 2 3 4 5 6 7 8 (local.get $n))

      )
      ;; 0x8XY0  v[x] = v[y]
      (br $set-vx (local.get $vy))

      )
      ;; 0x8XY1  v[x] |= v[y]
      (br $set-vx (i32.or (local.get $vx) (local.get $vy)))

      )
      ;; 0x8XY2  v[x] &= v[y]
      (br $set-vx (i32.and (local.get $vx) (local.get $vy)))

      )
      ;; 0x8XY3  v[x] ^= v[y]
      (br $set-vx (i32.xor (local.get $vx) (local.get $vy)))

      )
      ;; 0x8XY4  v[x] += v[y], vf = carry
      (br $set-vf-vx
        (i32.shr_u
          (local.tee $vx (i32.add (local.get $vx) (local.get $vy)))
          (i32.const 8)))

      )
      ;; 0x8XY5  v[x] -= v[y], vf = borrow
      (local.set $vx (i32.sub (local.get $vx) (local.get $vy)))
      (br $set-vf-vx (i32.ge_s (local.get $vx) (i32.const 0)))

      )
      ;; 0x8XY6  v[x] = v[y] >> 1, vf = shifted out bit
      (local.set $vx (i32.shr_u (local.get $vy) (i32.const 1)))
      (br $set-vf-vx (i32.and (local.get $vy) (i32.const 1)))

      )
      ;; 0x8XY7  v[x] = v[y] - v[x], vf = borrow
      (local.set $vx (i32.sub (local.get $vy) (local.get $vx)))
      (br $set-vf-vx (i32.ge_s (local.get $vx) (i32.const 0)))

      )
      ;; 0x8XYE  v[x] = v[y] << 1, vf = shifted out bit
      (local.set $vx (i32.shl (local.get $vy) (i32.const 1)))
      (br $set-vf-vx (i32.shr_u (local.get $vy) (i32.const 7)))

    )
    ;; 0x9XY0  skip if v[x] != v[y]
    (br $skip (i32.ne (local.get $vx) (local.get $vy)))

    )
    ;; 0xANNN  I = NNN
    (global.set $i (local.get $nnn))
    (br $nextpc)

    )
    ;; 0xBNNN  PC = NNN + v[0]
    (br $setpc
      (i32.add (local.get $nnn) (i32.load8_u (i32.const 0))))

    )
    ;; 0xCXNN  v[x] = random() & NN
    (br $set-vx
      (i32.and
        (i32.trunc_f32_u
          (f32.mul
            (call $random)
            ;; This is used instead of (f32.const 256) since it's smaller.
            (f32.convert_i32_s (i32.const 256))))
        (local.get $nn)))

    )
    ;; 0xDXYN  draw N-line sprite at (v[x], v[y])
    (local.set $vf (local.tee $j (i32.const 0)))
    (loop $yloop
      ;; Load the sprite data. It is loaded into a 64-bit local, and rotated to
      ;; the right to account for the x-coordinate (vx). Since the sprite data
      ;; is stored with high bits to the right of the screen, but little-endian
      ;; stores low bytes first, we have to store the data in reverse to make
      ;; simplify the code:
      ;;
      ;; For example, given the sprite data 0x85 (i.e. 1000 0101), the
      ;; following data will be loaded (where _ is substituted for 0 for
      ;; clarity):
      ;;
      ;; 63 ...                                                         0
      ;; ________________________________________________________1____1_1
      ;;
      ;; If the vx value is 20, this is rotated (by 20 + 8 = 28 bits) to:
      ;;
      ;; 63                 43   38 36                                  0
      ;; ____________________1____1_1____________________________________
      ;;
      ;; When this is written to memory, the low bytes are written first which
      ;; reverses the order of bytes shown here, to this:
      ;;
      ;; |byte 0 | byte 1| byte 2| byte 3| byte 4| byte 5| byte 6| byte 7
      ;;   0x00     0x00   0x00    0x00    0x50    0x08    0x00    0x00
      ;; _________________________________1_1________1___________________
      ;;
      ;; When the bytes are copied out to the canvas, they are read from right
      ;; to left, with each bit being shifted off the left side. Doing so will
      ;; display in the correct order.

      ;; draw sprite
      (i64.store offset=0x20

        ;; Calculate the destination address. The data is stored in reverse, so
        ;; it is easier to access using a 64-bit load/store in little-endian.
        ;; The following formula calculates: (31 - ((vy + j) & 31)) << 3 where
        ;; vy is the starting sprite line, and j is the loop index for each
        ;; sprite row.
        (local.tee $sprite-addr
          (i32.shl
            (i32.sub
              (i32.const 0x1f)
              (i32.and
                (i32.add (local.get $vy) (local.get $j))
                (i32.const 0x1f)))
            (i32.const 3)))

        (i64.xor
          (local.tee $orig-row
            (i64.load offset=0x20 (local.get $sprite-addr)))
          (local.tee $sprite-row
            (i64.rotr
              (i64.extend_i32_u
                (i32.load8_u (i32.add (global.get $i) (local.get $j))))
              (i64.add
                (i64.extend_i32_u (local.get $vx))
                (i64.const 8))))))

      ;; update vf
      (local.set $vf
        (i32.or
          (local.get $vf)
          (i32.eqz
            (i64.eqz
              (i64.and
                (local.get $orig-row)
                (local.get $sprite-row))))))

      (br_if $yloop
        (i32.lt_u
          (local.tee $j (i32.add (local.get $j) (i32.const 1)))
          (local.get $n))))

    ;; This sets vx too, but that's OK because it hasn't been changed.
    (br $set-vf-vx (local.get $vf))

    )
    ;; 0xEX9E  skip if v[x] key is pressed
    ;; 0xEXA1  skip if v[x] key is not pressed

    ;; Whether a key is pressed is stored as a 16-bit value @ 0x10. The bit is
    ;; shifted and masked to either 0 or 1, then xor'ed to flip the bit
    ;; depending on whether the instruction was 0xEX91 or 0xEXA1, by checking
    ;; whether the low nibble of the opcode is 1.
    (br $skip
      (i32.xor
        (i32.and
          (i32.shr_u
            (i32.load16_u offset=0x10 (i32.const 0))
            (local.get $vx))
          (i32.const 1))
        (i32.eq (local.get $n) (i32.const 0x1))))

    )
    ;; 0xF???

      (block (block (block (block (block (block (block (block
        ;; The 0xF instructions are discriminated by the low byte. Rather than
        ;; using a completely filled br_table (which would have to go up to
        ;; 0x65), we divide this value by 8 to create a smaller table. This
        ;; does mean that a few instructions overlap:
        ;;
        ;;     0xFX07 -> 0
        ;;     0xFX0A -> 1
        ;;     0xFX15 -> 2
        ;;     0xFX18 -> 3!
        ;;     0xFX1E -> 3!
        ;;     0xFX29 -> 4
        ;;     0xFX33 -> 5
        ;;     0xFX55 -> 6
        ;;     0xFX65 -> 7
        ;;
        ;; These are handled by checking the low nibble of the instruction
        ;; after the br_table.

               ;; 0 1 2 3 4 5 6 7 8 9 10 11 12
        (br_table 0 1 2 3 3 4 5 5 5 5 6  6  7
          (i32.shr_u (local.get $nn) (i32.const 3)))

      )
      ;; 0xFX07  v[x] = delay
      (br $set-vx (global.get $delay))

      )
      ;; 0xFX0A  v[x] = wait for key
      ;; Store key, choosing lowest numbered first.
      (br_if $set-vx
        (i32.ctz (local.tee $keys (i32.load16_u offset=0x10 (i32.const 0))))
        (local.get $keys))
        ;; no key pressed.
      (br $exit-loop)

      )
      ;; 0xFX15  delay = v[x]
      (global.set $delay (local.get $vx))
      (br $nextpc)

      )
      ;; 0xFX18 or 0xFX1E
      (br_if $nextpc (i32.ne (local.get $n) (i32.const 0xe)))
      ;; 0xFX1E  I += v[x]
      (global.set $i
        (i32.and
          (i32.add (global.get $i) (local.get $vx))
          (i32.const 0xffff)))
      (br $nextpc)

      )
      ;; 0xFX29  I = &font[v[x] & 0xf]
      (global.set $i
        (i32.add
          (i32.mul
            (i32.and (local.get $vx) (i32.const 0xf))
            ;; Each character is 5 bytes.
            (i32.const 5))
          (i32.const 0x120)))
      (br $nextpc)

      )
      ;; 0xFX33  I[0:2] = BCD(v[x])
      (i32.store16 (global.get $i)
        (i32.or
          (i32.div_u (local.get $vx) (i32.const 100))
          (i32.shl
            (i32.rem_u
              (i32.div_u (local.get $vx) (i32.const 10))
              (i32.const 10))
            (i32.const 8))))
      (i32.store8 offset=2 (global.get $i)
        (i32.rem_u (local.get $vx) (i32.const 10)))
      (br $nextpc)

      )
      ;; 0xFX55  I[0:X] = v[0:X], I += X + 1
      (local.set $copy-src (i32.const 0x00))
      (local.set $copy-dst (global.get $i))
      (br $do-copy-update-i)

      )
      ;; 0xFX65  v[0:X] = I[0:X], I += X + 1
      (local.set $copy-src (global.get $i))
      (local.set $copy-dst (i32.const 0x00))
      ;; fallthrough.

    )
    ;; $do-copy-update-i

    ;; The load and save instructions (0xFX55 and 0xFX65) both will save all
    ;; registers from v0 through vx. This means that it copies 1 more than the
    ;; value in x. In addition, the original VIP implementation of chip-8 also
    ;; increments the i register during these instructions.

    ;; x += 1   (x is the number of items to copy)
    ;; i += x
    (global.set $i
      (i32.and
        (i32.add
          (global.get $i)
          (local.tee $x
            (i32.add (local.get $x) (i32.const 1))))
        (i32.const 0xffff)))
    ;; fallthrough.

    )
    ;; $do-copy
    ;; always copy at least one byte
    (loop $copy
      (local.set $x (i32.sub (local.get $x) (i32.const 1)))
      (i32.store8
        (i32.add (local.get $copy-dst) (local.get $x))
        (i32.load8_u
          (i32.add (local.get $copy-src) (local.get $x))))
      (br_if $copy (local.get $x)))
    (br $nextpc)

    )
    ;; $skip
    (br $setpc
      (i32.add (i32.shl (i32.const 1) (;(i32.const <skip>);)) (local.get $nextpc)))

    )
    ;; $set-vf-vx
    ;; update vf
    (local.set $vf (;(i32.const <new-vf>);))
    (i32.store8 offset=0xf (i32.const 0) (local.get $vf))
    (local.get $vx)
    ;; fallthrough

    )
    ;; $set-vx
    (local.set $vx (;(i32.const <new-vx>);))
    (i32.store8 (local.get $x) (local.get $vx))
    ;; fallthrough.

    )
    ;; $nextpc
    (local.get $nextpc)
    ;; fallthrough.

    )
    ;; $setpc
    (global.set $pc (;(i32.const <new-pc>);))

    (br_if $cycle
      (local.tee $cycles (i32.sub (local.get $cycles) (i32.const 1)))))

  ;; $exit-loop
  )

  ;; draw screen
  (local.set $draw-src (i32.const 0x100))
  (loop $bytes
    ;; Start at 0x1c instead of 0x20, so that each byte is at the "top" of the
    ;; i32. That way we can rotate the most-significant bit to the left by 1,
    ;; into the least-significant bit. This means the mask can be `1` instead
    ;; of `0x100`, which saves a byte.
    (local.set $b0 (i32.load offset=0x1c (local.get $draw-src)))

    (loop $bits
      (i32.store offset=0x1000
        (local.get $draw-dst)
        (select
          (i32.const 0xff_ff_ff_ff)
          (i32.const 0xff_00_00_00)
          (i32.and
            (local.tee $b0 (i32.rotl (local.get $b0) (i32.const 1)))
            (i32.const 1))))

      (br_if $bits
        (i32.and
          (local.tee $draw-dst (i32.add (local.get $draw-dst) (i32.const 4)))
          (i32.const 0x1f))))

    (br_if $bytes
      (local.tee $draw-src (i32.sub (local.get $draw-src) (i32.const 1)))))
)
