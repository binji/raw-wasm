(import "Math" "random" (func $random (result f32)))
(import "Math" "sin" (func $sin (param f32) (result f32)))
(import "env" "t" (func $timer (param i32))) ;; 1:start, 0:stop

;; The current game mode. 0: init, 1: wait, 2: reset, 3:game, 4:winning
(global $mode (mut i32) (i32.const 0))
;; The mode timer, in frames.
(global $mode-timer (mut i32) (i32.const 90))
;; The maximum wall to render or collide against. Used to clear the maze.
(global $max-wall-addr (mut i32) (i32.const 0x0ddc))

;; Position and direction vectors. Direction is updated from angle, which is
;; expressed in radians.
(global $Px (mut f32) (f32.const 21))
(global $Py (mut f32) (f32.const 21))
(global $angle (mut f32) (f32.const 0.7853981633974483))
(global $ray-x (mut f32) (f32.const 0))
(global $ray-y (mut f32) (f32.const 0))

;; Common constants. Cheap way to reduce the binary size.
(global $half-screen-height f32 (f32.const 120))
(global $zero f32 (f32.const 0))
(global $one-half f32 (f32.const 0.5))
(global $one f32 (f32.const 1))

;; The "time" of the ray-line collision along the wall in the range [0,1].
(global $min-t2 (mut f32) (f32.const 0))
;; The address of the wall hit by the most recent raycast.
(global $min-wall (mut i32) (i32.const 0))

;; Color: u32        ; ABGR
;; Cell2: u8*2       ; left/up cell, right/down cell
;; Wall: s8*4,u8*4  ; (x0,y0),(dx, dy), scale/texture/palette/dummy

;; [0x0000, 0x0004)   u8[4]           left/right/forward/back keys
;; [0x0004, 0x0008)   f32             rotation speed
;; [0x0008, 0x000c)   f32             speed
;; [0x0010, 0x00a0)   u8[12*12]       maze cells for Kruskal's algo
;; [0x00a0, 0x0192)   Cell2[11*11]    walls for Kruskal's algo
;; [0x0192, 0x02b0)   Cell2[120]      extra walls that are removed to make maze
;; [0x02b0, 0x06b0)   u8[32*32]       8bpp brick texture
;; [0x06b0, 0x0ab0)   u8[32*32]       8bpp spot texture
;; [0x0ab0, 0x0c90)   f32[120]        Table of 120/(120-y)
;; [0x0c90, 0x0d90)   u8[32*32]       RLE compressed 2bpp textures
;; [0x0d90, 0x0dac)   u8[28]          color index (into Palette table @0x11b0)
;; [0x0dac, 0x0ddc)   Wall[6]         constant walls
;; [0x0ddc, 0x11a4)   Wall[11*11]     generated walls
;; [0x11b0, 0x2fb0)   Color[120][16]  Palette table (120 levels of darkness)
;; [0x3000, 0x4e000)  Color[320*240]  canvas
(memory (export "mem") 5)

