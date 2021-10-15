;; Memory map:
;;
;; [0x0000-0x000b] C B E D L H F A SP PC
;; [0x000c-0x000f] both / directions / buttons / neither
;; [0x0010-0x0017] &B &C &D &E &H &L ~ &A
;; [0x0018-0x001b] &BC, &DE, &HL, &SP
;; [0x001c-0x001f] &BC, &DE, &HL, &HL

;; [0x0020-0x0023] F_mask
;; [0x0024-0x0043] palette

;; [0x0044-0x00db] opcode decode table
;; [0x00dc-0x00ed] opcode decode table

;; [0x8000-0x9fff] vram
;; [0xc000-0xdfff] work ram
;; [0xfe00-0xffff] OAM, I/O, hram

;; [0x010000-0x10ffff] ROM
;; [0x110000-0x117fff] External RAM
;; [0x118000-0x12e800] framebuffer

(global $rom1 (mut i32) (i32.const 0x014000))
(global $extrambank (mut i32) (i32.const 0x110000))
(global $IME (mut i32) (i32.const 0))
(global $halt (mut i32) (i32.const 0))
(global $ppu-dot (mut i32) (i32.const 32))
(global $cycles (mut i32) (i32.const 0))
(global $ff00 i32 (i32.const 0xff00))

(memory (export "mem") 19)

(func $tick
  (global.set $cycles (i32.add (global.get $cycles) (i32.const 4)))
)

(func $decodeop (param $opcode i32) (param $table i32) (result i32)
  (loop $loop
    (local.set $table (i32.add (local.get $table) (i32.const 3)))
    (br_if $loop
      (i32.ne
        (i32.and (local.get $opcode) (i32.load8_u (local.get $table)))
        (i32.load8_u offset=1 (local.get $table)))))
  (i32.load8_u offset=2 (local.get $table))
)

(func $mem8 (param $addr i32) (param $val i32) (param $read i32) (result i32)
  (local $i i32)
  (call $tick)

  block $default-read
  block $default
  block $io-read
  block $io-write
  block $7
  block $5
  block $3
  block $2
  block $0
  block $1
  (br_table $0 $1 $2 $3 $default $5 $default $7
            (i32.shr_u (local.get $addr) (i32.const 13)))
  end $1  ;; ROM0
    (br_if $0 (local.get $read))
    ;; remap ROM1
    (global.set $rom1
      (i32.add
        (i32.const 0x010000)
        (i32.shl
          (select
            (i32.and (local.get $val) (i32.const 63))
            (i32.const 1)
            (local.get $val))
          (i32.const 14))))
    ;; fallthrough
  end $0  ;; ROM0
    (local.set $addr (i32.add (i32.const 0x010000) (local.get $addr)))
    (br $default-read)

  end $2  ;; ROM1
    (br_if $3 (i32.eqz (local.get $read)))
    (br_if $3 (i32.gt_u (local.get $val) (i32.const 3)))

    ;; remap extrambank
    (global.set $extrambank
      (i32.add
        (i32.const 0x110000)
        (i32.shl (local.get $val) (i32.const 13))))
    ;; fallthrough
  end $3  ;; ROM1
    (local.set $addr (i32.add (global.get $rom1)
                              (i32.and (local.get $addr) (i32.const 0x3fff))))
    (br $default-read)

  end $5  ;; External RAM
    (local.set $addr (i32.add (global.get $extrambank)
                              (i32.and (local.get $addr) (i32.const 0x1fff))))
    (br $default)

  end $7  ;; OAM I/O HRAM
    (br_if $default (i32.lt_u (local.get $addr) (i32.const 0xfe00)))
    (br_if $io-read (local.get $read))
    (br_if $io-write (i32.ne (local.get $addr) (i32.const 0xff46)))

    ;; copy mem -> OAM
    (local.set $i (i32.const 159))
    (loop $loop
      (i32.store8 offset=0xfe00
        (local.get $i)
        (call $read8
          (i32.or (i32.shl (local.get $val) (i32.const 8)) (local.get $i))))
      (br_if $loop
        (i32.ge_s
          (local.tee $i (i32.sub (local.get $i) (i32.const 1)))
          (i32.const 0))))
    ;; fallthrough

  end $io-write
    (i32.store8 (local.get $addr) (local.get $val))
    ;; fallthrough

  end $io-read
    (br_if $default-read (i32.ne (local.get $addr) (i32.const 0xff00)))
    ;; read joypad
    (return
      (i32.load8_u offset=0x0c
        (i32.and
          (i32.shr_u
            (i32.xor (i32.load8_u (global.get $ff00)) (i32.const 0xff))
            (i32.const 4))
          (i32.const 3))))

  end $default
    (br_if $default-read (local.get $read))
    (i32.store8 (local.get $addr) (local.get $val))
    ;; fallthrough

  end $default-read
    (return (i32.load8_u (local.get $addr)))

  unreachable
)

(func $read8 (param $addr i32) (result i32)
  (call $mem8 (local.get $addr) (i32.const 0) (i32.const 1))
)

(func $readpc (result i32)
  (local $pc i32)
  (call $read8 (local.tee $pc (i32.load16_u (i32.const 0x0a))))
  (i32.store16 (i32.const 0x0a) (i32.add (local.get $pc) (i32.const 1)))
)

(func $read16 (param $reg-addr i32) (result i32)
  (local $addr i32)
  (i32.or
    (call $read8 (local.tee $addr (i32.load16_u (local.get $reg-addr))))
    (i32.shl
      (call $read8 (i32.add (local.get $addr) (i32.const 1)))
      (i32.const 8)))
  (i32.store16 (local.get $reg-addr) (i32.add (local.get $addr) (i32.const 2)))
)

