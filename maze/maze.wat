(import "Math" "sin" (func $sin (param f32) (result f32)))

(memory (export "mem") 6)

(data (i32.const 0)
  ;; top wall
  "\00\00\40\c1"  ;; -12.0
  "\00\00\40\41"  ;; +12.0
  "\00\00\40\41"  ;; +12.0
  "\00\00\40\41"  ;; +12.0
  "\00\00\40\41"  ;; scale=+12
  ;; right wall
  "\00\00\40\41"  ;; +12.0
  "\00\00\40\41"  ;; +12.0
  "\00\00\40\41"  ;; +12.0
  "\00\00\40\c1"  ;; -12.0
  "\00\00\40\41"  ;; scale=12
  ;; bottom wall
  "\00\00\40\41"  ;; +12.0
  "\00\00\40\c1"  ;; -12.0
  "\00\00\40\c1"  ;; -12.0
  "\00\00\40\c1"  ;; -12.0
  "\00\00\40\41"  ;; scale=12
  ;; left wall
  "\00\00\40\c1"  ;; -12.0
  "\00\00\40\c1"  ;; -12.0
  "\00\00\40\c1"  ;; -12.0
  "\00\00\40\41"  ;; +12.0
  "\00\00\40\41"  ;; scale=12
)

;; brick texture 2bpp
(data (i32.const 0x400)
  "\aa\aa\aa\aa\aa\aa\aa\aa\00\00\00\00\02\00\00\00\ff\ff\ff\7f\f2\ff\ff\ff"
  "\ff\ff\ff\7f\f2\ff\ff\ff\fc\fc\fc\7c\f2\fc\fc\fc\f7\f7\f7\77\f2\f7\f7\f7"
  "\ff\ff\ff\7f\f2\ff\ff\ff\ff\ff\ff\7f\f2\ff\ff\ff\fc\fc\fc\7c\f2\fc\fc\fc"
  "\f7\f7\f7\77\f2\f7\f7\f7\ff\ff\ff\7f\f2\ff\ff\ff\ff\ff\ff\7f\f2\ff\ff\ff"
  "\fc\fc\fc\7c\f2\fc\fc\fc\f7\f7\f7\77\f2\f7\f7\f7\ff\ff\ff\7f\f2\ff\ff\ff"
  "\55\55\55\55\52\55\55\55\aa\aa\aa\aa\aa\aa\aa\aa\02\00\00\00\00\00\00\00"
  "\f2\ff\ff\ff\ff\ff\ff\7f\f2\ff\ff\ff\ff\ff\ff\7f\f2\fc\fc\fc\fc\fc\fc\7c"
  "\f2\f7\f7\f7\f7\f7\f7\77\f2\ff\ff\ff\ff\ff\ff\7f\f2\ff\ff\ff\ff\ff\ff\7f"
  "\f2\fc\fc\fc\fc\fc\fc\7c\f2\f7\f7\f7\f7\f7\f7\77\f2\ff\ff\ff\ff\ff\ff\7f"
  "\f2\ff\ff\ff\ff\ff\ff\7f\f2\fc\fc\fc\fc\fc\fc\7c\f2\f7\f7\f7\f7\f7\f7\77"
  "\f2\ff\ff\ff\ff\ff\ff\7f\52\55\55\55\55\55\55\55"
)

;; floor and ceiling texture
(data (i32.const 0x500)
  "\00\56\55\55\55\55\55\02\80\56\55\55\55\55\55\0a\a0\55\55\55\55\55\55\29"
  "\68\55\55\55\55\55\55\a5\5a\55\55\55\55\55\55\95\55\55\55\55\55\55\55\55"
  "\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55"
  "\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55"
  "\55\55\55\95\5a\55\55\55\55\55\55\a5\68\55\55\55\55\55\55\29\a0\55\55\55"
  "\55\55\55\0a\80\56\55\55\55\55\55\02\00\56\55\55\55\55\55\0a\80\56\55\55"
  "\55\55\55\29\a0\55\55\55\55\55\55\a5\68\55\55\55\55\55\55\95\5a\55\55\55"
  "\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55"
  "\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55\55"
  "\55\55\55\55\55\55\55\55\5a\55\55\55\55\55\55\95\68\55\55\55\55\55\55\a5"
  "\a0\55\55\55\55\55\55\29\80\56\55\55\55\55\55\0a"
)