(data (i32.const 0x0c90)
  ;; brick texture 2bpp RLE compressed
  "\08\aa\04\00\ff\02\03\00\03\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06"
  "\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52"
  "\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5"
  "\52\03\55\04\ff\ff\f2\03\ff\08\aa\ff\02\07\00\ff\52\06\55\fe\d5\52\06\55"
  "\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06"
  "\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52\06\55\fe\d5\52"
  "\06\55\fe\d5\52\06\55\fe\d5\f2\07\ff"

  ;; floor and ceiling texture 2bpp RLE compressed
  "\fe\00\56\05\55\fd\02\80\56\05\55\fe\0a\a0\06\55\fe\29\68\06\55\fe\a5\5a"
  "\06\55\ff\95\3b\55\fe\95\5a\06\55\fe\a5\68\06\55\fe\29\a0\06\55\fd\0a\80"
  "\56\05\55\fd\02\00\56\05\55\fd\0a\80\56\05\55\fe\29\a0\06\55\fe\a5\68\06"
  "\55\fe\95\5a\3b\55\ff\5a\06\55\fe\95\68\06\55\fe\a5\a0\06\55\fd\29\80\56"
  "\05\55\ff\0a"

  ;; 0xd90
  ;; left-right brick palette
  "\00\04\08\0c"
  ;; top-bottom brick palette
  "\10\14\18\1c"
  ;; ceiling palette
  "\20\20\24\24"
  ;; floor palette
  "\28\2c\2c\2c"
  ;; goal palette
  "\30\34\38\3c"
  ;; left-right spot palette
  "\04\00\08\0c"
  ;; top-bottom spot palette
  "\14\10\18\1c"

  ;; 0xdac
  ;; bottom wall
  "\00\00\18\00"  ;; (0,0),(24,0)
  "\18\00\00\00"  ;; scale:24, tex:0, pal:0
  ;; right wall (minus goal)
  "\18\00\00\16"  ;; (24,0),(0,22)
  "\16\00\04\00"  ;; scale:22, tex:0, pal:1<<2
  ;; right goal
  "\18\16\00\02"  ;; (24,22),(0,2)
  "\02\00\10\00"  ;; scale:2, tex:0, pal:4<<2
  ;; top goal
  "\18\18\fe\00"  ;; (24,24),(-2,0)
  "\02\00\10\00"  ;; scale:2, tex:0, pal:4<<2
  ;; top wall (minus goal)
  "\16\18\ea\00"  ;; (22,24),(-22,0)
  "\16\00\00\00"  ;; scale:22, tex:0, pal:0
  ;; left wall
  "\00\18\00\e8"  ;; (0,24),(0,-24)
  "\18\00\04\00"  ;; scale:24, tex:0, pal:1<<2
)

(data (i32.const 0x11b0)
  ;; brightest versions of all 16 colors
  "\f3\5f\5f\ff\9f\25\25\ff\51\0a\0a\ff\79\0e\0e\ff"
  "\c2\4c\4c\ff\7f\1d\1d\ff\51\0a\0a\ff\60\0b\0b\ff"
  "\cb\c8\b8\ff\9b\97\81\ff\81\95\af\ff\b5\b5\b5\ff"
  "\10\ff\10\ff\10\ef\10\ff\10\df\10\ff\10\cf\10\ff")

;; Shoot a ray against all walls in the scene, and return the minimum distance
;; (or inf if no wall was hit).
;; This function also sets $min-t2 and $min-wall.
(func $ray-walls (result f32)
  (local $wall i32)
  (local $min-t1 f32)

  (local $v1x f32)
  (local $v1y f32)
  (local $v2x f32)
  (local $v2y f32)
  (local $v2-dot-ray-perp f32)
  (local $t1 f32)
  (local $t2 f32)

  (local.set $min-t1 (f32.const inf))
  (local.set $wall (i32.const 0x0dac))
  (loop $wall-loop
    ;; Ray/line segment intersection.
    ;; see https://rootllama.wordpress.com/2014/06/20/ray-line-segment-intersection-test-in-2d/
    (if
      (i32.and (i32.and (i32.and
        ;; $t2 must be between [0, 1].
        (f32.ge
          ;; $t2 = intersection "time" between s and e.
          ;;     = dot($v1, perp(ray)) / dot($v2, perp(ray))
          (local.tee $t2
            (f32.div
              (f32.add
                (f32.mul
                  ;; $v1 = P - wall.P
                  (local.tee $v1x
                    (f32.sub
                      (global.get $Px)
                      (f32.convert_i32_s (i32.load8_s (local.get $wall)))))
                  (f32.neg (global.get $ray-y)))
                (f32.mul
                  (local.tee $v1y
                    (f32.sub
                      (global.get $Py)
                      (f32.convert_i32_s (i32.load8_s offset=1 (local.get $wall)))))
                  (global.get $ray-x)))
              ;; $v2 = wall.dP
              ;; $v2-dot-ray-perp = dot($v2, perp(ray))
              (local.tee $v2-dot-ray-perp
                (f32.add
                  (f32.mul
                    (local.tee $v2x
                      (f32.convert_i32_s (i32.load8_s offset=2 (local.get $wall))))
                    (f32.neg (global.get $ray-y)))
                  (f32.mul
                    (local.tee $v2y
                      (f32.convert_i32_s (i32.load8_s offset=3 (local.get $wall))))
                    (global.get $ray-x))))))
          (global.get $zero))
        (f32.le (local.get $t2) (global.get $one)))
        ;; $t1 is distance along ray, which must be >= 0.
        (f32.ge
          (local.tee $t1
            (f32.div
              (f32.sub
                (f32.mul (local.get $v2x) (local.get $v1y))
                (f32.mul (local.get $v1x) (local.get $v2y)))
              (local.get $v2-dot-ray-perp)))
          (global.get $zero)))
        ;; If the ray was a closer hit, update the min values.
        (f32.lt (local.get $t1) (local.get $min-t1)))
      (then
        (local.set $min-t1 (local.get $t1))
        ;; Scale t2 by the wall's scale value.
        (global.set $min-t2
          (f32.mul
            (local.get $t2)
            (f32.convert_i32_u
              (i32.load8_u offset=4 (local.get $wall)))))
        (global.set $min-wall (local.get $wall))))

    (br_if $wall-loop
      (i32.lt_s
        (local.tee $wall (i32.add (local.get $wall) (i32.const 8)))
        (global.get $max-wall-addr))))

  (local.get $min-t1))

