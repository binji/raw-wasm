(import "Math" "sin" (func $sin (param f32) (result f32)))

(memory (export "mem") 4)

(data (i32.const 0)
  "\00\00\00\00" ;; ground.x
  "\00\00\c8\42" ;; ground.y
  "\00\00\00\00" ;; ground.z
  "\00\00\c2\42" ;; ground.r
  "\3b\df\6f\3f" ;; ground.R
  "\04\56\8e\3e" ;; ground.G
  "\91\ed\bc\3e" ;; ground.B
)

(data (i32.const 112)
  "\04\56\8e\3e" ;; bg.R
  "\3b\df\6f\3f" ;; bg.G
  "\f2\d2\4d\3f" ;; bg.B

  "\00\00\00\40\8f\c2\75\3e\00\00\80\3f\00\00\00\00" ;; s1.x
  "\00\00\00\40\3d\0a\57\3f\00\00\c0\3f\cd\cc\cc\3d" ;; s1.y
  "\00\00\00\00\00\00\00\00\00\00\00\00\66\66\e6\c0" ;; s1.z
  "\00\00\00\00\00\00\00\00\00\00\00\00\cd\cc\4c\3f" ;; s1.r
  "\0a\d7\a3\3e\71\3d\8a\3e\00\00\00\00\c3\f5\28\3f" ;; s1.R
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\80\3f" ;; s1.G
  "\52\b8\9e\3e\14\ae\c7\3e\00\00\00\00\00\00\80\3f" ;; s1.B
  "\00\00\40\40\a4\70\7d\3f\00\00\00\00\00\00\00\00" ;; s2.x
  "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\c0" ;; s2.y
  "\00\00\40\40\a4\70\7d\3f\00\00\c0\3f\00\00\c0\c0" ;; s2.z
  "\00\00\00\00\00\00\00\00\00\00\00\00\66\66\a6\3f" ;; s2.r
  "\5c\8f\02\3f\c3\f5\a8\3e\00\00\00\00\29\5c\0f\3e" ;; s2.R
  "\5c\8f\02\3f\14\ae\c7\3e\00\00\00\00\00\00\80\3f" ;; s2.G
  "\5c\8f\02\3f\ec\51\b8\3e\00\00\00\00\00\00\80\3f" ;; s2.B
  "\00\00\40\40\5c\8f\82\3f\00\00\00\00\00\00\00\3f" ;; s3.x
  "\00\00\00\00\00\00\00\00\00\00\00\00\33\33\13\40" ;; s3.y
  "\00\00\40\c0\5c\8f\82\3f\00\00\c0\3f\66\66\06\c1" ;; s3.z
  "\00\00\00\00\ec\51\38\3e\00\00\00\00\33\33\33\3f" ;; s3.r
  "\5c\8f\02\3f\85\eb\11\3f\00\00\00\00\00\00\80\3f" ;; s3.R
  "\00\00\00\00\00\00\00\00\00\00\00\00\52\b8\5e\3f" ;; s3.G
  "\00\00\00\00\00\00\00\00\00\00\00\00\f6\28\5c\3f" ;; s3.B
)

(global $time (mut f32) (f32.const 0)) ;; simulation time, in random units
(global $t0 (mut f32) (f32.const 0))   ;; "time" of ray intersection
(global $rsx (mut f32) (f32.const 0))  ;; ray start x
(global $rsy (mut f32) (f32.const 0))  ;; ray start y
(global $rsz (mut f32) (f32.const 0))  ;; ray start z
(global $rdx (mut f32) (f32.const 0))  ;; ray dir x
(global $rdy (mut f32) (f32.const 0))  ;; ray dir y
(global $rdz (mut f32) (f32.const 0))  ;; ray dir z
(global $r (mut f32) (f32.const 0))    ;; current pixel R
(global $g (mut f32) (f32.const 0))    ;; current pixel G
(global $b (mut f32) (f32.const 0))    ;; current pixel B

;; Update all sphere values: x, y, z, r, R, G, B
(func $update
  (local $dst i32)
  (local $src i32)

  (local.set $dst (i32.const 28))
  (local.set $src (i32.const 124))

  (loop
    ;; set value to A*sin(B*t+C)+D
    (f32.store (local.get $dst)
      (f32.add
        (f32.mul
          (f32.load offset=0 (local.get $src))
          (call $sin
            (f32.add
              (f32.mul (global.get $time) (f32.load offset=4 (local.get $src)))
              (f32.load offset=8 (local.get $src)))))
        (f32.load offset=12 (local.get $src))))

    (local.set $src (i32.add (local.get $src) (i32.const 16)))
    (br_if 0
      (i32.ne
        (local.tee $dst (i32.add (local.get $dst) (i32.const 4)))
        (i32.const 112)))))

;; Ray/sphere intersection.
;;   $s is sphere address
;;   ray pos/dir via globals rs{x,y,z}, rd{x,y,z}