;; palette
(data (i32.const 0xd00)
  ;; brick palette
  "\f3\5f\5f\ff\79\0e\0e\ff\00\00\00\ff\9f\25\25\ff"
  ;; ceiling palette
  "\62\8d\c6\ff\81\95\af\ff\62\8d\c6\ff"
  ;; floor palette
  "\81\95\af\ff\b5\b5\b5\ff\b5\b5\b5\ff"
)

;; Position and direction vectors. Direction is updated from angle, which is
;; expressed in radians.
(global $Px (mut f32) (f32.const 0))
(global $Py (mut f32) (f32.const 0))
(global $angle (mut f32) (f32.const 0.7853981633974483))
(global $t2 (mut f32) (f32.const 0))

(func (export "init")
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
        (i32.const 120)))))

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
          (global.set $t2 (local.get $t2))
          (return (local.get $t1))))))

  (f32.const inf))

(func $scale-frac-i32 (param $x f32) (result i32)
  (local.set $x (f32.add (local.get $x) (local.get $x)))
  (i32.trunc_f32_s
    (f32.mul
      (f32.sub (local.get $x) (f32.floor (local.get $x)))
      (f32.const 32))))

(func $texture
      (param $tex-addr i32) (param $pal-addr i32)
      (param $x f32) (param $y f32)
      (result i32)
  (local $ix i32)
  (local $iy i32)

  (local.set $ix (call $scale-frac-i32 (local.get $x)))
  (local.set $iy (call $scale-frac-i32 (local.get $y)))

  ;; read 2bpp color, then index into palette
  (i32.load
    (i32.add
      (local.get $pal-addr)
      (i32.shl
        (i32.and
          (i32.shr_u
            (i32.load8_u
              (i32.add
                (local.get $tex-addr)
                (i32.add (i32.shl (local.get $iy) (i32.const 3))
                         (i32.shr_u (local.get $ix) (i32.const 2)))))
            (i32.shl (i32.and (local.get $ix) (i32.const 3)) (i32.const 1)))
          (i32.const 3))
        (i32.const 2)))))

(func $draw-ceiling-and-floor
      (param $top-addr i32) (param $height i32) (param $ray-x f32) (param $ray-y f32)
      (result i32)
  (local $bot-addr i32)
  (local $dist-addr i32)
  (local $dist f32)
  (local $x f32)
  (local $y f32)

  (local.set $bot-addr (i32.add (local.get $top-addr) (i32.const 307200)))

  (if (local.get $height)
    (then
      (loop $loop
        ;; update distance
        (local.set $dist (f32.load offset=0xe00 (local.get $dist-addr)))
        (local.set $dist-addr (i32.add (local.get $dist-addr) (i32.const 4)))

        ;; find UV using distance table
        (local.set $x
          (f32.add (global.get $Px) (f32.mul (local.get $ray-x) (local.get $dist))))
        (local.set $y
          (f32.add (global.get $Py) (f32.mul (local.get $ray-y) (local.get $dist))))

        ;; draw ceiling (decrement after)
        (i32.store offset=0x3000
          (local.get $top-addr)
          (call $texture
            (i32.const 0x500) (i32.const 0xd10)
            (local.get $x) (local.get $y)))
        (local.set $top-addr (i32.add (local.get $top-addr) (i32.const 1280)))

        ;; draw-floor (decrement before)
        (local.set $bot-addr (i32.sub (local.get $bot-addr) (i32.const 1280)))
        (i32.store offset=0x3000
          (local.get $bot-addr)
          (call $texture
            (i32.const 0x500) (i32.const 0xd1c)
            (local.get $x) (local.get $y)))


        (br_if $loop
          (local.tee $height (i32.sub (local.get $height) (i32.const 1)))))))
  (local.get $top-addr))

