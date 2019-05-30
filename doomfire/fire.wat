;; FIRE_WIDTH = 320
;; FIRE_HEIGHT = 168
;; FIRE_WIDTH * FIRE_HEIGHT = 53760
;; FIRE_WIDTH * (FIRE_HEIGHT - 1) = 53440

(import "" "rand" (func $random (result f64)))

;; 5 pages * 64KiB bytes per page:
;; [0, 53760)       => firePixels, 1 byte per pixel.
;; [53760, 268800)  => canvasData, 4 bytes per pixel.
;; [268800, 268948) => Palette data, RGBA.
(memory (export "mem") 5)

;; Palette data.
(data (i32.const 268800)
  "\07\07\07\FF\1F\07\07\FF\2F\0F\07\FF\47\0F\07\FF\57\17\07\FF\67\1F\07\FF"
  "\77\1F\07\FF\8F\27\07\FF\9F\2F\07\FF\AF\3F\07\FF\BF\47\07\FF\C7\47\07\FF"
  "\DF\4F\07\FF\DF\57\07\FF\DF\57\07\FF\D7\5F\07\FF\D7\5F\07\FF\D7\67\0F\FF"
  "\CF\6F\0F\FF\CF\77\0F\FF\CF\7F\0F\FF\CF\87\17\FF\C7\87\17\FF\C7\8F\17\FF"
  "\C7\97\1F\FF\BF\9F\1F\FF\BF\9F\1F\FF\BF\A7\27\FF\BF\A7\27\FF\BF\AF\2F\FF"
  "\B7\AF\2F\FF\B7\B7\2F\FF\B7\B7\37\FF\CF\CF\6F\FF\DF\DF\9F\FF\EF\EF\C7\FF"
  "\FF\FF\FF\FF")

(func $setup
  (local $i i32)

  ;; Fill bottom row with color 36, (R=0xff, G=0xff, B=0xff).
  (local.set $i (i32.const 320))
  (loop
    ;; memory[53440 - 1 + i] = 36
    (i32.store8 offset=53439 (local.get $i) (i32.const 36))
    ;; loop if --i != 0
    (br_if 0
      (local.tee $i (i32.sub (local.get $i) (i32.const 1))))))

;; Run setup at start.
(start $setup)

(func (export "run")
  (local $i i32)
  (local $pixel i32)
  (local $randIdx i32)

  ;; Update the fire.
  (loop $xloop
    (loop $yloop
      (if
        ;; if (pixel = memory[i += 320]) != 0
        (local.tee $pixel
          (i32.load8_u
            (local.tee $i
              (i32.add (local.get $i) (i32.const 320)))))
        (then
          ;; randIdx = round(random() * 3.0) & 3
          (local.set $randIdx
            (i32.and
              (i32.trunc_f64_u
                (f64.nearest
                  (f64.mul
                    (call $random)
                    (f64.const 3))))
              (i32.const 3)))

          ;; memory[i - randIdx - 319] = pixel - (randIdx & 1)
          (i32.store8
            (i32.sub
              (i32.sub
                (local.get $i)
                (local.get $randIdx))
              (i32.const 319))
            (i32.sub
              (local.get $pixel)
              (i32.and
                (local.get $randIdx)
                (i32.const 1)))))
        (else
          ;; memory[i - 320] = 0
          (i32.store8
            (i32.sub (local.get $i) (i32.const 320))
            (i32.const 0))))

      ;; loop if i < 53760 - 320
      (br_if $yloop
        (i32.lt_u (local.get $i) (i32.const 53440))))

    ;; i -= 53760 - 320 - 1, loop if i != 320
    (br_if $xloop
      (i32.ne
        (local.tee $i (i32.sub (local.get $i) (i32.const 53439)))
        (i32.const 320))))

  ;; copy from firePixels to canvasData, using palette data.
  (local.set $i (i32.const 53760))
  (loop
    ;; --i
    (local.set $i (i32.sub (local.get $i) (i32.const 1)))

    ;; memory[53760 + (i << 2)] = memory[268800 + (memory[i] << 2)]
    (i32.store offset=53760
      (i32.shl (local.get $i) (i32.const 2))
      (i32.load offset=268800
        (i32.shl
          (i32.load8_u (local.get $i))
          (i32.const 2))))

    ;; loop if i != 0
    (br_if 0 (local.get $i))))
