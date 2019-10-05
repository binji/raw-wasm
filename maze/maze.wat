(import "Math" "random" (func $random (result f32)))
(import "Math" "sin" (func $sin (param f32) (result f32)))

(global $mode (mut i32) (i32.const 3))
(global $mode-timer (mut i32) (i32.const 120))
(global $max-wall-addr (mut i32) (i32.const 0x1078))

;; Position and direction vectors. Direction is updated from angle, which is
;; expressed in radians.
(global $Px (mut f32) (f32.const 23))
(global $Py (mut f32) (f32.const 23))
(global $angle (mut f32) (f32.const 0.7853981633974483))

(global $min-t2 (mut f32) (f32.const 0))
(global $min-wall (mut i32) (i32.const 0))

;; Color: u32        ; ABGR
;; Cell2: u8*2       ; left/up cell, right/down cell
;; Wall: f32*4,u8*3  ; (x1,y1),(x2, y2), scale, texture, palette

;; [0x0000, 0x0100)   u8[12*12]       maze cells for Kruskal's algo
;; [0x0100, 0x0310)   Cell2[12*11*2]  walls for Kruskal's algo
;; [0x0400, 0x0500)   u8[32*32]       RLE compressed 2bpp textures
;; [0x0500, 0x0900)   u8[32*32]       8bpp brick texture
;; [0x0900, 0x0d00)   u8[32*32]       8bpp spot texture
;; [0x0d00, 0x0d2c)   Color[4+4+4]    palettes
;; [0x0df0, 0x0df4)   f32             rotation speed
;; [0x0df4, 0x0df8)   f32             speed
;; [0x0dfc, 0x0e00)   u8[4]           left/right/forward/back keys
;; [0x0e00, 0x0fe0)   f32[120]        Table of 120/(120-y)
;; [0x1000, 0x19ec)   Wall[6+11*11]   walls used in-game
;; [0x3000, 0x4e000)  Color[320*240]  canvas
(memory (export "mem") 6)

(data (i32.const 0x1000)
  ;; bottom wall
  "\00\00\00\00"  ;; 0.0
  "\00\00\00\00"  ;; 0.0
  "\00\00\c0\41"  ;; 24.0
  "\00\00\00\00"  ;; 0.0
  "\18\00\00\00"  ;; scale=24
  ;; right wall (minus goal)
  "\00\00\c0\41"  ;; 24.0
  "\00\00\00\00"  ;; 0.0
  "\00\00\c0\41"  ;; 24.0
  "\00\00\b0\41"  ;; 22.0
  "\16\00\01\00"  ;; scale=22
  ;; right goal
  "\00\00\c0\41"  ;; 24.0
  "\00\00\b0\41"  ;; 22.0
  "\00\00\c0\41"  ;; 24.0
  "\00\00\c0\41"  ;; 24.0
  "\02\00\04\00"  ;; scale=2
  ;; top goal
  "\00\00\c0\41"  ;; 24.0
  "\00\00\c0\41"  ;; 24.0
  "\00\00\b0\41"  ;; 22.0
  "\00\00\c0\41"  ;; 24.0
  "\02\00\04\00"  ;; scale=2
  ;; top wall (minus goal)
  "\00\00\b0\41"  ;; 22.0
  "\00\00\c0\41"  ;; 24.0
  "\00\00\00\00"  ;;  0.0
  "\00\00\c0\41"  ;; 24.0
  "\16\00\00\00"  ;; scale=22
  ;; left wall
  "\00\00\00\00"  ;; 0.0
  "\00\00\c0\41"  ;; 24.0
  "\00\00\00\00"  ;; 0.0
  "\00\00\00\00"  ;; 0.0
  "\18\00\01\00"  ;; scale=24
)

(data (i32.const 0x400)
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
)

;; palette
(data (i32.const 0xd00)
  ;; 0xd00: left-right brick palette
  "\f3\5f\5f\ff\9f\25\25\ff\00\00\00\ff\79\0e\0e\ff"
  ;; 0xd10: top-bottom brick palette
  "\c2\4c\4c\ff\7f\1d\1d\ff\00\00\00\ff\60\0b\0b\ff"
  ;; 0xd20: ceiling palette
  "\62\8d\c6\ff\81\95\af\ff\62\8d\c6\ff\00\00\00\ff"
  ;; 0xd30: floor palette
  "\81\95\af\ff\b5\b5\b5\ff\b5\b5\b5\ff\00\00\00\ff"
  ;; 0xd40: goal palette
  "\10\df\10\ff\10\df\10\ff\10\df\10\ff\10\df\10\ff"
)