;; Returns distance to hit along ray, or inf (no hit).
(func $ray_sphere (param $s i32) (result f32)
  (local $Lx f32)
  (local $Ly f32)
  (local $Lz f32)
  (local $b f32)
  (local $r f32)
  (local $d2 f32)

  (local.set $d2
    (f32.add
      (f32.sub
        (f32.mul
          (local.tee $b
            (f32.add
              (f32.add
                (f32.mul
                  (local.tee $Lx
                    (f32.sub
                      (f32.load offset=0 (local.get $s))
                      (global.get $rsx)))
                  (global.get $rdx))
                (f32.mul
                  (local.tee $Ly
                    (f32.sub
                      (f32.load offset=4 (local.get $s))
                      (global.get $rsy)))
                  (global.get $rdy)))
              (f32.mul
                (local.tee $Lz
                  (f32.sub
                    (f32.load offset=8 (local.get $s))
                    (global.get $rsz)))
                (global.get $rdz))))
          (local.get $b))
        (f32.add
          (f32.add
            (f32.mul (local.get $Lx) (local.get $Lx))
            (f32.mul (local.get $Ly) (local.get $Ly)))
          (f32.mul (local.get $Lz) (local.get $Lz))))
      (f32.mul
        (local.tee $r (f32.load offset=12 (local.get $s)))
        (local.get $r))))

  (if (result f32)
    (f32.gt (local.get $d2) (f32.const 0))
    (if (result f32)
      (f32.gt
        (local.tee $r
          (f32.sub (local.get $b) (local.tee $d2 (f32.sqrt (local.get $d2)))))
        (f32.const 1e-4))
      (local.get $r)
      (if (result f32)
        (f32.gt
          (local.tee $r (f32.add (local.get $b) (local.get $d2)))
          (f32.const 1e-4))
        (local.get $r)
        (f32.const inf)))
    (f32.const inf)))

;; Intersect ray w/ all spheres, return address of closest hit (or -1 if none).
(func $scene (result i32)
  (local $s i32)
  (local $smin i32)
  (local $t0 f32)

  (local.set $smin (i32.const -1))
  (global.set $t0 (f32.const inf))

  (loop
    (if
      (f32.lt
        (local.tee $t0 (call $ray_sphere (local.get $s)))
        (global.get $t0))
      (then
        (global.set $t0 (local.get $t0))
        (local.set $smin (local.get $s))))
    (br_if 0
      (i32.ne
        (local.tee $s (i32.add (local.get $s) (i32.const 28)))
        (i32.const 112))))
  (local.get $smin))

;; Accumulate given color into current pixel's color, scaled by $scale.
(func $accum (param $r f32) (param $g f32) (param $b f32) (param $scale f32)
  (global.set $r
    (f32.add (global.get $r) (f32.mul (local.get $r) (local.get $scale))))
  (global.set $g
    (f32.add (global.get $g) (f32.mul (local.get $g) (local.get $scale))))
  (global.set $b
    (f32.add (global.get $b) (f32.mul (local.get $b) (local.get $scale)))))