(func (export "run")
  (local $x i32)
  (local $y i32)
  (local $wall i32)
  (local $xproj f32)
  (local $Dx f32)
  (local $Dy f32)
  (local $mindist f32)
  (local $mint2 f32)
  (local $dist f32)
  (local $height i32)
  (local $miny i32)
  (local $maxy i32)
  (local $addr i32)
  (local $rotate f32)

  (local $ray-x f32)
  (local $ray-y f32)

  ;; rotate
  (local.set $rotate
    (f32.mul
      (f32.convert_i32_s
        (i32.sub
          (i32.load8_u (i32.const 0))
          (i32.load8_u (i32.const 1))))
      (f32.const 0.08)))
  (global.set $angle
    (call $fmod (f32.add (global.get $angle) (local.get $rotate))
                (f32.const 6.283185307179586)))

  (local.set $Dx (call $sin (global.get $angle)))
  (local.set $Dy (call $sin (f32.add (global.get $angle) (f32.const 1.5707963267948966))))

  ;; move forward
  (if (i32.load8_u (i32.const 2))
    (then
      (global.set $Px
        (f32.add (global.get $Px) (f32.mul (local.get $Dx) (f32.const 0.10))))
      (global.set $Py
        (f32.add (global.get $Py) (f32.mul (local.get $Dy) (f32.const 0.10))))))

  ;; Loop for each column.
  (loop $x-loop
    (local.set $xproj
      (f32.sub
        (f32.div
          (f32.convert_i32_s (local.get $x))
          (f32.const 160))
        (f32.const 1)))

    ;; for each wall
    (local.set $mindist (f32.const inf))
    (local.set $wall (i32.const 0))
    (loop $wall-loop

      ;; Shoot a ray against a wall. Use rays projected onto screen plane.
      ;; choose the shortest distance.
      (local.set $ray-x
        (f32.add (local.get $Dx) (f32.mul (local.get $xproj) (f32.neg (local.get $Dy)))))
      (local.set $ray-y
        (f32.add (local.get $Dy) (f32.mul (local.get $xproj) (local.get $Dx))))

      (local.set $dist
        (call $ray-line
          (local.get $ray-x)
          (local.get $ray-y)
          (f32.load (local.get $wall))
          (f32.load offset=4 (local.get $wall))
          (f32.load offset=8 (local.get $wall))
          (f32.load offset=12 (local.get $wall))))

      (if (f32.lt (local.get $dist) (local.get $mindist))
        (then
          (local.set $mindist (local.get $dist))
          (local.set $mint2
            (f32.mul (global.get $t2) (f32.load offset=16 (local.get $wall))))))

      (br_if $wall-loop
        (i32.lt_s
          (local.tee $wall (i32.add (local.get $wall) (i32.const 20)))
          (i32.const 80))))

    (local.set $height
      (i32.trunc_f32_s
        (f32.div
          (f32.const 120)  ;; screen height / 2.
          (local.get $mindist))))

    (local.set $miny (i32.sub (i32.const 120) (local.get $height)))
    (local.set $maxy (i32.add (i32.const 120) (local.get $height)))

    ;; clamp miny and maxy
    (if (i32.le_s (local.get $miny) (i32.const 0))
      (then (local.set $miny (i32.const 0))))
    (if (i32.ge_s (local.get $maxy) (i32.const 240))
      (then (local.set $maxy (i32.const 240))))

    ;; Start at middle of column.
    (local.set $y (i32.const 0))
    (local.set $addr (i32.shl (local.get $x) (i32.const 2)))

    ;; draw ceiling and floor
    (local.set $addr
      (call $draw-ceiling-and-floor
        (local.get $addr) (local.get $miny) (local.get $ray-x) (local.get $ray-y)))

    ;; draw wall
    (if (local.get $height)
      (then
        (local.set $y (local.get $miny))
        (loop $y-loop
          (i32.store offset=0x3000 (local.get $addr)
            (call $texture
              (i32.const 0x400) (i32.const 0xd00)
              (local.get $mint2)
              (f32.div (f32.convert_i32_s (i32.sub (local.get $y) (i32.sub (i32.const 120) (local.get $height))))
                       (f32.convert_i32_s (i32.mul (local.get $height) (i32.const 2))))))
          (local.set $addr (i32.add (local.get $addr) (i32.const 1280)))
          (br_if $y-loop
            (i32.lt_s
              (local.tee $y (i32.add (local.get $y) (i32.const 1)))
              (local.get $maxy))))))

    ;; loop on x
    (br_if $x-loop
      (i32.lt_s
        (local.tee $x (i32.add (local.get $x) (i32.const 1)))
        (i32.const 320))))
)