(start $init)
(func $init
  ;; initialize distance table:
  ;;   120 / (120 - y) for y in [0, 120)
  (local $y i32)
  (loop $loop
    (f32.store offset=0xe00
      (i32.shl (local.get $y) (i32.const 2))
      (f32.div
        (f32.const 120)
        (f32.sub (f32.const 120) (f32.convert_i32_s (local.get $y)))))

    (br_if $loop
      (i32.lt_s
        (local.tee $y (i32.add (local.get $y) (i32.const 1)))
        (i32.const 120))))

  (call $decompress-textures)
)

;; Generate maze using Kruskal's algorithm.
;; See http://weblog.jamisbuck.org/2011/1/3/maze-generation-kruskal-s-algorithm
(func $gen-maze
  (local $i i32)
  (local $x i32)
  (local $y i32)
  (local $wall-addr i32)
  (local $dest-wall-addr i32)
  (local $walls i32)
  (local $fx f32)
  (local $fy f32)

  (local.set $wall-addr (i32.const 0x100))
  (loop $y-loop

    (local.set $x (i32.const 0))
    (loop $x-loop
      ;; Each cell is "owned" by itself at the start.
      (i32.store8 (local.get $i) (local.get $i))

      ;; Add horizontal edge, connecting cell i and i + 1.
      (if (i32.lt_s (local.get $x) (i32.const 11))
        (then
          (i32.store8 (local.get $wall-addr) (local.get $i))
          (i32.store8 offset=1 (local.get $wall-addr) (i32.add (local.get $i) (i32.const 1)))
          (local.set $wall-addr (i32.add (local.get $wall-addr) (i32.const 2)))))

      ;; add vertical edge, connecting cell i and i + 12.
      (if (i32.lt_s (local.get $y) (i32.const 11))
        (then
          (i32.store8 (local.get $wall-addr) (local.get $i))
          (i32.store8 offset=1 (local.get $wall-addr) (i32.add (local.get $i) (i32.const 12)))
          (local.set $wall-addr (i32.add (local.get $wall-addr) (i32.const 2)))))

      ;; increment cell index.
      (local.set $i (i32.add (local.get $i) (i32.const 1)))

      (br_if $x-loop
        (i32.lt_s
          (local.tee $x (i32.add (local.get $x) (i32.const 1)))
          (i32.const 12))))

    (br_if $y-loop
      (i32.lt_s
        (local.tee $y (i32.add (local.get $y) (i32.const 1)))
        (i32.const 12))))

  (local.set $walls (i32.const 264))  ;; 12 * 11 * 2

  ;; randomly choose a wall
  (loop $wall-loop
    (local.set $wall-addr
      (i32.add
        (i32.const 0x100)
        (i32.shl
          (i32.trunc_f32_s
            (f32.mul (call $random) (f32.convert_i32_s (local.get $walls))))
          (i32.const 1))))

    ;; repurpose $x as the left/up cell, and $y as the right/down cell of the
    ;; wall.
    (local.set $x (i32.load8_u (i32.load8_u (local.get $wall-addr))))
    (local.set $y (i32.load8_u (i32.load8_u offset=1 (local.get $wall-addr))))

    ;; if each side of the wall is not part of the same set:
    (if (i32.ne (local.get $x) (local.get $y))
      (then
        ;; remove this wall by copying the last wall over it.
        (local.set $walls (i32.sub (local.get $walls) (i32.const 1)))
        (i32.store16
          (local.get $wall-addr)
          (i32.load16_u offset=0x100
            (i32.shl (local.get $walls) (i32.const 1))))

        ;; replace all cells that contain $y with $x.
        (local.set $i (i32.const 0))
        (loop $remove-loop
          (if (i32.eq (i32.load8_u (local.get $i)) (local.get $y))
            (then (i32.store8 (local.get $i) (local.get $x))))

          (br_if $remove-loop
            (i32.lt_s
              (local.tee $i (i32.add (local.get $i) (i32.const 1)))
              (i32.const 144))))
        ))

    ;; loop until there are exactly 11 * 11 walls.
    (br_if $wall-loop (i32.gt_s (local.get $walls) (i32.const 121))))

  ;; generate walls for use in-game.
  (local.set $wall-addr (i32.const 0x100))
  (local.set $dest-wall-addr (i32.const 0x1078))
  (loop $wall-loop
    ;; Save the right/bottom cell of the wall as $i.
    (local.set $i (i32.load8_u offset=1 (local.get $wall-addr)))

    ;; Get the x,y coordinate of the wall from the cell index.
    ;; Multiply by 2 so each cell is 2x2 units.
    (local.set $fx
      (f32.convert_i32_s
        (i32.shl (i32.rem_s (local.get $i) (i32.const 12)) (i32.const 1))))
    (local.set $fy
      (f32.convert_i32_s
        (i32.shl (i32.div_s (local.get $i) (i32.const 12)) (i32.const 1))))

    (f32.store (local.get $dest-wall-addr) (local.get $fx))
    (f32.store offset=4 (local.get $dest-wall-addr) (local.get $fy))
    ;; pal | tex | scale
    (i32.store offset=16 (local.get $dest-wall-addr) (i32.const 0x00_01_02))

    ;; Get the two cells of the wall. If the difference is 1, it must be
    ;; left/right.
    (if (i32.eq
          (i32.sub (local.get $i) (i32.load8_u (local.get $wall-addr)))
          (i32.const 1))
      ;; left-right wall
      (then
        (i32.store8 offset=18 (local.get $dest-wall-addr) (i32.const 1))  ;; pal
        (local.set $fy (f32.add (local.get $fy) (f32.const 2))))
      ;; top-bottom wall
      (else
        (local.set $fx (f32.add (local.get $fx) (f32.const 2)))))

    (f32.store offset=8 (local.get $dest-wall-addr) (local.get $fx))
    (f32.store offset=12 (local.get $dest-wall-addr) (local.get $fy))

    (local.set $dest-wall-addr
      (i32.add (local.get $dest-wall-addr) (i32.const 20)))

    (br_if $wall-loop
      (i32.lt_s
        (local.tee $wall-addr (i32.add (local.get $wall-addr) (i32.const 2)))
        (i32.const 0x1f2)))))   ;; 0x100 + 11 * 11 * 2