;; Calculate pixel color.
(func $scene_col
  (local $bounce i32)
  (local $scale f32)
  (local $smin i32)
  (local $dot f32)
  (local $dx f32)
  (local $dy f32)
  (local $dz f32)
  (local $nx f32)
  (local $ny f32)
  (local $nz f32)

  (local.set $bounce (i32.const 3))
  (local.set $scale (f32.const 1))

  ;; Loop for bounced rays.
  (loop $loop
    (if
      (i32.ge_s
        (local.tee $smin (call $scene))
        (i32.const 0))
      (then
        (global.set $t0 (f32.sub (global.get $t0) (f32.const 1e-2))) ;; nudge

        ;; save dir
        (local.set $dx (global.get $rdx))
        (local.set $dy (global.get $rdy))
        (local.set $dz (global.get $rdz))

        ;; new pos
        (global.set $rsx
          (f32.add (global.get $rsx) (f32.mul (local.get $dx) (global.get $t0))))
        (global.set $rsy
          (f32.add (global.get $rsy) (f32.mul (local.get $dy) (global.get $t0))))
        (global.set $rsz
          (f32.add (global.get $rsz) (f32.mul (local.get $dz) (global.get $t0))))

        ;; normal
        (global.set $rdx
          (f32.sub (global.get $rsx) (f32.load offset=0 (local.get $smin))))
        (global.set $rdy
          (f32.sub (global.get $rsy) (f32.load offset=4 (local.get $smin))))
        (global.set $rdz
          (f32.sub (global.get $rsz) (f32.load offset=8 (local.get $smin))))
        (call $norm)

        ;; save normal
        (local.set $nx (global.get $rdx))
        (local.set $ny (global.get $rdy))
        (local.set $nz (global.get $rdz))

        ;; light dir
        (global.set $rdx (f32.sub (f32.const -1) (global.get $rsx)))
        (global.set $rdy (f32.sub (f32.const -9) (global.get $rsy)))
        (global.set $rdz (f32.sub (f32.const -2) (global.get $rsz)))
        (call $norm)

        (call $accum
          (f32.const 0.1) (f32.const 0.1) (f32.const 0.1) (local.get $scale))

        ;; do shadow
        (if
          (i32.lt_s (call $scene) (i32.const 0))
          (then
            (local.set $dot
              (f32.max
                (f32.add
                  (f32.add
                    (f32.mul (global.get $rdx) (local.get $nx))
                    (f32.mul (global.get $rdy) (local.get $ny)))
                  (f32.mul (global.get $rdz) (local.get $nz)))
                (f32.const 0)))

            (call $accum
              (f32.mul (f32.load offset=16 (local.get $smin)) (local.get $dot))
              (f32.mul (f32.load offset=20 (local.get $smin)) (local.get $dot))
              (f32.mul (f32.load offset=24 (local.get $smin)) (local.get $dot))
              (local.get $scale))))

        ;; do reflect
        (if
          (local.tee $bounce (i32.sub (local.get $bounce) (i32.const 1)))
          (then
            ;; reflect D across N
            (local.set $dot
              (f32.mul
                (f32.add
                  (f32.add
                    (f32.mul (local.get $dx) (local.get $nx))
                    (f32.mul (local.get $dy) (local.get $ny)))
                  (f32.mul (local.get $dz) (local.get $nz)))
                (f32.const 2)))
            (global.set $rdx
              (f32.sub (local.get $dx) (f32.mul (local.get $nx) (local.get $dot))))
            (global.set $rdy
              (f32.sub (local.get $dy) (f32.mul (local.get $ny) (local.get $dot))))
            (global.set $rdz
              (f32.sub (local.get $dz) (f32.mul (local.get $nz) (local.get $dot))))

            ;; loop w/ reflection ray in fainter color
            (local.set $scale (f32.mul (local.get $scale) (f32.const 0.2)))
            (br $loop))) )
      (else
        (call $accum
          (f32.load (i32.const 112))
          (f32.load (i32.const 116))
          (f32.load (i32.const 120))
          (local.get $scale))
      )
    )
  )
)

(func $norm
  (local $temp f32)
  (local $x f32)
  (local $y f32)
  (local $z f32)
  (local.set $temp
    (f32.sqrt
      (f32.add
        (f32.add
          (f32.mul (local.tee $x (global.get $rdx)) (local.get $x))
          (f32.mul (local.tee $y (global.get $rdy)) (local.get $y)))
        (f32.mul (local.tee $z (global.get $rdz)) (local.get $z)))))
  (global.set $rdx (f32.div (local.get $x) (local.get $temp)))
  (global.set $rdy (f32.div (local.get $y) (local.get $temp)))
  (global.set $rdz (f32.div (local.get $z) (local.get $temp))))

;; Clamp f32 color, and convert to [0, 255] range.
(func $col (param f32) (result i32)
  (i32.trunc_f32_s
    (f32.mul
      (f32.min
        (f32.max (local.get 0) (f32.const 0))
        (f32.const 1))
      (f32.const 255))))

(func (export "run") (param $time f32)
  (local $x i32)
  (local $y i32)
  (local $hit f32)

  (global.set $time (f32.mul (local.get $time) (f32.const 0.0008)))

  (call $update)

  (loop $yloop

    (local.set $x (i32.const 0))
    (loop $xloop

      (global.set $r (f32.const 0))
      (global.set $g (f32.const 0))
      (global.set $b (f32.const 0))

      (global.set $rsx (f32.const 0))
      (global.set $rsy (f32.const 0))
      (global.set $rsz (f32.const 0))

      (global.set $rdx
        (f32.sub
          (f32.mul
            (f32.const 0.005578517393521942)
            (f32.convert_i32_s (local.get $x)))
          (f32.const 0.8897735242667496)))
      (global.set $rdy
        (f32.sub
          (f32.mul
            (f32.const 0.0055785173935219414)
            (f32.convert_i32_s (local.get $y)))
          (f32.const 0.5550624806554332)))
      (global.set $rdz (f32.const -1))
      (call $norm)

      (call $scene_col)

      ;; draw pixel
      (i32.store offset=1024
        (i32.shl
          (i32.add
            (i32.mul (local.get $y) (i32.const 320))
            (local.get $x))
          (i32.const 2))
        (i32.or
          (i32.const 0xff000000)
          (i32.or
            (i32.shl (call $col (global.get $b)) (i32.const 16))
            (i32.or
              (i32.shl (call $col (global.get $g)) (i32.const 8))
              (call $col (global.get $r))))))

      ;; loop on x
      (br_if $xloop
        (i32.ne
          (local.tee $x (i32.add (local.get $x) (i32.const 1)))
          (i32.const 320))))

    ;; loop on y
    (br_if $yloop
      (i32.ne
        (local.tee $y (i32.add (local.get $y) (i32.const 1)))
        (i32.const 200)))))