;; Takes an f32, doubles it, then take the fractional part of that and scales
;; it to [0, 32). Used to index into a 32x32 texture.
(func $scale-frac-i32 (param $x f32) (result f32)
  (f32.mul
    (f32.sub
      (local.tee $x (f32.add (local.get $x) (local.get $x)))
      (f32.floor (local.get $x)))
    (f32.convert_i32_s (i32.const 32))))

;; Returns a color from a 32x32 8bpp texture, using a two-level palette.
;; The texture contains a palette index [0, 4).
;; Each palette entry has a color index [0, 16).
;; The color index can be combined with a distance value [0, 120) to get the
;; actual 32-bit color.
(func $texture
      (param $tex i32) (param $pal-addr i32) (param $dist i32)
      (param $u f32) (param $v f32)
      (result i32)
  ;; Read color from color-distance table.
  (i32.load offset=0x11b0
    (i32.add
      (i32.shl (local.get $dist) (i32.const 6))
      ;; Read palette entry from palette.
      (i32.load8_u offset=0x0d90
        (i32.add
          (local.get $pal-addr)
          ;; Read from 32x32 texture.
          (i32.load8_u offset=0x02b0
            (i32.add
              (i32.shl (local.get $tex) (i32.const 10))
              (i32.add
                ;; wrap v coordinate to [0, 32), then multiply by 32.
                (i32.shl
                  (i32.trunc_f32_s (call $scale-frac-i32 (local.get $v)))
                  (i32.const 5))
                ;; wrap u coordinate to [0, 32).
                (i32.trunc_f32_s (call $scale-frac-i32 (local.get $u)))))))))))

;; Changes the rotation speed or movement speed fluidly given an input value.
;;   $input-addr: Address of 2 bytes of input (either left/right or up/down)
;;   $value-addr: The value to modify (either rotation or movement speed)
;; Returns the new value.
(func $move (param $input-addr i32) (param $value-addr i32) (result f32)
  (local $result f32)
  (f32.store (local.get $value-addr)
    (local.tee $result
      (f32.mul
        (f32.add
          (f32.load (local.get $value-addr))
          (f32.mul
            (f32.convert_i32_s
              (i32.sub
                (i32.load8_u (local.get $input-addr))
                (i32.load8_u offset=1 (local.get $input-addr))))
            (f32.const 0.0078125)))
        (f32.const 0.875))))
  (local.get $result))