(func $decompress-textures
  (local $src i32)
  (local $dst i32)
  (local $count i32)
  (local $d-src i32)
  (local $byte i32)

  (local.set $src (i32.const 0x400))
  (local.set $dst (i32.const 0x500))
  (loop $src-loop
    (local.set $count (i32.load8_s (local.get $src)))

    (if (i32.gt_s (local.get $count) (i32.const 0))
      (then
        ;; Run of length $count.
        (local.set $src (i32.add (local.get $src) (i32.const 1)))
        (local.set $d-src (i32.const 0)))
      (else
        ;; -$count singleton elements.
        (local.set $count (i32.sub (i32.const 0) (local.get $count)))
        (local.set $d-src (i32.const 1))))

    ;; Write the run.
    (loop $dst-loop
      (local.set $src (i32.add (local.get $src) (local.get $d-src)))
      (local.set $byte (i32.load8_u (local.get $src)))

      ;; Each byte is 2bpp, unpack into 8bpp palette index.
      (i32.store8
        (local.get $dst)
        (i32.and (i32.shl (local.get $byte) (i32.const 2)) (i32.const 0xc)))
      (i32.store8 offset=1
        (local.get $dst)
        (i32.and (local.get $byte) (i32.const 0xc)))
      (i32.store8 offset=2
        (local.get $dst)
        (i32.and (i32.shr_u (local.get $byte) (i32.const 2)) (i32.const 0xc)))
      (i32.store8 offset=3
        (local.get $dst)
        (i32.and (i32.shr_u (local.get $byte) (i32.const 4)) (i32.const 0xc)))
      (local.set $dst (i32.add (local.get $dst) (i32.const 4)))

      (br_if $dst-loop
        (local.tee $count (i32.sub (local.get $count) (i32.const 1)))))

    (local.set $src (i32.add (local.get $src) (i32.const 1)))
    (br_if $src-loop
      (i32.lt_s (local.get $src) (i32.const 0x500)))))

