(import "" "rand" (func $random (result f32)))

;; 4 pages * 64KiB per page
;; [0, N * 20)     => N blobs * {x, dx, y, dy, r: f32}
;; [984, 1024)     => Random ranges (see below)
;; [1024, 257024)  => canvasData (320x200), 4 bytes per pixel.
(memory (export "mem") 4)

(data (i32.const 984)
  "\00\00\48\43" ;; 200   x range
  "\00\00\48\42" ;; 50    x addend
  "\cd\cc\cc\3e" ;; 0.4   dx range
  "\cd\cc\4c\be" ;; -0.2  dx addend
  "\00\00\c8\42" ;; 100   y range
  "\00\00\48\42" ;; 50    y addend
  "\cd\cc\cc\3e" ;; 0.4   dy range
  "\cd\cc\4c\be" ;; -0.2  dy addend
  "\00\00\f0\41" ;; 30    r range
  "\00\00\a0\41" ;; 20    r addend
)

(global $blobsEnd (mut i32) (i32.const 0))
(func (export "blobs") (param i32)
  (local $i i32)
  (local $temp i32)

  (global.set $blobsEnd
    (i32.mul
      (local.get 0)
      (i32.const 20)))

  ;; For each float in each blob, set to a random number given a range loaded
  ;; from the table above.
  (loop $blobs
    ;; temp = (i << 1) % 40
    (local.set $temp
      (i32.rem_u
        (i32.shl (local.get $i) (i32.const 1))
        (i32.const 40)))

    ;; memory[i] = (random() * randrange[temp].range) + randrange[temp].addend
    (f32.store
      (local.get $i)
      (f32.add
        (f32.mul (call $random) (f32.load offset=984 (local.get $temp)))
        (f32.load offset=988 (local.get $temp))))

    ;; loop
    (br_if $blobs
      (i32.ne
        (local.tee $i (i32.add (local.get $i) (i32.const 4)))
        (global.get $blobsEnd)))))

(func $move (param $blob i32) (param $blobR f32) (param $canvasR f32)
  (local $sum f32)
  (local $dx f32)

  ;; sum = blob.x + blob.dx; if abs(canvas.r - sum) > (canvas.r - blob.r), then
  (if
    (f32.gt
      (f32.abs
        (f32.sub
          (local.get $canvasR)
          (local.tee $sum
            (f32.add
              (f32.load offset=0 (local.get $blob))
              (local.tee $dx
                (f32.load offset=4 (local.get $blob)))))))
      (f32.sub
        (local.get $canvasR)
        (local.get $blobR)))

    ;; blob.dx = -blob.dx
    (f32.store offset=4
      (local.get $blob)
      (f32.neg (local.get $dx))))

  ;; blob.x = sum;
  (f32.store offset=0 (local.get $blob) (local.get $sum)))

(func (export "run")
  (local $blob i32)
  (local $x i32)
  (local $y i32)
  (local $temp f32)
  (local $sum f32)

  ;; Loop over all blobs and update position.
  (loop $blobs
    ;; Update x coordinate.
    (call $move
      (local.get $blob)
      ;; temp = blob.r
      (local.tee $temp (f32.load offset=16 (local.get $blob)))
      (f32.const 160))

    ;; Update y coordinate.
    (call $move
      (i32.add (local.get $blob) (i32.const 8))
      (local.get $temp)
      (f32.const 100))

    (br_if $blobs
      (i32.ne
        (local.tee $blob (i32.add (local.get $blob) (i32.const 20)))
        (global.get $blobsEnd))))

  ;; Loop over all pixels.
  (loop $yloop

    (local.set $x (i32.const 0))
    (loop $xloop

      (local.set $blob (i32.const 0))
      (local.set $sum (f32.const 0))
      (loop $blobs

        ;; sum += (...)
        (local.set $sum
          (f32.add
            (local.get $sum)

            (f32.div
              ;; blob[i].r ** 2
              (f32.mul
                (local.tee $temp
                  (f32.load offset=16 (local.get $blob)))
                (local.get $temp))

              (f32.add
                ;; (x - blob[i].x) ** 2
                (f32.mul
                  (local.tee $temp
                    (f32.sub
                      (f32.convert_i32_s (local.get $x))
                      (f32.load offset=0 (local.get $blob))))
                  (local.get $temp))

                ;; (y - blob[i].y) ** 2
                (f32.mul
                  (local.tee $temp
                    (f32.sub
                      (f32.convert_i32_s (local.get $y))
                      (f32.load offset=8 (local.get $blob))))
                  (local.get $temp))))))

        (br_if $blobs
          (i32.ne
            (local.tee $blob (i32.add (local.get $blob) (i32.const 20)))
            (global.get $blobsEnd))))

      ;; canvas[pixel] = (trunc(clamp(sum - 1, 0, 1) * 255) << 24) | color;
      (i32.store offset=1024
        (i32.shl
          (i32.add
            (i32.mul (local.get $y) (i32.const 320))
            (local.get $x))
          (i32.const 2))
        (i32.or
          (i32.shl
            (i32.trunc_f32_s
              (f32.mul
                (f32.max
                  (f32.min
                    (f32.sub (local.get $sum) (f32.const 1))
                    (f32.const 1))
                  (f32.const 0))
                (f32.const 255)))
            (i32.const 24))
          (i32.const 0x73d419)))

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