(func (export "run")
  (local $color i32)

  (local $src i32)
  (local $dst i32)
  (local $count i32)
  (local $d-src i32)
  (local $byte i32)

  (local $cells i32)
  (local $i i32)
  (local $cell0 i32)
  (local $cell1 i32)
  (local $wall-addr i32)
  (local $dest-wall-addr i32)
  (local $walls i32)

  (local $x i32)
  (local $y i32)
  (local $1280y i32)

  (local $x-mid-addr i32)
  (local $top-tex i32)
  (local $top-pal i32)
  (local $bot-tex i32)
  (local $bot-pal i32)

  (local $ihalf-height i32)
  (local $dist-index i32)

  (local $factor f32)

  (local $xproj f32)
  (local $Dx f32)
  (local $Dy f32)
  (local $dist f32)
  (local $speed f32)

  (local $normal-x f32)
  (local $normal-y f32)
  (local $wall-scale f32)
  (local $dot-product f32)

  (local $half-height f32)

  (local $u f32)
  (local $top-v f32)
  (local $bot-v f32)
  (local $dv f32)
  (local $ydv f32)

  ;; Set both $ray-x/$Dx and $ray-y $Dy.
  ;; $Dx/$Dy is used for the view direction, and $ray-x/$ray-y is used for
  ;; the movement vector.
  (global.set $ray-x
    (local.tee $Dx
      (call $sin (global.get $angle))))
  (global.set $ray-y
    (local.tee $Dy
      (call $sin (f32.add (global.get $angle) (f32.const 1.5707963267948966)))))

  ;; Always decrement the mode timer.
  (global.set $mode-timer (i32.sub (global.get $mode-timer) (i32.const 1)))

  (block $done
    (block $winning
      (block $game
        (block $reset
          (block $wait
            (block $init
              (br_table $init $wait $reset $game $winning (global.get $mode)))

            ;; MODE: $init
            (loop $loop
              ;; initialize distance table:
              ;;   120 / (y + 1) for y in [0, 120)
              (f32.store offset=0x0ab0
                (i32.shl (local.get $y) (i32.const 2))
                (local.tee $factor
                  (f32.div
                    (global.get $half-screen-height)
                    (f32.add
                      (f32.convert_i32_s (local.get $y))
                      (global.get $one)))))

              ;; Make the brightness falloff more slowly.
              (local.set $factor (f32.sqrt (local.get $factor)))

              ;; Initialize the palette tables with darker versions of all 16
              ;; colors, for each of the 120 distance values.
              (loop $color-loop
                ;; Skip the original 64 colors when writing.
                (i32.store8 offset=0x11f0  ;; 0x11b0 + 0x40
                  (local.get $color)
                  ;; Set $channel to 0xff by default (for alpha). Only adjust
                  ;; brightness for RGB channels.
                  (select
                    ;; non-alpha channel
                    (i32.trunc_f32_s
                      (f32.div
                        (f32.convert_i32_s
                          ;; Mask off the low 6 bits to get the original color.
                          (i32.load8_u offset=0x11b0
                            (i32.and (local.get $color) (i32.const 63))))
                        (local.get $factor)))
                    ;; alpha channel
                    (i32.const 0xff)
                    (i32.ne (i32.and (local.get $color) (i32.const 3)) (i32.const 3))))

                (br_if $color-loop
                  (i32.and
                    (local.tee $color (i32.add (local.get $color) (i32.const 1)))
                    (i32.const 63))))

              (br_if $loop
                (i32.lt_s
                  (local.tee $y (i32.add (local.get $y) (i32.const 1)))
                  (i32.const 120))))

            ;; Decompress RLE-encoded 2bpp textures
            ;; RLE is encoded as:
            ;;  v**n        => (+n, v)
            ;;  v1,v2,..,vn => (-n, v1, v2,..,vn)
            ;;
            ;; Where each cell is one byte.
            (local.set $dst (i32.const 0x02ac))  ;; 0x02b0 - 4
            (loop $src-loop
              (if (local.tee $d-src
                    (i32.le_s
                      (local.tee $count (i32.load8_s offset=0x0c90 (local.get $src)))
                      (i32.const 0)))
                (then
                  ;; -$count singleton elements.
                  (local.set $count (i32.sub (i32.const 0) (local.get $count))))
                (else
                  ;; Run of length $count.
                  (local.set $src (i32.add (local.get $src) (i32.const 1)))))

              ;; Write the run.
              (loop $dst-loop
                ;; Each byte is 2bpp, unpack into 8bpp palette index.
                (i32.store
                  (local.tee $dst (i32.add (local.get $dst) (i32.const 4)))
                  (i32.and
                    (i32.or
                      (i32.or
                        (i32.or
                          (local.tee $byte
                            (i32.load8_u offset=0x0c90
                              (local.tee $src
                                (i32.add (local.get $src) (local.get $d-src)))))
                          (i32.shl (local.get $byte) (i32.const 6)))
                        (i32.shl (local.get $byte) (i32.const 12)))
                      (i32.shl (local.get $byte) (i32.const 18)))
                    (i32.const 0x03030303)))

                (br_if $dst-loop
                  (local.tee $count (i32.sub (local.get $count) (i32.const 1)))))

              (br_if $src-loop
                (i32.lt_s
                  (local.tee $src (i32.add (local.get $src) (i32.const 1)))
                  (i32.const 0x100))))
              (global.set $mode (i32.const 1)) ;; wait
              (br $done))

          ;; MODE: $wait
          (if (i32.eqz (global.get $mode-timer))
            (then
              (global.set $mode (i32.const 4)) ;; winning
              (global.set $mode-timer (i32.const 120)))) ;; reset position over time
          (br $done))

        ;; MODE: $reset
        ;; clear rotation and movement speed
        (i64.store align=4 (i32.const 0x0004) (i64.const 0))
        ;; Generate maze using Kruskal's algorithm.
        ;; See http://weblog.jamisbuck.org/2011/1/3/maze-generation-kruskal-s-algorithm

        ;; Pack the following values: (i, i + 1, i, i + 12)
        ;; This allows us to use i32.store16 below to write a horizontal or
        ;; vertical wall.
        (local.set $cells (i32.const 0x0c_00_01_00))

        ;; start at 0x00a0 - 2 and pre-increment before storing
        (local.set $wall-addr (i32.const 0x009e))
        (loop $loop
          ;; Each cell is "owned" by itself at the start.
          (i32.store8 offset=0x0010
            (i32.and (local.get $cells) (i32.const 0xff)) (local.get $cells))

          ;; Add horizontal edge, connecting cell i and i + 1.
          (if (i32.lt_s (i32.rem_s (local.get $i) (i32.const 12)) (i32.const 11))
            (then
              (i32.store16
                (local.tee $wall-addr (i32.add (local.get $wall-addr) (i32.const 2)))
                (local.get $cells))))

          ;; add vertical edge, connecting cell i and i + 12.
          (if (i32.lt_s (i32.div_s (local.get $i) (i32.const 12)) (i32.const 11))
            (then
              (i32.store16
                (local.tee $wall-addr (i32.add (local.get $wall-addr) (i32.const 2)))
                (i32.shr_u (local.get $cells) (i32.const 16)))))

          ;; increment cell indexes.
          (local.set $cells (i32.add (local.get $cells) (i32.const 0x01_01_01_01)))

        (br_if $loop
          (i32.lt_s
            (local.tee $i (i32.add (local.get $i) (i32.const 1)))
            (i32.const 144))))  ;; 12 * 12

        (local.set $walls (i32.const 264))  ;; 12 * 11 * 2

        (loop $wall-loop
          ;; if each side of the wall is not part of the same set:
          (if
            (i32.ne
              ;; $cell0 is the left/up cell.
              (local.tee $cell0
                (i32.load8_u offset=0x0010
                  (i32.load8_u offset=0x00a0
                    ;; randomly choose a wall
                    (local.tee $wall-addr
                      (i32.shl
                        (i32.trunc_f32_s
                          (f32.mul
                            (call $random)
                            (f32.convert_i32_s (local.get $walls))))
                        (i32.const 1))))))
              ;; $cell1 is the right/down cell
              (local.tee $cell1
                (i32.load8_u offset=0x0010
                  (i32.load8_u offset=0x00a1 (local.get $wall-addr)))))
            (then
              ;; remove this wall by copying the last wall over it.
              (i32.store16 offset=0x00a0
                (local.get $wall-addr)
                (i32.load16_u offset=0x00a0
                  (i32.shl
                    (local.tee $walls (i32.sub (local.get $walls) (i32.const 1)))
                    (i32.const 1))))

              ;; replace all cells that contain $cell1 with $cell0.
              ;; loop over range [0x0090,0x0000), so use an offset of 0xf so the
              ;; stored addresses are in the range (0x00a0,0x0010].
              (local.set $i (i32.const 0x0090))
              (loop $remove-loop
                (if (i32.eq
                      (i32.load8_u offset=0xf (local.get $i))
                      (local.get $cell1))
                  (then
                    (i32.store8 offset=0xf (local.get $i) (local.get $cell0))))

                (br_if $remove-loop
                  (local.tee $i (i32.sub (local.get $i) (i32.const 1)))))))

          ;; loop until there are exactly 11 * 11 walls.
          (br_if $wall-loop (i32.gt_s (local.get $walls) (i32.const 121))))

        ;; generate walls for use in-game.
        (local.set $wall-addr (i32.const 0x00a0))
        (local.set $dest-wall-addr (i32.const 0x0dd4))  ;; 0x0ddc - 8
        (loop $wall-loop
          ;; Store the x,y coordinate of the wall, given the cell index.
          ;; Multiply by 2 so each cell is 2x2 units.
          (i32.store16
            ;; Increment $dest-wall-addr early, so we can use local.tee instead of
            ;; local.set. To do allow this, we have to start at 0x0ddc - 8 (see
            ;; above).
            (local.tee $dest-wall-addr
              (i32.add (local.get $dest-wall-addr) (i32.const 8)))
            (i32.shl
              (i32.or
                (i32.shl
                  (i32.div_s
                    ;; Save the right/bottom cell of the wall as $i.
                    (local.tee $i (i32.load8_u offset=1 (local.get $wall-addr)))
                    (i32.const 12))
                  (i32.const 8))
                (i32.rem_s (local.get $i) (i32.const 12)))
              (i32.const 1)))

          (i64.store offset=2 align=2
            (local.get $dest-wall-addr)
            (select
              ;; left-right wall
              ;; Write dx=0, dy=2. We can use an unaligned write to combine this with
              ;; updating pal, tex, and scale too.
              ;; This ends up writing:
              ;;    \00  ;; dx
              ;;    \02  ;; dy
              ;;    \02\01\18\00  ;; scale:2, tex:1, pal:6<<2
              (i64.const 0x18_01_02_02_00)
              ;; top-bottom wall
              ;;    \02  ;; dx
              ;;    \00  ;; dy
              ;;    \02\01\14\00  ;; scale:2, tex:1, pal:5<<2
              (i64.const 0x14_01_02_00_02)
              ;; Get the two cells of the wall. If the difference is 1, it must be
              ;; left/right.
              (i32.eq
                (i32.sub (local.get $i) (i32.load8_u (local.get $wall-addr)))
                (i32.const 1))))

          (br_if $wall-loop
            (i32.lt_s
              (local.tee $wall-addr (i32.add (local.get $wall-addr) (i32.const 2)))
              (i32.const 0x0192))))   ;; 0x00a0 + 11 * 11 * 2
        (global.set $max-wall-addr (i32.const 0x11a4))
        (global.set $mode (i32.const 3)) ;; game
        (call $timer (i32.const 1)) ;; start timer
        (br $done))

      ;; MODE: $game
      ;; Rotate if left or right is pressed.
      (global.set $angle
        (f32.add
          (global.get $angle)
          (call $move (i32.const 0x0000) (i32.const 0x0004))))
      ;; angle = fmod(angle, 2 * pi)
      (global.set $angle
        (f32.sub
          (global.get $angle)
          (f32.mul
            (f32.trunc
              (f32.div
                (global.get $angle)
                (f32.const 6.283185307179586)))
            (f32.const 6.283185307179586))))

      ;; Move forward if up is pressed.
      ;; If the speed is negative, flip the movement vector
      (if (f32.lt
            (local.tee $speed (call $move (i32.const 0x0002) (i32.const 0x0008)))
            (global.get $zero))
        (then
          (local.set $speed (f32.neg (local.get $speed)))
          (global.set $ray-x (f32.neg (global.get $ray-x)))
          (global.set $ray-y (f32.neg (global.get $ray-y)))))

      ;; Move if the speed is non-zero.
      (if (f32.gt (local.get $speed) (global.get $zero))
        (then
          ;; Try to move, but stop at the nearest wall.
          ;; Afterward, $dist is the distance to the wall.
          (global.set $Px
            (f32.add
              (global.get $Px)
              (f32.mul
                (global.get $ray-x)
                (local.tee $dist
                  (f32.min
                    ;; Epsilon to prevent landing on the wall.
                    (f32.add (call $ray-walls) (f32.const 0.001953125))
                    (local.get $speed))))))
          (global.set $Py
            (f32.add
              (global.get $Py)
              (f32.mul (global.get $ray-y) (local.get $dist))))

          ;; Store the dot product of the normal and the vector to P, to see if
          ;; the normal is pointing in the right direction.
          (local.set $dot-product
            (f32.add
              (f32.mul
                ;; Store the normal of the nearest wall.
                ;; Wall is stored as (x,y),(dx,dy),scale.
                ;; Since we want the normal, store (-dy/scale, dx/scale).
                (local.tee $normal-x
                  (f32.neg
                    (f32.div
                      (f32.convert_i32_s
                        (i32.load8_s offset=3 (global.get $min-wall)))
                      (local.tee $wall-scale
                        (f32.convert_i32_u
                          (i32.load8_u offset=4 (global.get $min-wall)))))))
                (f32.sub
                  (global.get $Px)
                  (f32.convert_i32_s
                    (i32.load8_s (global.get $min-wall)))))
              (f32.mul
                (local.tee $normal-y
                  (f32.div
                    (f32.convert_i32_s
                      (i32.load8_s offset=2 (global.get $min-wall)))
                    (local.get $wall-scale)))
                (f32.sub
                  (global.get $Py)
                  (f32.convert_i32_s
                    (i32.load8_s offset=1 (global.get $min-wall)))))))

          ;; Push the player away from the wall if they're too close. Since the
          ;; $dot-product is signed, we need to use the absolute value to find
          ;; the actual distance.
          (if (f32.gt
                (local.tee $dist
                  (f32.sub (f32.const 0.25) (f32.abs (local.get $dot-product))))
                (global.get $zero))
            (then
              (global.set $Px
                (f32.add
                  (global.get $Px)
                  (f32.mul
                    (local.get $normal-x)
                    (local.tee $dist
                      ;; Use the sign of the $dot-product on the positive value
                      ;; $dist to push in the proper direction.
                      (f32.copysign (local.get $dist) (local.get $dot-product))))))
              (global.set $Py
                (f32.add
                  (global.get $Py)
                  (f32.mul (local.get $normal-y) (local.get $dist))))))))

      ;; If the player reaches the goal, generate a new maze, and reset their
      ;; position.
      (if (i32.and
            (f32.gt (global.get $Px) (f32.convert_i32_s (i32.const 22)))
            (f32.gt (global.get $Py) (f32.convert_i32_s (i32.const 22))))
        (then
          (call $timer (i32.const 0)) ;; stop timer
          (global.set $mode (i32.const 4)) ;; winning
          (global.set $mode-timer (i32.const 120)) ;; reset position over time
          (global.set $max-wall-addr (i32.const 0x0ddc))))

      (br $done))

    ;; MODE: $winning
    ;; Move the player back to the beginning.
    (global.set $Px
      (f32.add
        (global.get $one-half)
        (f32.mul
          (f32.sub (global.get $Px) (global.get $one-half))
          (local.tee $dist
            (f32.div
              (f32.convert_i32_s (global.get $mode-timer))
              (global.get $half-screen-height))))))
    (global.set $Py
      (f32.add
        (global.get $one-half)
        (f32.mul
          (f32.sub (global.get $Py) (global.get $one-half)) (local.get $dist))))
    (global.set $angle
      (f32.add
        (f32.const 0.7853981633974483)
        (f32.mul
          (f32.sub (global.get $angle) (f32.const 0.7853981633974483))
          (local.get $dist))))

    (if (i32.eqz (global.get $mode-timer))
      (then
        (global.set $mode (i32.const 2)) ;; reset
        (global.set $mode-timer (i32.const 15))))) ;; shorter wait

  ;; DRAWING:
  ;; Loop for each column.
  (loop $x-loop
    ;; Shoot a ray against a wall. Use rays projected onto screen plane.
    (global.set $ray-x
      (f32.add
        (local.get $Dx)
        (f32.mul
          (local.tee $xproj
            (f32.div
              (f32.convert_i32_s (i32.sub (local.get $x) (i32.const 160)))
              (f32.convert_i32_s (i32.const 160))))
          (f32.neg (local.get $Dy)))))
    (global.set $ray-y
      (f32.add (local.get $Dy) (f32.mul (local.get $xproj) (local.get $Dx))))

    ;; Draw a vertical strip of the scene, including ceiling, wall, and floor.

    ;; Fire the ray, and find the closest wall that is hit. Divide the
    ;; half-screen-height (120 pixels) by this distance to produce the
    ;; half-height for this wall, but clamp it so 120 we don't access
    ;; out-of-bounds.
    (if (i32.ge_s
          (local.tee $ihalf-height
            (i32.trunc_f32_s
              (local.tee $half-height
                (f32.div (global.get $half-screen-height) (call $ray-walls)))))
          (i32.const 120))
      (then
        (local.set $ihalf-height (i32.const 120))))

    ;; $x-mid-addr is address of the pixel at (x, 219).
    (local.set $x-mid-addr
      (i32.add (i32.const 0x28300) (i32.shl (local.get $x) (i32.const 2))))
    ;; Set the initial values for drawing a wall. These will be changed when
    ;; drawing the floor/ceiling.
    (local.set $dist-index (local.get $ihalf-height))
    (local.set $u (global.get $min-t2))
    (local.set $dv (f32.div (global.get $one-half) (local.get $half-height)))
    (local.set $bot-tex
      (local.tee $top-tex (i32.load8_u offset=5 (global.get $min-wall))))
    (local.set $bot-pal
      (local.tee $top-pal (i32.load8_u offset=6 (global.get $min-wall))))

    ;; Loop over all pixels in this column.
    (local.set $y (i32.const 0))
    (loop $y-loop
      (if (i32.lt_s (local.get $y) (local.get $ihalf-height))
        (then
          ;; Draw wall.
          ;; Start at the center of the texture and move up for $top-v and
          ;; down for $bot-v.
          (local.set $top-v
            (f32.sub
              (global.get $one-half)
              (local.tee $ydv
                (f32.mul (f32.convert_i32_s (local.get $y)) (local.get $dv)))))
          (local.set $bot-v
            (f32.add (global.get $one-half) (local.get $ydv))))
        (else
          ;; Drawing ceiling/floor
          ;; Find UV using distance table
          (local.set $u
            (f32.add
              (global.get $Px)
              (f32.mul
                (global.get $ray-x)
                (local.tee $dist
                  (f32.load offset=0x0ab0 (i32.shl (local.get $y) (i32.const 2)))))))
          (local.set $bot-v
            (local.tee $top-v
              (f32.add
                (global.get $Py)
                (f32.mul (global.get $ray-y) (local.get $dist)))))
          (local.set $dist-index (local.get $y))
          (local.set $top-tex (i32.const 0))
          (local.set $top-pal (i32.const 0x8))
          (local.set $bot-tex (i32.const 1))
          (local.set $bot-pal (i32.const 0xc))))

      ;; Draw ceiling or wall top.
      (i32.store
        (i32.sub
          (local.get $x-mid-addr)
          (local.tee $1280y (i32.mul (local.get $y) (i32.const 1280))))
        (call $texture
          (local.get $top-tex) (local.get $top-pal) (local.get $dist-index)
          (local.get $u) (local.get $top-v)))

      ;; Draw floor or wall bottom.
      (i32.store offset=1280
        (i32.add (local.get $x-mid-addr) (local.get $1280y))
        (call $texture
          (local.get $bot-tex) (local.get $bot-pal) (local.get $dist-index)
          (local.get $u) (local.get $bot-v)))

      (br_if $y-loop
        (i32.lt_s
          (local.tee $y (i32.add (local.get $y) (i32.const 1)))
          (i32.const 120))))

    ;; loop on x
    (br_if $x-loop
      (i32.lt_s
        (local.tee $x (i32.add (local.get $x) (i32.const 1)))
        (i32.const 320)))))