(func $fmod (param $x f32) (param $y f32) (result f32)
  (f32.sub
    (local.get $x)
    (f32.mul
      (f32.trunc
        (f32.div
          (local.get $x)
          (local.get $y)))
      (local.get $y))))

;; Ray/line segment intersection. see https://rootllama.wordpress.com/2014/06/20/ray-line-segment-intersection-test-in-2d/
;;
;;   ray is defined by [Px,Py] -> [Dx,Dy].
;;   line segment is [sx,sy] -> [ex,ey].
;;
;;   Returns distance to the segment, or inf if it doesn't hit.
(func $ray-line
      (param $Dx f32) (param $Dy f32)
      (param $sx f32) (param $sy f32) (param $ex f32) (param $ey f32)
      (result f32)
  (local $v1x f32)
  (local $v1y f32)
  (local $v2x f32)
  (local $v2y f32)
  (local $v3x f32)
  (local $v3y f32)
  (local $inv-v2.v3 f32)
  (local $t1 f32)
  (local $t2 f32)

  ;; v1 = P - s
  (local.set $v1x (f32.sub (global.get $Px) (local.get $sx)))
  (local.set $v1y (f32.sub (global.get $Py) (local.get $sy)))

  ;; v2 = e - s
  (local.set $v2x (f32.sub (local.get $ex) (local.get $sx)))
  (local.set $v2y (f32.sub (local.get $ey) (local.get $sy)))

  ;; v3 = (-Dy, Dx)
  (local.set $v3x (f32.neg (local.get $Dy)))
  (local.set $v3y (local.get $Dx))

  (local.set $inv-v2.v3
    (f32.div
      (f32.const 1)
      (f32.add
        (f32.mul (local.get $v2x) (local.get $v3x))
        (f32.mul (local.get $v2y) (local.get $v3y)))))

  ;; t2 is intersection "time" between s and e.
  (local.set $t2
    (f32.mul
      (f32.add
        (f32.mul (local.get $v1x) (local.get $v3x))
        (f32.mul (local.get $v1y) (local.get $v3y)))
      (local.get $inv-v2.v3)))

  ;; t2 must be between [0, 1].
  (if
    (i32.and
      (f32.ge (local.get $t2) (f32.const 0))
      (f32.le (local.get $t2) (f32.const 1)))
    (then
      ;; t1 is distance along ray.
      (local.set $t1
        (f32.mul
          (f32.sub
            (f32.mul (local.get $v2x) (local.get $v1y))
            (f32.mul (local.get $v1x) (local.get $v2y)))
          (local.get $inv-v2.v3)))

      (if (f32.ge (local.get $t1) (f32.const 0))
        (then
          ;; return intersection time as global.
          (global.set $min-t2 (local.get $t2))
          (return (local.get $t1))))))

  (f32.const inf))

(func $ray-walls (param $ray-x f32) (param $ray-y f32) (result f32)
  (local $wall i32)
  (local $min-wall i32)
  (local $dist f32)
  (local $min-dist f32)
  (local $min-t2 f32)

  (local.set $min-dist (f32.const inf))
  (local.set $wall (i32.const 0x1000))
  (loop $wall-loop
    (local.set $dist
      (call $ray-line
        (local.get $ray-x)
        (local.get $ray-y)
        (f32.load (local.get $wall))
        (f32.load offset=4 (local.get $wall))
        (f32.load offset=8 (local.get $wall))
        (f32.load offset=12 (local.get $wall))))

    (if (f32.lt (local.get $dist) (local.get $min-dist))
      (then
        (local.set $min-dist (local.get $dist))
        (local.set $min-t2
          (f32.mul
            (global.get $min-t2)
            (f32.convert_i32_u
              (i32.load8_u offset=16 (local.get $wall)))))
        (local.set $min-wall (local.get $wall))))

    (br_if $wall-loop
      (i32.lt_s
        (local.tee $wall (i32.add (local.get $wall) (i32.const 20)))
        (global.get $max-wall-addr))))

  (global.set $min-t2 (local.get $min-t2))
  (global.set $min-wall (local.get $min-wall))
  (local.get $min-dist))