(func $push (param $val i32)
  (local $sp i32)
  (call $mem8
    (local.tee $sp (i32.sub (i32.load16_u (i32.const 0x08)) (i32.const 1)))
    (i32.shr_u (local.get $val) (i32.const 8))
    (i32.const 0))
  (call $mem8
    (local.tee $sp (i32.sub (local.get $sp) (i32.const 1)))
    (local.get $val)
    (i32.const 0))
  (i32.store16 (i32.const 0x08) (local.get $sp))
  (call $tick)
  return
)

(func $reg8-access (param $val i32) (param $read i32) (param $o i32) (result i32)
  (if (result i32)
    (i32.eq (local.tee $o (i32.and (local.get $o) (i32.const 7))) (i32.const 6))
    (then
      (call $mem8 (i32.load16_u (i32.const 4)) (local.get $val) (local.get $read)))
    (else
      (if (i32.eqz (local.get $read))
        (then (i32.store8 (i32.load8_u offset=0x10 (local.get $o))
                          (local.get $val))))
      (i32.load8_u (i32.load8_u offset=0x10 (local.get $o)))))
)

(func $reg8-write (param $val i32) (param $o i32) (result i32)
  (call $reg8-access (local.get $val) (i32.const 0) (local.get $o))
)

(func $set-flags (param $mask i32) (param $z i32) (param $n i32) (param $h i32) (param $c i32)
  (i32.store8 (i32.const 6)
    (i32.or
      (i32.or
        (i32.or
          (i32.or
            (i32.and (i32.load8_u (i32.const 6)) (local.get $mask))
            (i32.shl (i32.eqz (local.get $z)) (i32.const 7)))
          (i32.shl (local.get $n) (i32.const 6)))
        (i32.shl (local.get $h) (i32.const 5)))
      (i32.shl (local.get $c) (i32.const 4))))
)

(func $get-color (param $tile i32) (param $y i32) (param $x i32) (result i32)
  (local $tile-addr i32)
  (i32.or
    (i32.shl
      (i32.and
        (i32.shr_u
          (i32.load8_u offset=0x8001
            (local.tee $tile-addr
              (i32.add
                (i32.shl (local.get $tile) (i32.const 4))
                (i32.shl
                  (i32.and (local.get $y) (i32.const 7))
                  (i32.const 1)))))
          (local.tee $x (i32.and (local.get $x) (i32.const 7))))
        (i32.const 1))
      (i32.const 1))
    (i32.and
      (i32.shr_u
        (i32.load8_u offset=0x8000 (local.get $tile-addr))
        (local.get $x))
      (i32.const 1)))
)