(func $scale-frac-i32 (param $x f32) (result i32)
  (local.set $x (f32.add (local.get $x) (local.get $x)))
  (i32.trunc_f32_s
    (f32.mul
      (f32.sub (local.get $x) (f32.floor (local.get $x)))
      (f32.const 32))))

;; Returns a color from a 32x32 8bpp texture, using a palette.
(func $texture
      (param $tex-addr i32) (param $pal-addr i32)
      (param $u f32) (param $v f32)
      (result i32)
  (i32.load offset=0xd00
    (i32.add
      (local.get $pal-addr)
      ;; Read from 32x32 texture.
      (i32.load8_u offset=0x500
        (i32.add
          (local.get $tex-addr)
          (i32.add
            ;; wrap v coordinate to [0, 32), then multiply by 32.
            (i32.shl (call $scale-frac-i32 (local.get $v)) (i32.const 5))
            ;; wrap u coordinate to [0, 32).
            (call $scale-frac-i32 (local.get $u))))))))

(func $draw-strip
      (param $top-addr i32) (param $height f32)
      (param $ray-x f32) (param $ray-y f32)
  (local $bot-addr i32)
  (local $dist-addr i32)
  (local $iheight i32)
  (local $wall-tex i32)
  (local $wall-pal i32)
  (local $dist f32)
  (local $u f32)
  (local $v f32)
  (local $dv f32)

  (local.set $bot-addr (i32.add (local.get $top-addr) (i32.const 307200)))
  (local.set $iheight
    (i32.trunc_f32_s
      (f32.ceil (f32.sub (f32.const 120) (local.get $height)))))

  ;; Draw floor + ceiling.
  (if (i32.gt_s (local.get $iheight) (i32.const 0))
    (then
      (loop $loop
        ;; update distance
        (local.set $dist (f32.load offset=0xe00 (local.get $dist-addr)))
        (local.set $dist-addr (i32.add (local.get $dist-addr) (i32.const 4)))

        ;; find UV using distance table
        (local.set $u
          (f32.add (global.get $Px) (f32.mul (local.get $ray-x) (local.get $dist))))
        (local.set $v
          (f32.add (global.get $Py) (f32.mul (local.get $ray-y) (local.get $dist))))

        ;; draw ceiling (increment after)
        (i32.store offset=0x3000
          (local.get $top-addr)
          (call $texture
            (i32.const 0) (i32.const 0x20)
            (local.get $u) (local.get $v)))
        (local.set $top-addr (i32.add (local.get $top-addr) (i32.const 1280)))

        ;; draw-floor (decrement before)
        (local.set $bot-addr (i32.sub (local.get $bot-addr) (i32.const 1280)))
        (i32.store offset=0x3000
          (local.get $bot-addr)
          (call $texture
            (i32.const 0x400) (i32.const 0x30)
            (local.get $u) (local.get $v)))

        (br_if $loop
          (local.tee $iheight (i32.sub (local.get $iheight) (i32.const 1)))))))

  ;; Draw wall.
  (local.set $u (global.get $min-t2))
  (local.set $dv (f32.div (f32.const 0.5) (local.get $height)))

  (local.set $v
    (f32.mul
      (f32.sub (local.get $height) (f32.trunc (local.get $height)))
      (local.get $dv)))

  (local.set $iheight
    (i32.shl
      (i32.trunc_f32_s (f32.ceil (local.get $height)))
      (i32.const 1)))

  ;; If the wall is taller than the screen, adjust the $v coordinate
  ;; accordingly.
  (if (i32.gt_s (local.get $iheight) (i32.const 240))
    (then
      (local.set $v
        (f32.add
          (local.get $v)
          (f32.mul
            (local.get $dv)
            (f32.sub (local.get $height) (f32.const 120)))))
      (local.set $iheight (i32.const 240))))

  (if (i32.gt_s (local.get $iheight) (i32.const 0))
    (then
      (local.set $wall-tex
        (i32.shl
          (i32.load8_u offset=17 (global.get $min-wall))
          (i32.const 10)))
      (local.set $wall-pal
        (i32.shl
          (i32.load8_u offset=18 (global.get $min-wall))
          (i32.const 4)))
      (loop $loop
        (i32.store offset=0x3000 (local.get $top-addr)
          (call $texture
            (local.get $wall-tex) (local.get $wall-pal)
            (local.get $u) (local.get $v)))
        (local.set $v (f32.add (local.get $v) (local.get $dv)))
        (local.set $top-addr (i32.add (local.get $top-addr) (i32.const 1280)))
        (br_if $loop
          (local.tee $iheight (i32.sub (local.get $iheight) (i32.const 1))))))))

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
  (local $x i32)
  (local $xproj f32)
  (local $Dx f32)
  (local $Dy f32)
  (local $dist f32)
  (local $speed f32)

  (local $move-x f32)
  (local $move-y f32)
  (local $ray-x f32)
  (local $ray-y f32)
  (local $wall-x f32)
  (local $wall-y f32)
  (local $normal-x f32)
  (local $normal-y f32)
  (local $wall-scale f32)
  (local $dot-product f32)

  ;; Set both $move-x/$Dx and $move-y $Dy.
  ;; $Dx/$Dy is used for the view direction, and $move-x/$move-y is used for
  ;; the movement vector.
  (local.set $move-x
    (local.tee $Dx
      (call $sin (global.get $angle))))
  (local.set $move-y
    (local.tee $Dy
      (call $sin (f32.add (global.get $angle) (f32.const 1.5707963267948966)))))

  ;; Always decrement the mode timer.
  (global.set $mode-timer (i32.sub (global.get $mode-timer) (i32.const 1)))

  (block $done
    (block $winning
      (block $game
        (block $intro-anim
          (block $init
            (br_table $init $intro-anim $game $winning (global.get $mode)))

          ;; MODE: $init
          (f32.store (i32.const 0xdf0) (f32.const 0)) ;; rotation speed
          (f32.store (i32.const 0xdf4) (f32.const 0)) ;; speed
          (call $gen-maze) ;; generate walls into 0x2000
          (global.set $mode (i32.const 1)) ;; intro-anim
          (br $done))

        ;; MODE: intro-anim
        (if (i32.eqz (global.get $mode-timer))
          (then
            (global.set $max-wall-addr (i32.const 0x19ec))
            (global.set $mode (i32.const 2)))) ;; game
        (br $done))

      ;; MODE: $game

      ;; Rotate if left or right is pressed.
      (global.set $angle
        (call $fmod
          (f32.add
            (global.get $angle)
            (call $move (i32.const 0xdfc) (i32.const 0xdf0)))
          (f32.const 6.283185307179586)))

      ;; Move forward if up is pressed.
      (local.set $speed (call $move (i32.const 0xdfe) (i32.const 0xdf4)))

      ;; If the speed is negative, flip the movement vector
      (if (f32.lt (local.get $speed) (f32.const 0))
        (then
          (local.set $speed (f32.neg (local.get $speed)))
          (local.set $move-x (f32.neg (local.get $move-x)))
          (local.set $move-y (f32.neg (local.get $move-y)))))

      ;; Move if the speed is non-zero.
      (if (f32.gt (local.get $speed) (f32.const 0))
        (then
          ;; Try to move, but stop at the nearest wall.
          ;; Afterward, $dist is the distance to the wall.
          (local.set $dist
            (f32.min
              (f32.add
                (call $ray-walls (local.get $move-x) (local.get $move-y))
                (f32.const 0.001953125))  ;; Epsilon to prevent landing on the wall.
              (local.get $speed)))  ;; Current speed.

          (global.set $Px
            (f32.add
              (global.get $Px)
              (f32.mul (local.get $move-x) (local.get $dist))))
          (global.set $Py
            (f32.add
              (global.get $Py)
              (f32.mul (local.get $move-y) (local.get $dist))))

          (local.set $wall-x (f32.load (global.get $min-wall)))
          (local.set $wall-y (f32.load offset=4 (global.get $min-wall)))
          (local.set $wall-scale
            (f32.convert_i32_u (i32.load8_u offset=16 (global.get $min-wall))))

          ;; Store the normal of the nearest wall.
          ;; Wall is stored as (x0,y0),(x1,y1),scale.
          ;; Since we want the normal, store (-(y0-y1), x0-x1).
          (local.set $normal-x
            (f32.neg
              (f32.div
                (f32.sub
                  (local.get $wall-y)
                  (f32.load offset=12 (global.get $min-wall)))
                (local.get $wall-scale))))
          (local.set $normal-y
            (f32.div
              (f32.sub
                (local.get $wall-x)
                (f32.load offset=8 (global.get $min-wall)))
              (local.get $wall-scale)))

          ;; Store the dot product of the normal and the vector to P, to see if
          ;; the normal is pointing in the right direction.
          (local.set $dot-product
            (f32.add
              (f32.mul
                (local.get $normal-x)
                (f32.sub (global.get $Px) (local.get $wall-x)))
              (f32.mul
                (local.get $normal-y)
                (f32.sub (global.get $Py) (local.get $wall-y)))))

          ;; If the normal is in the wrong direction (e.g. away from the player)
          ;; flip it.
          (if (f32.lt (local.get $dot-product) (f32.const 0))
            (then
              (local.set $dot-product (f32.neg (local.get $dot-product)))
              (local.set $normal-x (f32.neg (local.get $normal-x)))
              (local.set $normal-y (f32.neg (local.get $normal-y)))))

          ;; Push the player away from the wall if they're too close.
          (local.set $dot-product
            (f32.sub (f32.const 0.25) (local.get $dot-product)))
          (if (f32.gt (local.get $dot-product) (f32.const 0))
            (then
              (global.set $Px
                (f32.add
                  (global.get $Px)
                  (f32.mul (local.get $normal-x) (local.get $dot-product))))
              (global.set $Py
                (f32.add
                  (global.get $Py)
                  (f32.mul (local.get $normal-y) (local.get $dot-product))))))))

      ;; If the player reaches the goal, generate a new maze, and reset their
      ;; position.
      (if (i32.and
            (f32.gt (global.get $Px) (f32.const 22))
            (f32.gt (global.get $Py) (f32.const 22)))
        (then
          (global.set $mode (i32.const 3)) ;; winning
          (global.set $mode-timer (i32.const 120)) ;; reset position over time
          (global.set $max-wall-addr (i32.const 0x1078))))

      (br $done))

    ;; MODE: $winning
    (local.set $dist
      (f32.div
        (f32.convert_i32_s (global.get $mode-timer))
        (f32.const 120)))
    (global.set $Px
      (f32.add (f32.const 0.5) (f32.mul (f32.sub (global.get $Px) (f32.const 0.5)) (local.get $dist))))
    (global.set $Py
      (f32.add (f32.const 0.5) (f32.mul (f32.sub (global.get $Py) (f32.const 0.5)) (local.get $dist))))
    (global.set $angle
      (f32.add
        (f32.const 0.7853981633974483)
        (f32.mul (f32.sub (global.get $angle) (f32.const 0.7853981633974483))
                 (local.get $dist))))

    (if (i32.eqz (global.get $mode-timer))
      (then
        (global.set $mode (i32.const 0)) ;; init
        (global.set $mode-timer (i32.const 15)))) ;; shorter wait
    (br $done))

  ;; DRAWING:
  ;; Loop for each column.
  (loop $x-loop
    (local.set $xproj
      (f32.div
        (f32.convert_i32_s (i32.sub (local.get $x) (i32.const 160)))
        (f32.const 160)))

    ;; Shoot a ray against a wall. Use rays projected onto screen plane.
    (local.set $ray-x
      (f32.add (local.get $Dx) (f32.mul (local.get $xproj) (f32.neg (local.get $Dy)))))
    (local.set $ray-y
      (f32.add (local.get $Dy) (f32.mul (local.get $xproj) (local.get $Dx))))

    ;; Draw ceiling, wall, floor
    (call $draw-strip
      (i32.shl (local.get $x) (i32.const 2))
      (f32.div
        (f32.const 120)
        (call $ray-walls (local.get $ray-x) (local.get $ray-y)))
      (local.get $ray-x) (local.get $ray-y))

    ;; loop on x
    (br_if $x-loop
      (i32.lt_s
        (local.tee $x (i32.add (local.get $x) (i32.const 1)))
        (i32.const 320)))))