(func (export "run")
  (local $opcode i32)
  (local $opindex i32)
  (local $opcode&8 i32)
  (local $opcode>>3 i32)
  (local $opcode>>4 i32)
  (local $alu-operand i32)
  (local $operand i32)
  (local $~cond i32)
  (local $a i32)
  (local $f i32)
  (local $tmp i32)
  (local $hl i32)
  (local $sp i32)
  (local $neg i32)
  (local $carry i32)
  (local $bit i32)
  (local $prev-cycles i32)
  (local $lcdc i32)
  (local $ly i32)
  (local $is-bg i32)
  (local $x i32)
  (local $y i32)
  (local $palette-index i32)
  (local $tile i32)
  (local $color i32)
  (local $sprite i32)
  (local $sprite-color i32)
  (local $sprite-attr i32)
  (local $sprite-tile i32)
  (local $sprite-height-minus1 i32)
  (local $sprite8x16 i32)
  (local $IF i32)
  (local $STAT i32)
  (local $irq i32)
  (local $ly=lyc i32)

  (loop $loop
    (local.set $prev-cycles (global.get $cycles))

    block $ppu
    block $ppu-tick
    block $normal
    block $halt
    block $interrupt

    (br_if $interrupt
      (i32.and
        (i32.and
          (global.get $IME)
          (local.tee $IF (i32.load8_u offset=0x0f (global.get $ff00)))) ;; IF
        (i32.load8_u offset=0xff (global.get $ff00))))                  ;; IE
    (br_if $halt (global.get $halt))
    (br $normal)

    end $interrupt
      ;; clear the least-significant 1 bit
      (i32.store8 offset=0x0f
        (global.get $ff00)
        (i32.and
          (local.get $IF)
          (i32.xor
            ;; isolate least-significant 1 bit
            (local.tee $irq
              (i32.and (local.get $IF)
                       (i32.sub (i32.const 0) (local.get $IF))))
            (i32.const 0xff))))
      (global.set $IME (i32.const 0))
      (global.set $halt (i32.const 0))
      ;; push PC
      (call $push (i32.load16_u (i32.const 0x0a)))
      ;; PC = 0x38 + irq * 8
      (i32.store16
        (i32.const 0x0a)
        (i32.add (i32.const 56) (i32.shl (local.get $irq) (i32.const 3))))
      (call $tick)
      (br $ppu-tick)

    end $halt
      (br $ppu-tick)

    end $normal
      block $rotate
      block $v
      block $u
      block $t
      block $s
      block $r
      block $q
      block $p
      block $o
      block $n
      block $m
      block $l
      block $k
      block $j
      block $i
      block $alu
      block $subtract
      block $h
      block $g
      block $f
      block $e
      block $d
      block $c
      block $b
      block $a
      block $9
      block $8
      block $7
      block $6
      block $5
      block $4
      block $3
      block $2
      block $1
      block $0
      block $y
      block $z

      (local.set $opcode (call $readpc))
      (local.set $opcode&8 (i32.and (local.get $opcode) (i32.const 8)))
      (local.set $opcode>>3
        (i32.and (i32.shr_u (local.get $opcode) (i32.const 3))
                 (i32.const 7)))
      (local.set $opcode>>4
        (i32.and (i32.shr_u (local.get $opcode) (i32.const 4))
                 (i32.const 3)))

      (local.set $f (i32.load8_u (i32.const 6)))
      (local.set $~cond
        (i32.xor
          (i32.eqz
            (i32.eqz
              (i32.and
                (local.get $f)
                (i32.load8_u offset=0x20
                  (i32.and
                    (local.get $opcode>>3)
                    (i32.const 3))))))
          (i32.and
            (local.get $opcode>>3)
            (i32.const 1))))
      (local.set $a (i32.load8_u (i32.const 7)))

      ;; decode opcode
      (local.set $opindex
        (call $decodeop (local.get $opcode) (i32.const 0x41)))

      (br_table $z $z $z $z $z $z $z $0 $1 $2 $3 $4 $5 $6 $7 $8
                $9 $a $b $d $y $y $y $y $y $y $y $k $l $m $n $o
                $p $q $r $s $t $u $v
        (local.get $opindex))

      end $z  ;; ALU operation w/ immediate
        (local.set $alu-operand (call $readpc))
        (br_table $e $f $g $h $i $j (local.get $opindex))

      end $y  ;; opcode with reg8-access operand

      (local.set $alu-operand
        (local.tee $operand
          (call $reg8-access
            (i32.const 0)
            (i32.const 1)
            (local.get $opcode))))

      (br_table $c $e $f $g $h $i $j
        (i32.sub (local.get $opindex) (i32.const 0x14)))

      end $0  ;; nop
        (br $ppu)

      end $1  ;; ld r16, u16
        (i32.store16
          (i32.load8_u offset=0x18 (local.get $opcode>>4))
          (call $read16 (i32.const 0x0a)))
        (br $ppu)

      end $2  ;; ld a, (r16) / ld (r16), a
        (call $reg8-access
          (call $mem8
            (i32.load16_u (i32.load8_u offset=0x1c (local.get $opcode>>4)))
            (local.get $a)
            (local.get $opcode&8))
          (i32.eqz (local.get $opcode&8))
          (i32.const 7))

        (br_if $ppu (i32.lt_u (local.get $opcode>>4) (i32.const 2)))

        ;; inc/dec HL
        (i32.store16 (i32.const 4)
          (i32.add
            (i32.load16_u (i32.const 4))
            (i32.sub
              (i32.const 5)
              (i32.mul (local.get $opcode>>4) (i32.const 2)))))

        (br $ppu)

      end $3  ;; dec r16 / inc r16
        (i32.store16
          (local.tee $tmp (i32.load8_u offset=0x18 (local.get $opcode>>4)))
          (i32.add
            (i32.load16_u (local.get $tmp))
            (select
              (i32.const -1)
              (i32.const 1)
              (local.get $opcode&8))))
        (br $ppu-tick)

      end $4  ;; dec r8 / dec (hl) / inc r8 / inc (hl)
        (local.set $operand
          (call $reg8-access
            (i32.const 0)
            (i32.const 1)
            (local.get $opcode>>3)))
        (local.set $neg (i32.and (local.get $opcode) (i32.const 1)))
        (call $reg8-write
          (local.tee $operand
            (i32.add
              (local.get $operand)
              (select (i32.const -1) (i32.const 1) (local.get $neg))))
          (local.get $opcode>>3))
        (call $set-flags
          (i32.const 16)
          (i32.and (local.get $operand) (i32.const 255))
          (local.get $neg)
          (i32.eqz
            (i32.and (i32.add (local.get $operand) (local.get $neg))
                     (i32.const 15)))
          (i32.const 0))
        (br $ppu)

      end $5  ;; ld r8, u8 / ld (hl), u8
        (call $reg8-write
              (call $readpc)
              (local.get $opcode>>3))
        (br $ppu)

      end $6  ;; add hl, r16
        (local.set $tmp
          (i32.load16_u (i32.load8_u offset=0x18 (local.get $opcode>>4))))
        (call $set-flags
          (i32.const 128)
          (i32.const 1)
          (i32.const 0)
          (i32.gt_u
            (i32.add
              (i32.and
                (local.tee $hl (i32.load16_u (i32.const 4)))
                (i32.const 4095))
              (i32.and (local.get $tmp) (i32.const 4095)))
            (i32.const 4095))
          (i32.gt_u
            (i32.add (local.get $hl) (local.get $tmp))
            (i32.const 65535)))
        (i32.store16 (i32.const 4) (i32.add (local.get $hl) (local.get $tmp)))
        (br $ppu-tick)

      end $7  ;; rla / rlca / rrca / rra
        (local.set $neg (i32.const 1))
        (br $rotate)

      end $8  ;; jr i8 / jr <cond>, i8
        (local.set $tmp (call $readpc))
        (br_if $ppu (i32.and (i32.ne (local.get $opcode) (i32.const 0x18))
                             (local.get $~cond)))
        (i32.store16 (i32.const 0x0a)
          (i32.add
            (i32.load16_u (i32.const 0x0a))
            (i32.extend8_s (local.get $tmp))))
        (br $ppu-tick)

      end $9  ;; daa
        (local.set $carry (local.tee $tmp (i32.const 0)))
        (local.set $neg (i32.and (local.get $f) (i32.const 64)))

        (if (i32.or
              (i32.eqz (i32.eqz (i32.and (local.get $f) (i32.const 32))))
              (i32.and
                (i32.eqz (local.get $neg))
                (i32.gt_u (i32.and (local.get $a) (i32.const 15)) (i32.const 9))))
          (then
            (local.set $tmp (i32.const 6))))

        (if (i32.or
              (i32.eqz (i32.eqz (i32.and (local.get $f) (i32.const 16))))
              (i32.and
                (i32.eqz (local.get $neg))
                (i32.gt_u (local.get $a) (i32.const 153))))
          (then
            (local.set $tmp (i32.or (local.get $tmp) (i32.const 96)))
            (local.set $carry (i32.const 1))))

        (call $set-flags
          (i32.const 65)
          (call $reg8-write
            (i32.add
              (local.get $a)
                (i32.mul
                  (select (i32.const -1) (i32.const 1) (local.get $neg))
                  (local.get $tmp)))
                (i32.const 7))
          (i32.const 0)
          (i32.const 0)
          (local.get $carry))
        (br $ppu)

      end $a  ;; cpl
        (i32.store8 (i32.const 7) (i32.xor (local.get $a) (i32.const 255)))
        (call $set-flags
          (i32.const 144)
          (i32.const 1)
          (i32.const 1)
          (i32.const 1)
          (i32.const 0))
        (br $ppu)

      end $b  ;; scf / ccf
        (call $set-flags
          (i32.const 128)
          (i32.const 1)
          (i32.const 0)
          (i32.const 0)
          (select
            (i32.eqz (i32.and (local.get $f) (i32.const 16)))
            (i32.const 1)
            (local.get $opcode&8)))
        (br $ppu)

      end $c  ;; ld r8, r8 / ld r8, (hl) / ld (hl), r8
        (call $reg8-write
          (local.get $operand)
          (local.get $opcode>>3))
        (br $ppu)

      end $d  ;; halt
        (global.set $halt (i32.const 1))
        (br $ppu)

      end $e  ;; add a, r8 / add a, (hl) / add a, u8
        (local.set $neg
          (local.tee $carry
            (i32.const 0)))
        (br $alu)

      end $f  ;; adc a, r8 / adc a, (hl) / adc a, u8
        (local.set $neg (i32.const 0))
        (local.set $carry
          (i32.and (i32.shr_u (local.get $f) (i32.const 4))
                   (i32.const 1)))
        (br $alu)

      end $g  ;; cp a, r8 / cp a, (hl) / cp a, u8
              ;; sub a, r8 / sub a, (hl) / sub a, u8
        (local.set $carry (i32.const 1))
        (br $subtract)

      end $h  ;; sbc a, r8 / sbc a, (hl) / sbc a, u8
        (local.set $carry
          (i32.eqz
            (i32.and (i32.shr_u (local.get $f) (i32.const 4))
                     (i32.const 1))))
        ;; fallthrough

      end $subtract
        (local.set $neg (i32.const 1))
        (local.set $alu-operand (i32.xor (local.get $alu-operand) (i32.const 255)))
        ;; fallthrough

      end $alu
        (call $set-flags
          (i32.const 0)
          (i32.and
            (local.tee $tmp
              (i32.add
                (i32.add
                  (local.get $a)
                  (local.get $alu-operand))
                (local.get $carry)))
            (i32.const 255))
          (local.get $neg)
          (i32.xor
            (i32.gt_u
              (i32.add
                (i32.add
                  (i32.and (local.get $a) (i32.const 15))
                  (i32.and (local.get $alu-operand) (i32.const 15)))
                (local.get $carry))
              (i32.const 15))
            (local.get $neg))
          (i32.xor
            (i32.gt_u (local.get $tmp) (i32.const 255))
            (local.get $neg)))

        ;; skip setting A for CP *
        (br_if $ppu (i32.eq (local.get $opcode>>3) (i32.const 7)))
        (i32.store8 (i32.const 7) (local.get $tmp))
        (br $ppu)

      end $i  ;; and a, r8 / and a, (hl) / and a, u8
        (call $set-flags
          (i32.const 0)
          (call $reg8-write
            (i32.and (local.get $a) (local.get $alu-operand))
            (i32.const 7))
          (i32.const 0)
          (i32.const 1)
          (i32.const 0))
        (br $ppu)

      end $j  ;; xor/or a, r8 / xor/or a, (hl) / xor/or a, u8
        (call $set-flags
          (i32.const 0)
          (call $reg8-write
            (select
              (i32.or (local.get $a) (local.get $alu-operand))
              (i32.xor (local.get $a) (local.get $alu-operand))
              (i32.and (local.get $opcode) (i32.const 0x10)))
            (i32.const 7))
          (i32.const 0)
          (i32.const 0)
          (i32.const 0))
        (br $ppu)

      end $k  ;; reti
        (local.set $~cond (i32.const 0))
        (global.set $IME (i32.const 3))
        ;; fallthrough

      end $l  ;; ret / ret <cond>
        (call $tick)
        (br_if $ppu (i32.and (i32.ne (local.get $opcode) (i32.const 0xc9))
                             (local.get $~cond)))
        (i32.store16 (i32.const 0x0a) (call $read16 (i32.const 0x08)))
        (br $ppu)

      end $m  ;; pop r16
        (i32.store16 (i32.shl (local.get $opcode>>4) (i32.const 1))
                     (call $read16 (i32.const 0x08)))
        (br $ppu)

      end $n  ;; call/jp u16 / call/jp <cond>, u16 / rst $NN
        (local.set $tmp
          (if (result i32)
            (i32.eq (i32.and (local.get $opcode) (i32.const 7)) (i32.const 7))
            (then (i32.and (local.get $opcode) (i32.const 0x38)))  ;; rst
            (else (call $read16 (i32.const 0x0a)))))               ;; call/jp

        (br_if $ppu
          (i32.and (i32.eqz (i32.and (local.get $opcode) (i32.const 1)))
                   (local.get $~cond)))

        (if (i32.and (local.get $opcode) (i32.const 4))
          (then (call $push (i32.load16_u (i32.const 0x0a))))  ;; CALL
          (else (call $tick)))                                 ;; JP
        (i32.store16 (i32.const 0x0a) (local.get $tmp)) ;; PC = tmp
        (br $ppu)

      end $o  ;; push r16
        (call $push (i32.load16_u (i32.shl (local.get $opcode>>4) (i32.const 1))))
        (br $ppu)

      end $p  ;; ldh a, u8 / ldh a, c / ld a, (u16)
              ;; ldh u8, a / ldh c, a / ld (u16), a
        (local.set $tmp (i32.and (local.get $opcode) (i32.const 16)))
        (call $reg8-access
          (call $mem8
            (if (result i32)
              (local.get $opcode&8)
              (then (call $read16 (i32.const 0x0a)))
              (else
                (i32.add
                  (i32.const 0xff00)
                  (if (result i32)
                    (i32.and (local.get $opcode) (i32.const 2))
                    (then (i32.load8_u (i32.const 0)))
                    (else (call $readpc))))))
            (local.get $a)
            (local.get $tmp))
          (i32.eqz (local.get $tmp))
          (i32.const 7))
        (br $ppu)

      end $q  ;; jp hl
        (i32.store16 (i32.const 0x0a) (i32.load16_u (i32.const 4)))
        (br $ppu)

      end $r  ;; di / ei
        (global.set $IME
          (i32.mul (i32.eq (local.get $opcode) (i32.const 0xfb))
                   (i32.const 3)))
        (br $ppu)

      end $s  ;; ld hl, sp + i8 / add sp, i8
        (i32.store16
          (if (result i32) (i32.and (local.get $opcode) (i32.const 16))
            (then (i32.const 0x4))                ;; ld hl, sp + i8
            (else (call $tick) (i32.const 0x8)))  ;; add sp, i8
          (i32.add
            (local.tee $sp (i32.load16_u (i32.const 0x8)))
            (i32.extend8_s (local.tee $tmp (call $readpc)))))
        (call $set-flags
          (i32.const 0)
          (i32.const 1)
          (i32.const 0)
          (i32.gt_u
            (i32.add
              (i32.and (local.get $sp) (i32.const 15))
              (i32.and (local.get $tmp) (i32.const 15)))
            (i32.const 15))
          (i32.gt_u
            (i32.add
              (i32.and (local.get $sp) (i32.const 255))
              (local.get $tmp))
            (i32.const 255)))
        (br $ppu-tick)

      end $t  ;; ld sp, hl
        (i32.store16 (i32.const 0x08) (i32.load16_u (i32.const 4)))
        (br $ppu-tick)

      end $u  ;; ld (u16), sp
        (call $mem8
          (local.tee $tmp (call $read16 (i32.const 0x0a)))
          (local.tee $sp (i32.load16_u (i32.const 0x08)))
          (i32.const 0))
        (call $mem8
          (i32.add (local.get $tmp) (i32.const 1))
          (i32.shr_u (local.get $sp) (i32.const 8))
          (i32.const 0))
        (br $ppu-tick)

      end $v  ;; cb prefix
        ;; read next byte
        (local.set $neg (i32.const 0))
        (local.set $opcode (call $readpc))

      end $rotate

        block $5
        block $4
        block $3
        block $shift
        block $2
        block $1
        block $0

        (local.set $opcode>>3
          (i32.and (i32.shr_u (local.get $opcode) (i32.const 3))
                   (i32.const 7)))
        (local.tee $operand
          (call $reg8-access (i32.const 0) (i32.const 1) (local.get $opcode)))
        (local.set $bit (i32.shl (i32.const 1) (local.get $opcode>>3)))

        (local.set $opindex (call $decodeop (local.get $opcode) (i32.const 0xd1)))
        (br_table $0 $1 $2 $3 $4 $5 (local.get $opindex))

        end $0  ;; rlc r8 / rlc (hl) / rl r8 / rl (hl) / sla r8 / sla (hl)
          (local.set $carry (i32.shr_u (local.get $operand) (i32.const 7)))
          (local.set $tmp
            (i32.add
              (i32.shl (local.get $operand) (i32.const 1))
              (select
                (i32.and (i32.shr_u (local.get $f) (i32.const 4)) (i32.const 1))
                (select
                  (i32.const 0)
                  (local.get $carry)
                  (i32.and (local.get $opcode) (i32.const 32)))
                (i32.and (local.get $opcode) (i32.const 16)))))
          (br $shift)

        end $1  ;; rrc r8 / rrc (hl) / rr r8 / rr (hl) / sra r8 / sra (hl) / srl r8 / srl (hl)
          (local.set $carry (i32.and (local.get $operand) (i32.const 1)))
          (local.set $tmp
            (select
              (i32.shr_s
                (i32.extend8_s (local.get $operand))
                (i32.const 1))
              (i32.add
                (i32.shr_u (local.get $operand) (i32.const 1))
                (select
                  (i32.const 0)
                  (select
                    (i32.and (i32.shl (local.get $f) (i32.const 3)) (i32.const 128))
                    (i32.shl (local.get $carry) (i32.const 7))
                    (i32.and (local.get $opcode) (i32.const 16)))
                  (i32.and (local.get $opcode) (i32.const 32))))
              (i32.eq (i32.and (local.get $opcode) (i32.const 48)) (i32.const 32))))
          (br $shift)

        end $2  ;; swap r8 / swap (hl)
          (local.set $carry (i32.const 0))
          (local.set $tmp
            (i32.or
              (i32.shl (local.get $operand) (i32.const 4))
              (i32.shr_u (local.get $operand) (i32.const 4))))
          ;; fallthrough

        end $shift
          (call $reg8-write (local.get $tmp) (local.get $opcode))
          (call $set-flags
            (i32.const 0)
            (i32.or
              (local.get $neg)
              (i32.eqz (i32.eqz (i32.and (local.get $tmp) (i32.const 255)))))
            (i32.const 0)
            (i32.const 0)
            (local.get $carry))
          (br $ppu)

        end $3  ;; bit b, r8 / bit b, (hl)
          (call $set-flags
            (i32.const 16)
            (i32.and (local.get $operand) (local.get $bit))
            (i32.const 0)
            (i32.const 1)
            (i32.const 0))
          (br $ppu)

        end $4  ;; res b, r8 / res b, (hl)
          (call $reg8-write
            (i32.and (local.get $operand)
                     (i32.xor (local.get $bit) (i32.const 0xff)))
            (local.get $opcode))
          (br $ppu)

        end $5  ;; set b, r8 / set b, (hl)
          (call $reg8-write
            (i32.or (local.get $operand) (local.get $bit))
            (local.get $opcode))
          (br $ppu)

    end $ppu-tick
      (call $tick)
      ;; fallthrough

    end $ppu
      (local.set $prev-cycles
        (i32.sub (global.get $cycles) (local.get $prev-cycles)))
      ;; update DIV register
      (i32.store16 offset=0x03 (global.get $ff00)
        (i32.add
          (i32.load16_u offset=0x03 (global.get $ff00))
          (local.get $prev-cycles)))
      loop $loop
        (if $done (i32.and (local.tee $lcdc
                             (i32.load8_u offset=0x40 (global.get $ff00)))
                           (i32.const 128))
          (then
            (global.set $ppu-dot (i32.add (global.get $ppu-dot) (i32.const 1)))

            (br_if $done (i32.ne (global.get $ppu-dot) (i32.const 456)))

            ;; finished a scanline
            (if (i32.lt_u (local.tee $ly
                            (i32.load8_u offset=0x44 (global.get $ff00)))
                          (i32.const 144))
              (then
                ;; loop through all pixels this line
                (local.set $tmp (i32.const 159))
                (loop $pixel
                  (if
                    ;; is-bg = !(LCDC & 32) ||
                    ;;         (y = LY - mem[0xff4a]) < 0 ||
                    ;;         (x = tmp - mem[0xff4b] + 7) < 0
                    (local.tee $is-bg
                      (i32.or
                        (i32.or
                          (i32.eqz (i32.and (local.get $lcdc) (i32.const 32)))
                          (i32.lt_s
                            (local.tee $y
                              (i32.sub
                                (local.get $ly)
                                (i32.load8_u offset=0x4a (global.get $ff00))))
                            (i32.const 0)))
                        (i32.lt_s
                          (local.tee $x
                            (i32.add
                              (i32.sub
                                (local.get $tmp)
                                (i32.load8_u offset=0x4b (global.get $ff00)))
                              (i32.const 7)))
                          (i32.const 0))))
                    (then
                      ;; x = tmp + mem[0xff43]
                      ;; y = ly + mem[0xff42]
                      (local.set $x
                        (i32.add (local.get $tmp)
                                 (i32.load8_u offset=0x43 (global.get $ff00))))
                      (local.set $y
                        (i32.add (local.get $ly)
                                 (i32.load8_u offset=0x42 (global.get $ff00))))))

                  (local.set $palette-index (i32.const 0))
                  (local.set $tile
                    (i32.load8_u offset=0x8000
                      (i32.or
                        (i32.or
                          (i32.shl
                            (select
                              (i32.const 7)
                              (i32.const 6)
                              (i32.and
                                (local.get $lcdc)
                                (select
                                  (i32.const 8)
                                  (i32.const 64)
                                  (local.get $is-bg))))
                            (i32.const 10))
                          (i32.shl
                            (i32.and
                              (i32.shr_u (local.get $y) (i32.const 3))
                              (i32.const 31))
                            (i32.const 5)))
                        (i32.and
                          (i32.shr_u (local.get $x) (i32.const 3))
                          (i32.const 31)))))

                  (local.set $color
                    (call $get-color
                      (select
                        (local.get $tile)
                        (i32.add
                          (i32.const 256)
                          (i32.extend8_s (local.get $tile)))
                        (i32.and (local.get $lcdc) (i32.const 16)))
                      (local.get $y)
                      (i32.xor (local.get $x) (i32.const 7))))

                  ;; render sprites
                  (if $sprites-done (i32.and (local.get $lcdc) (i32.const 2))
                    (then
                      ;; check whether sprites are 8x16 or 8x8
                      (local.set $sprite8x16
                        (i32.and (i32.shr_u (local.get $lcdc) (i32.const 2))
                                 (i32.const 1)))
                      (local.set $sprite (i32.const 0xfe00))
                      (loop $sprite
                        ;; sprite-y offset is ly - sprite[0] + 16; however, if
                        ;; the sprite is y-fliiped, then we also need to xor w/
                        ;; 7 (for 8x8 sprites) or 15 (for 8x16 sprites)
                        (local.set $y
                          (i32.xor
                            (i32.add
                              (i32.sub
                                (local.get $ly)
                                (i32.load8_u (local.get $sprite)))
                              (i32.const 16))
                            (select
                              (local.tee $sprite-height-minus1
                                (select
                                  (i32.const 15)
                                  (i32.const 7)
                                  (local.get $sprite8x16)))
                              (i32.const 0)
                              (i32.and
                                (local.tee $sprite-attr
                                  (i32.load8_u offset=3 (local.get $sprite)))
                                (i32.const 64)))))
                        ;; sprite-x offset is tmp - sprite[1] + 8; also xor w/
                        ;; 7 if the sprite is x-flipped.
                        (local.set $x
                          (i32.xor
                            (i32.add
                              (i32.sub
                                (local.get $tmp)
                                (i32.load8_u offset=1 (local.get $sprite)))
                              (i32.const 8))
                            (select
                              (i32.const 0)
                              (i32.const 7)
                              (i32.and (local.get $sprite-attr) (i32.const 32)))))
                        (local.set $sprite-color
                          (call $get-color
                            (select
                              (i32.and
                                (local.tee $sprite-tile
                                  (i32.load8_u offset=2 (local.get $sprite)))
                                (i32.xor (local.get $sprite8x16) (i32.const 255)))
                              (i32.or
                                (local.get $sprite-tile)
                                (local.get $sprite8x16))
                              (i32.lt_u (local.get $y) (i32.const 8)))
                            (local.get $y)
                            (local.get $x)))

                        ;; only draw the sprite if the x/y coordinates are in
                        ;; bounds. For y, that depends on whether it is a 8x8
                        ;; or 8x16 sprite.
                        ;;
                        ;; The sprite pixel color should only be chosen if the
                        ;; sprite is non-zero color, and has priority or the
                        ;; background is zero.
                        (if
                          (i32.and
                            (i32.and
                              (i32.lt_u (local.get $x) (i32.const 8))
                              (i32.le_u (local.get $y) (local.get $sprite-height-minus1)))
                            (i32.and
                              (i32.or
                                (i32.eqz
                                  (i32.and (local.get $sprite-attr) (i32.const 128)))
                                (i32.eqz (local.get $color)))
                              (i32.eqz (i32.eqz (local.get $sprite-color)))))
                          (then
                            (local.set $color (local.get $sprite-color))
                            (local.set $palette-index
                              (i32.add
                                (i32.const 1)
                                (i32.eqz
                                  (i32.eqz
                                    (i32.and (local.get $sprite-attr) (i32.const 16))))))
                            ;; don't process any later sprites once we found
                            ;; one to draw (this gives priority to the lowest
                            ;; numbered sprite.
                            (br $sprites-done)))

                        (br_if $sprite
                          (i32.lt_u
                            (local.tee $sprite
                              (i32.add (local.get $sprite) (i32.const 4)))
                            (i32.const 0xfea0))))))

                  ;; draw pixel
                  (i32.store offset=0x118000
                    (i32.shl
                      (i32.add
                        (i32.mul (local.get $ly) (i32.const 160))
                        (local.get $tmp))
                      (i32.const 2))
                    (i32.load offset=0x24
                      (i32.shl
                        (i32.and
                          (i32.add
                            (i32.and
                              (i32.shr_u
                                (i32.load8_u offset=0xff47 (local.get $palette-index))
                                (i32.shl
                                  (local.get $color)
                                  (i32.const 1)))
                              (i32.const 3))
                            (i32.shl (local.get $palette-index) (i32.const 2)))
                          (i32.const 7))
                        (i32.const 2))))

                  (br_if $pixel
                    (i32.ge_s
                      (local.tee $tmp (i32.sub (local.get $tmp) (i32.const 1)))
                      (i32.const 0))))))

            (i32.store8 offset=0x44 (global.get $ff00)
              (i32.rem_u
                (i32.add (local.get $ly) (i32.const 1))
                (i32.const 154)))
            (global.set $ppu-dot (i32.const 0))

            (i32.store8 offset=0x0f (global.get $ff00)
              (i32.or
                (i32.or
                  (local.get $IF)
                  ;; trigger VBLANK at end of frame
                  (local.tee $tmp (i32.eq (local.get $ly) (i32.const 143))))
                ;; if LY=LYC and the enable bit is set, then trigger a STAT
                ;; interrupt
                (i32.shl
                  (i32.and
                    (local.tee $ly=lyc
                      (i32.eq (local.get $ly)
                              (i32.load8_u offset=0x45 (global.get $ff00))))
                    (i32.and
                      (i32.shr_u
                        (local.tee $STAT
                          (i32.load8_u offset=0x41 (global.get $ff00)))
                        (i32.const 6))
                      (i32.const 1)))
                  (i32.const 1))))

            ;; set/reset the LY=LYC bit
            (i32.store8 offset=0x41 (global.get $ff00)
              (i32.or (i32.and (local.get $STAT) (i32.const 0xfd))
                      (i32.shl (local.get $ly=lyc) (i32.const 1))))

            ;; return if end of frame
            (br_if 3 (local.get $tmp)))
          (else
            (i32.store8 offset=0x44 (global.get $ff00) (i32.const 0))
            (global.set $ppu-dot (i32.const 0))))

        (br_if $loop
          (local.tee $prev-cycles
            (i32.sub (local.get $prev-cycles) (i32.const 1))))
      end

    (br $loop))
)

(data (i32.const 0)
  (i8 19 0 216 0 77 1 176 1) (i16 65534 256)  ;; C B E D L H A SP PC
  (i8 0xff 0xef 0xdf 0xcf)                    ;; unused
  (i8 1 0 3 2 5 4 0 7)                        ;; &B &C &D &E &H &L ~ &A
  (i8 0 2 4 8)                                ;; &BC &DE &HL &SP
  (i8 0 2 4 4)                                ;; &BC &DE &HL &HL

  (i8  128 128 16 16)                         ;; F_mask
  (i32 -1 -23197   -65536    -16777216
       -1 -8092417 -12961132 -16777216)       ;; palette

  ;; opcode decode tables (sorted by frequency used in pokemon)
  (i8 0xff 0x00 0x07)  ;; nop            (must come before jr*)
  (i8 0xff 0x08 0x25)  ;; ld (u16), sp   (must come before jr*)
  (i8 0xc7 0x00 0x0f)  ;; jr i8 / jr <cond>, i8
  (i8 0xef 0xe0 0x20)  ;; ldh u8, a / ldh a, u8
  (i8 0xf8 0xb8 0x17)  ;; cp a, r8
  (i8 0xc6 0x04 0x0b)  ;; dec r8 / inc r8
  (i8 0xe7 0xe2 0x20)  ;; ldh a, c / ld a, (u16) / ldh c, a / ld (u16), a
  (i8 0xf8 0xa0 0x19)  ;; and a, r8
  (i8 0xcf 0xc1 0x1d)  ;; pop r16
  (i8 0xff 0x76 0x13)  ;; halt   (must come before ld r8, r8)
  (i8 0xc0 0x40 0x14)  ;; ld r8, r8
  (i8 0xff 0xcd 0x1e)  ;; call u16
  (i8 0xcf 0x01 0x08)  ;; ld r16, u16
  (i8 0xff 0xc9 0x1c)  ;; ret
  (i8 0xcf 0x09 0x0d)  ;; add hl, r16
  (i8 0xff 0xfe 0x02)  ;; cp a, u8
  (i8 0xff 0xe6 0x04)  ;; and a, u8
  (i8 0xc7 0x06 0x0c)  ;; ld r8, u8
  (i8 0xf8 0xb0 0x1a)  ;; or a, r8
  (i8 0xf8 0x80 0x15)  ;; add a, r8
  (i8 0xc7 0x03 0x0a)  ;; dec r16 / inc r16
  (i8 0xf8 0xa8 0x1a)  ;; xor a, r8
  (i8 0xe7 0xc0 0x1c)  ;; ret <cond>
  (i8 0xe7 0x07 0x0e)  ;; rla / rlca / rrca / rra
  (i8 0xc7 0x02 0x09)  ;; ld a, (r16) / ld (r16), a
  (i8 0xff 0xcb 0x26)  ;; cb prefix
  (i8 0xff 0xc6 0x00)  ;; add a, u8
  (i8 0xff 0xd6 0x02)  ;; sub a, u8
  (i8 0xff 0xde 0x03)  ;; sbc a, u8
  (i8 0xff 0xce 0x01)  ;; adc a, u8
  (i8 0xe1 0xc0 0x1e)  ;; call/jp <cond>, u16
  (i8 0xcf 0xc5 0x1f)  ;; push r16
  (i8 0xff 0xe9 0x21)  ;; jp hl
  (i8 0xff 0x2f 0x11)  ;; cpl
  (i8 0xff 0xf9 0x24)  ;; ld sp, hl
  (i8 0xff 0xc3 0x1e)  ;; jp u16
  (i8 0xf8 0x98 0x18)  ;; sbc a, r8
  (i8 0xef 0xe8 0x23)  ;; ld hl, sp + i8 / add sp, i8
  (i8 0xf8 0x88 0x16)  ;; adc a, r8
  (i8 0xc7 0xc7 0x1e)  ;; rst nn
  (i8 0xff 0xd9 0x1b)  ;; reti
  (i8 0xf7 0x37 0x12)  ;; scf / ccf
  (i8 0xff 0xf6 0x06)  ;; or a, u8
  (i8 0xf8 0x90 0x17)  ;; sub a, r8
  (i8 0xff 0xee 0x05)  ;; xor a, u8
  (i8 0xf7 0xf3 0x22)  ;; di / ei
  (i8 0xff 0x27 0x10)  ;; daa
  (i8 0x00 0x00 0x07)  ;; terminator

   ;; cb
  (i8 0xf8 0x30 0x02)  ;; swap r8 / swap (hl)   (must come before rl*)
  (i8 0xc8 0x00 0x00)  ;; rlc r8 / rl r8 / sla r8
  (i8 0xc0 0x40 0x03)  ;; bit b, r8 / bit b, (hl)
  (i8 0xc8 0x08 0x01)  ;; rrc r8 / rr r8 / sra r8 / srl r8
  (i8 0xc0 0xc0 0x05)  ;; set b, r8 / set b, (hl)
  (i8 0xc0 0x80 0x04)  ;; res b, r8 / res b, (hl)
)

;; TODO better way to init?
(data (i32.const 0xff03) (i16 44032)) ;; DIV
(data (i32.const 0xff40) (i8 145))  ;; LCDC
