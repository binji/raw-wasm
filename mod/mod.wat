;; Memory map:
;;
;; [0x10000 .. ???????]  mod file data
;; [0x10000 .. 0x10013]  mod file name
;; [0x10014 .. 0x103b5]  sample info (31 samples)
;; [0x103b8 .. 0x10437]  sequence (up to 128 orders)
;; [0x10438 .. 0x1043b]  signature
;; [0x1043c .. ???????]  pattern data

(import "" "rate" (global $sample-rate i32))
(import "" "init" (func $init (param i32 i32)))
(import "" "draw" (func $draw (param (;pattern;) i32 (;row;) i32)))
;;(import "" "log" (func $log (param i32)))
(import "" "mem" (memory 1))
(global $song-length (mut i32) (i32.const 0))
(global $num-channels (mut i32) (i32.const 0))
(global $num-patterns (mut i32) (i32.const 0))

(global $gain (mut f32) (f32.const 0.5))
(global $c2-rate (mut i32) (i32.const 0))
(global $tick-len (mut i32) (i32.const 6))
(global $tick-offset (mut i32) (i32.const 0))
(global $pattern (mut i32) (i32.const 0))
(global $break-pattern (mut i32) (i32.const 0))
(global $row (mut i32) (i32.const 0))
(global $next-row (mut i32) (i32.const 0))
(global $tick (mut i32) (i32.const 1))
(global $speed (mut i32) (i32.const 6))
(global $pl-count (mut i32) (i32.const -1))
(global $pl-channel (mut i32) (i32.const -1))
(global $random-seed (mut i32) (i32.const 0))

(func $read16be_2x (param $addr i32) (result i32)
  (i32.shl
    (i32.or
      (i32.shl (i32.load8_u (local.get $addr)) (i32.const 8))
      (i32.load8_u offset=1 (local.get $addr)))
    (i32.const 1))
)

(func $i32_clamp0_s (param $x i32) (param $max i32) (result i32)
  (select
    (i32.const 0)
    (select
      (local.get $max)
      (local.get $x)
      (i32.gt_s (local.get $x) (local.get $max)))
    (i32.lt_s (local.get $x) (i32.const 0)))
)

(func $start
  ;; calculate number of channels
  (local $channel i32)
  (local $channel-idx i32)
  (local $i i32)
  (local $j i32)
  (local $order-entry i32)
  (local $sample-data i32)
  (local $sample-length i32)
  (local $loop-start i32)
  (local $loop-length i32)

  ;; calculate number of patterns
  (local.set $i (i32.const 0x103b8))
  (loop $loop
    (global.set $num-patterns
      (select
        (i32.add (i32.const 1) (local.tee $order-entry (i32.load8_u (local.get $i))))
        (global.get $num-patterns)
        (i32.ge_u (local.get $order-entry) (global.get $num-patterns))))
    (br_if $loop (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 1)))
                           (i32.const 0x10438))))

  (global.set $song-length
    (i32.and (i32.load8_u (i32.const 0x103b6)) (i32.const 0x7f)))

  ;; perfect hash
  (local.tee $channel
    (i32.add
      (i32.add
        (i32.add
          (i32.load8_u offset=26 (i32.load8_u offset=3 (local.get $i)))
          (i32.load8_u offset=26 (i32.load8_u offset=2 (local.get $i))))
        (i32.load8_u offset=26 (i32.add (i32.load8_u offset=1 (local.get $i))
                                        (i32.const 5))))
      (i32.load8_u offset=26 (i32.add (i32.load8_u (local.get $i))
                                      (i32.const 2)))))

  (global.set $num-channels
    (i32.mul
      (i32.load8_u (;local.get $channel;))
      (i32.lt_u (local.get $channel) (i32.const 59))))

  (call $init (global.get $num-channels) (global.get $num-patterns))

  ;; calculate sample info
  (local.set $sample-data (i32.add (i32.const 0x1043c)
                                   (i32.shl
                                     (i32.mul (global.get $num-patterns)
                                              (global.get $num-channels))
                                     (i32.const 8))))
  (local.set $i (i32.const 0x1001e))
  (local.set $j (i32.const 0xc3))  ;; 0xb5 + 14
  (loop $loop
    (local.set $sample-length (call $read16be_2x (i32.add (local.get $i) (i32.const 12))))
    (local.set $loop-start (call $read16be_2x (i32.add (local.get $i) (i32.const 16))))
    (local.set $loop-length (call $read16be_2x (i32.add (local.get $i) (i32.const 18))))

    (if (i32.gt_u (i32.add (local.get $loop-start) (local.get $loop-length))
                  (local.get $sample-length))
      (then
        ;; Check if loop_start is in bytes
        (if (i32.le_u (i32.add (i32.shr_u (local.get $loop-start) (i32.const 1))
                               (local.get $loop-length))
                      (local.get $sample-length))
          (then (local.set $loop-start (i32.shr_u (local.get $loop-start) (i32.const 1))))
          (else
            (local.set $loop-length
                       (i32.sub (local.get $sample-length) (local.get $loop-start)))))))
    (if (i32.lt_u (local.get $loop-length) (i32.const 4))
      (then
        (local.set $loop-start (local.get $sample-length))
        (local.set $loop-length (i32.const 0))))

    (i32.store (local.get $j) (local.get $sample-data))
    (f32.store offset=4 (local.get $j) (f32.convert_i32_u (local.get $loop-start)))
    (f32.store offset=8 (local.get $j) (f32.convert_i32_u (local.get $loop-length)))
    (i32.store8 offset=12 (local.get $j)
      (i32.and (i32.load8_u offset=14 (local.get $i)) (i32.const 0xf)))
    (i32.store8 offset=13 (local.get $j)
      (call $i32_clamp0_s
        (i32.and
          (i32.load8_u offset=15 (local.get $i))
          (i32.const 0x7f))
        (i32.const 64)))

    (local.set $sample-data (i32.add (local.get $sample-data) (local.get $sample-length)))
    (local.set $j (i32.add (local.get $j) (i32.const 14)))
    (br_if $loop (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 30)))
                           (i32.const 0x103a2))))

  (if (i32.gt_u (global.get $num-channels) (i32.const 4))
    (then
      (global.set $gain
        (f32.mul (global.get $gain) (f32.convert_i32_u (i32.const 2))))
      (global.set $c2-rate (i32.const 3579364)))
    (else
      (global.set $c2-rate (i32.const 3546836))))

  ;; (global.set $next-row (i32.const 0))
  ;; (global.set $tick (i32.const 1))
  ;; (global.set $speed (i32.const 6))
  (global.set $tick-len (i32.div_u (global.get $sample-rate) (i32.const 50)))
  ;; (global.set $pl-count (i32.const -1))
  ;; (global.set $pl-channel (i32.const -1))

  (loop $channel
    ;; set channel id
    (i32.store8 offset=36
      (local.tee $channel
        (i32.add
          (i32.const 0x275)
          (i32.mul (local.get $channel-idx) (i32.const 52))))
      (local.get $channel-idx))

    ;; set panning (channel 0,3 => 0; 1,2 => 127)
    (i32.store8 offset=35 (local.get $channel)
      (i32.mul
        (i32.const 127)
        (i32.ge_u
          (i32.and
            (local.tee $channel-idx
              (i32.add (local.get $channel-idx) (i32.const 1)))
            (i32.const 3))
          (i32.const 2))))
    (br_if $channel
      (i32.lt_u (local.get $channel-idx) (global.get $num-channels))))

  (call $sequence-tick)
)
(start $start)

(func $sequence-tick
  (local $channel-end i32)
  (local $tick<0 i32)
  (local $pattern-offset i32)
  (local $channel i32)
  (local $pat0 i32)
  (local $pat2 i32)
  (local $effect i32)
  (local $effect=7 i32)
  (local $param i32)
  (local $param-lo i32)
  (local $param-hi i32)
  (local $-param i32)
  (local $fx-count i32)
  ;; update-frequency
  (local $period i32)
  ;; tone-portamento
  (local $source i32)
  (local $dest i32)
  ;; vibrato-tremolo
  (local $addr i32)
  (local $amp i32)
  (local $phase i32)

  (local.set $channel (i32.const 0x275))
  (local.set $channel-end (i32.add (local.get $channel) (i32.mul (global.get $num-channels) (i32.const 52))))

  (global.set $tick (i32.sub (global.get $tick) (i32.const 1)))
  (if (local.tee $tick<0 (i32.le_s (global.get $tick) (i32.const 0)))
    (then
      (global.set $tick (global.get $speed))

      ;; sequence-row
      (if (i32.lt_s (global.get $next-row) (i32.const 0))
        (then
          (global.set $break-pattern (i32.add (global.get $pattern) (i32.const 1)))
          (global.set $next-row (i32.const 0))))

      (if (i32.ge_s (global.get $break-pattern) (i32.const 0))
        (then
          (if (i32.ge_s (global.get $break-pattern) (global.get $song-length))
            (then
              (global.set $break-pattern (i32.const 0))
              (global.set $next-row (i32.const 0))))

          (global.set $pattern (global.get $break-pattern))

          ;; clear pl-row for each channel
          (loop $channel
            (i32.store8 offset=38 (local.get $channel) (i32.const 0))
            (br_if $channel
              (i32.lt_u (local.tee $channel
                          (i32.add (local.get $channel) (i32.const 52)))
                        (local.get $channel-end))))

          (local.set $channel (i32.const 0x275))
          (global.set $break-pattern (i32.const -1))))

      (global.set $row (global.get $next-row))
      (call $draw (global.get $pattern) (global.get $row))

      (global.set $next-row (i32.add (global.get $row) (i32.const 1)))
      (if (i32.ge_u (global.get $next-row) (i32.const 64))
        (then
          (global.set $next-row (i32.const -1))))

      (local.set $pattern-offset
        (i32.add
          (i32.mul
            (i32.mul
              (i32.add
                (i32.shl
                  (i32.load8_u offset=0x103b8 (global.get $pattern))
                  (i32.const 6))
                (global.get $row))
              (global.get $num-channels))
            (i32.const 4))
          (i32.const 0x1043c)))))

    (loop $channel
      block $X
      block $vs  ;; volume-slide
      block $vt  ;; vibrato-tremolo
      block $tp  ;; tone-portamento

      (if (local.get $tick<0)
        (then
          ;; set note-key
          (i32.store16 offset=28 (local.get $channel)
            (i32.or
              (i32.shl
                (i32.and
                  (local.tee $pat0 (i32.load8_u (local.get $pattern-offset)))
                  (i32.const 0xf))
                (i32.const 8))
              (i32.load8_u offset=1 (local.get $pattern-offset))))

          ;; set note-instrument
          (i32.store8 offset=30 (local.get $channel)
            (i32.or
              (i32.shr_u
                (local.tee $pat2 (i32.load8_u offset=2 (local.get $pattern-offset)))
                (i32.const 4))
              (i32.and (local.get $pat0) (i32.const 0x10))))
          ;; set note-effect
          (local.set $effect (i32.and (local.get $pat2) (i32.const 0xf)))
          ;; set note-param
          (local.set $param (i32.load8_u offset=3 (local.get $pattern-offset)))
          (local.set $param-lo (i32.and (local.get $param) (i32.const 0xf)))
          (local.set $param-hi (i32.shr_u (local.get $param) (i32.const 4)))

          (local.set $pattern-offset (i32.add (local.get $pattern-offset) (i32.const 4)))

          ;; Convert extend effects (0xE) into 0x1Y
          (if (i32.eq (local.get $effect) (i32.const 0xE))
            (then
              (local.set $effect (i32.or (i32.const 0x10) (local.get $param-hi)))
              (local.set $param (local.get $param-lo))
              (local.set $param-hi (i32.const 0))))

          ;; Convert effect 0 to effect 0xE
          (if (i32.and (i32.eqz (local.get $effect))
                       (i32.eqz (i32.eqz (local.get $param))))
            (then
              (local.set $effect (i32.const 0xE))))

          (local.set $-param (i32.sub (i32.const 0) (local.get $param)))

          (i32.store8 offset=31 (local.get $channel) (local.get $effect))
          (i32.store8 offset=32 (local.get $channel) (local.get $param))

          ;; channel row

          ;; fx-count = 0
          ;; vibrato_add = 0
          ;; tremolo_add = 0
          ;; arpeggio_add = 0
          (i32.store offset=39 (local.get $channel) (i32.const 0))

          ;; If it's not a note delay, trigger the note.
          (if (i32.or (i32.ne (local.get $effect) (i32.const 0x1d))
                      (i32.eqz (local.get $param)))
            (then
              (call $trigger (local.get $channel))))

          block $3
          block $8
          block $b
          block $c
          block $d
          block $f
          block $11
          block $12
          block $14
          block $16
          block $17
          block $1a
          block $1b
          block $1c
          block $1e
            (br_table $X  $X  $X  $3 $vt $X  $vt $vt $8 $X  $X  $b  $c $d  $X  $f $X
                      $11 $12 $X $14 $X  $16 $17 $X  $X $1a $1b $1c $X $1e $X
                      (local.get $effect))
          end $1e ;; pattern delay
            (global.set $tick
              (i32.add
                (global.get $speed)
                (i32.mul (global.get $speed) (local.get $param))))
            br $X
          end $1c ;; note cut
            (br_if $X (local.get $param))
            (i32.store8 offset=34 (local.get $channel) (i32.const 0))
            br $X
          end $1b ;; fine volume down
            (local.set $param (local.get $-param))
            ;; fallthrough
          end $1a ;; fine volume up
            (i32.store8 offset=34 (local.get $channel)
              (call $i32_clamp0_s
                (i32.add
                  (i32.load8_u offset=34 (local.get $channel))
                  (local.get $param))
                (i32.const 64)))
            br $X
          end $17 ;; set tremolo waveform
            unreachable
          end $16 ;; pattern loop
            (if (i32.eqz (local.get $param))
              (then
                (i32.store8 offset=38 (local.get $channel) (global.get $row))))

            (br_if $X
              (i32.or
                (i32.ge_s
                  (i32.load8_u offset=38 (local.get $channel))
                  (global.get $row))
                (i32.ge_s (global.get $break-pattern) (i32.const 0))))

            (if (i32.lt_s (global.get $pl-count) (i32.const 0))
              (then
                (global.set $pl-count (local.get $param))
                (global.set $pl-channel (i32.load8_u offset=36 (local.get $channel)))))
            (br_if $X
              (i32.ne (global.get $pl-channel)
                      (i32.load8_u offset=36 (local.get $channel))))
            (if (i32.eqz (global.get $pl-count))
              (then
                (i32.store8 offset=38 (local.get $channel)
                  (i32.add (global.get $row) (i32.const 1))))
              (else
                (global.set $next-row (i32.load8_u offset=38 (local.get $channel)))))
            (global.set $pl-count
              (i32.sub
                (global.get $pl-count)
                (i32.const 1)))
            br $X
          end $14 ;; set vibrato waveform
            (br_if $X (i32.ge_s (local.get $param) (i32.const 8)))
            (i32.store8 offset=43 (local.get $channel) (local.get $param))
            br $X
          end $12 ;; fine portamento down
            (local.set $param (local.get $-param))
            ;; fallthrough
          end $11 ;; fine portamento up
            (i32.store16 offset=24 (local.get $channel)
              (call $i32_clamp0_s
                (i32.sub
                  (i32.load16_u offset=24 (local.get $channel))
                  (local.get $param))
                (i32.const 65535)))
            br $X
          end $f  ;; set speed
            (br_if $X (i32.eqz (local.get $param)))
            (if (i32.lt_s (local.get $param) (i32.const 32))
              (then
                (global.set $tick (local.get $param))
                (global.set $speed (local.get $param)))
              (else
                (global.set $tick-len
                  (i32.div_u (i32.mul (global.get $sample-rate) (i32.const 5))
                             (i32.shl (local.get $param) (i32.const 1))))))
            br $X
          end $d  ;; pattern break
            (br_if $X (i32.ge_s (global.get $pl-count) (i32.const 0)))

            (if (i32.lt_s (global.get $break-pattern) (i32.const 0))
              (then
                (global.set $break-pattern
                  (i32.add (global.get $pattern) (i32.const 1)))))
            (global.set $next-row
              (i32.add
                (i32.mul (local.get $param-hi) (i32.const 10))
                (local.get $param-lo)))

            (br_if $X (i32.lt_s (global.get $next-row) (i32.const 64)))
            (global.set $next-row (i32.const 0))
            br $X
          end $c  ;; set volume
            (i32.store8 offset=34 (local.get $channel)
              (call $i32_clamp0_s (local.get $param) (i32.const 64)))
            br $X
          end $b ;; pattern jump
            (br_if $X (i32.ge_s (global.get $pl-count) (i32.const 0)))
            (global.set $break-pattern (local.get $param))
            (global.set $next-row (i32.const 0))
            br $X
          end $8 ;; set panning
            (br_if $X (i32.eq (global.get $num-channels) (i32.const 4)))
            (i32.store8 offset=35 (local.get $channel)
              (call $i32_clamp0_s (local.get $param) (i32.const 127)))
            br $X
          end $3  ;; tone portamento
            (br_if $X (i32.eqz (local.get $param)))
            (i32.store8 offset=37 (local.get $channel) (local.get $param)))
        (else
          ;; channel tick
          (local.set $effect (i32.load8_u offset=31 (local.get $channel)))
          (local.set $param (i32.load8_u offset=32 (local.get $channel)))
          ;; fx-count++
          (i32.store8 offset=39 (local.get $channel)
            (local.tee $fx-count
              (i32.add (i32.load8_u offset=39 (local.get $channel)) (i32.const 1))))

          block $1
          block $2
          block $e
          block $19
          block $1c
          block $1d
            (br_table $X $1 $2 $tp $vt $tp $vt $vt $X $X  $vs $X $X  $X  $e $X
                      $X $X $X $X  $X  $X  $X  $X  $X $19 $X  $X $1c $1d $X
                      (local.get $effect))
          end $1d ;; note delay
            (br_if $X (i32.ne (local.get $param) (local.get $fx-count)))
            (call $trigger (local.get $channel))
            br $X
          end $1c ;; note cut
            (br_if $X (i32.ne (local.get $param) (local.get $fx-count)))
            (i32.store8 offset=34 (local.get $channel) (i32.const 0))  ;; volume
            br $X
          end $19 ;; retrigger
            (br_if $X (i32.lt_s (local.get $fx-count) (local.get $param)))
            (i32.store8 offset=39 (local.get $channel) (i32.const 0))  ;; fx-count
            (i32.store offset=12 (local.get $channel) (i32.const 0))   ;; sample-idx
            br $X
          end $e ;; arpeggio
            block $fx-arp-add (result i32)
            block $fx2
            block $fx1
            block $fx0
            block $fxN
              (br_table $fx0 $fx1 $fx2 $fxN (local.get $fx-count))
            end $fxN
              (i32.store8 offset=39 (local.get $channel) (i32.const 0))
              br $X
            end $fx0
              (br $fx-arp-add (i32.const 0))
            end $fx1
              (br $fx-arp-add (i32.shr_u (local.get $param) (i32.const 4)))
            end $fx2
              (br $fx-arp-add (i32.and (local.get $param) (i32.const 0xf)))
            end $fx-arp-add
              (i32.store8 offset=42 (local.get $channel) (; value ;))
            br $X
          end $2 ;; portamento down
            (local.set $param (local.get $-param))
            ;; fallthrough
          end $1 ;; portamento up
            (i32.store16 offset=24 (local.get $channel)
              (call $i32_clamp0_s
                (i32.sub
                  (i32.load16_u offset=24 (local.get $channel))
                  (local.get $param))
                (i32.const 65535)))))
            br $X

        ;; 3:tone portamento
        ;; 4:vibrato
        ;; 5:tone portamento + volume slide
        ;; 6:vibrato + volume slide
        ;; 7:tremolo
        ;; a:volume slide

        end $tp
          (local.set $source (i32.load16_u offset=24 (local.get $channel)))
          (local.set $dest (i32.load16_u offset=26 (local.get $channel)))
          (i32.store16 offset=24 (local.get $channel)
            (if (result i32) (i32.lt_s (local.get $source) (local.get $dest))
              (then
               (select
                  (local.get $dest)
                  (local.tee $source
                    (i32.add (local.get $source)
                            (i32.load8_u offset=37 (local.get $channel))))
                 (i32.gt_s (local.get $source) (local.get $dest))))
              (else
               (select
                  (local.get $dest)
                  (local.tee $source
                    (i32.sub (local.get $source)
                            (i32.load8_u offset=37 (local.get $channel))))
                 (i32.lt_s (local.get $source) (local.get $dest))))))
          br $vs
        end $vt ;; vibrato-tremolo
          (local.set $addr
            ;; difference between vibrato-type and tremolo-type
            (i32.add
              (local.get $channel)
              (i32.shl
                (local.tee $effect=7
                  (i32.eq (local.get $effect) (i32.const 7)))
                (i32.const 2))))
          (if (local.get $tick<0)
            (then
              (if (local.get $param-hi)
                (then
                  (i32.store8 offset=45 (local.get $channel) (local.get $param-hi))))
              (if (local.get $param-lo)
                (then
                  (i32.store8 offset=46 (local.get $channel) (local.get $param-lo)))))
            (else
              (i32.store8 offset=44 (local.get $addr)
                (i32.add
                  (i32.load8_u offset=44 (local.get $addr))
                  (i32.load8_u offset=45 (local.get $addr))))))
          (local.set $phase (i32.load8_u offset=44 (local.get $addr)))
          block $done
          block $0
          block $1
          block $2
          block $3
            (br_table $0 $1 $2 $3
              (i32.and
                (i32.load8_u offset=43 (local.get $addr))
                (i32.const 3)))
          end $3  ;; Random
            (local.set $amp
              (i32.sub (i32.shr_u (global.get $random-seed) (i32.const 20))
                       (i32.const 255)))
            (global.set $random-seed
              (i32.and
                (i32.add
                  (i32.mul
                    (global.get $random-seed)
                    (i32.const 65))
                  (i32.const 17))
                (i32.const 0x1FFFFFFF)))
            (br $done)
          end $2  ;; Square wave
            (local.set $amp
              (i32.sub
                (i32.const 255)
                (i32.shl
                  (i32.and (local.get $phase) (i32.const 0x20))
                  (i32.const 4))))
            (br $done)
          end $1   ;; Saw down
            (local.set $amp
              (i32.sub
                (i32.const 255)
                (i32.shl
                  (i32.and
                    (i32.add (local.get $phase) (i32.const 0x20))
                    (i32.const 0x3f))
                  (i32.const 3))))
            (br $done)
          end $0
          ;; TODO: sine
          end $done
          (i32.store8 offset=40
            ;; Use vibrato-add or tremolo-add
            (i32.add (local.get $addr) (local.get $effect=7))
            (i32.shr_u
              (i32.mul
                (local.get $amp)
                (i32.load8_u offset=46 (local.get $addr)))
              ;; Divide by 6 or 7 for vibrato or tremolo respectively.
              (i32.sub (i32.const 7) (local.get $effect=7))))
          ;; fallthrough
        end $vs
          (br_if $X
            (i32.or
              (i32.or
                (i32.lt_u (local.get $effect) (i32.const 5))
                ;; Can't use $effect=7 since it may not be set by the time we
                ;; get here.
                (i32.eq (local.get $effect (i32.const 7))))
              (local.get $tick<0)))
          (i32.store8 offset=34 (local.get $channel)
            (call $i32_clamp0_s
              (i32.sub
                (i32.add
                  (i32.load8_u offset=34 (local.get $channel))
                  (i32.shr_u (local.get $param) (i32.const 4)))
                (i32.and (local.get $param) (i32.const 0xf)))
              (i32.const 64)))
          ;; fallthrough
        end $X

        ;; update frequency
        (if (i32.or (i32.eqz (i32.eqz (local.get $effect)))
                    (local.get $tick<0))
          (then
            (local.set $period
              (select
                (i32.const 6848)
                (local.tee $period
                  (i32.add
                    (i32.shr_u
                      (local.tee $period
                        (i32.shr_u
                          (i32.mul
                            (i32.add
                              (i32.load16_u offset=24 (local.get $channel))    ;; period
                              (i32.load8_u offset=40 (local.get $channel)))    ;; vibrato_add
                            (i32.load16_u offset=0x95                          ;; arp_tuning
                              (i32.shl
                                (i32.load8_u offset=42 (local.get $channel))   ;; arpeggio_add
                                (i32.const 1))))
                          (i32.const 11)))
                      (i32.const 1))
                    (i32.and (local.get $period) (i32.const 1))))
                (i32.lt_u (local.get $period) (i32.const 14))))

            ;; set channel step
            (f32.store offset=16 (local.get $channel)
              (f32.div
                (f32.convert_i32_u
                  (i32.div_u (global.get $c2-rate) (local.get $period)))
                (f32.convert_i32_u (global.get $sample-rate))))

            ;; set channel amplitude
            (f32.store offset=20 (local.get $channel)
              (f32.mul
                (f32.mul
                  (f32.convert_i32_u
                    (call $i32_clamp0_s
                      (i32.add
                        (i32.load8_u offset=34 (local.get $channel))   ;; volume
                        (i32.load8_u offset=41 (local.get $channel)))  ;; tremolo_add
                      (i32.const 64)))
                  (global.get $gain))
                (f32.const 0.03125)))))
      (br_if $channel
        (i32.lt_u
          (local.tee $channel (i32.add (local.get $channel) (i32.const 52)))
          (local.get $channel-end))))
)

(func $trigger (param $channel i32)
  (local $ins i32)
  (local $instrument-ptr i32)
  (local $effect i32)
  (local $key i32)
  (local $period i32)

  (if $exit-if
    (i32.lt_u
      (i32.sub
        (local.tee $ins (i32.load8_u offset=30 (local.get $channel)))
        (i32.const 1))
      (i32.const 31))  ;; 0 < ins < 32
    (then
      (i32.store offset=4 (local.get $channel)                       ;; assigned
        ;; convert from instrument number to instrument offset
        (local.tee $instrument-ptr
          (i32.add (i32.mul (local.get $ins) (i32.const 14))
                   (i32.const 0xb5))))
      (i32.store offset=8 (local.get $channel) (i32.const 0))        ;; sample_offset
      ;; copy fine tune and volume
      (i32.store16 offset=33 (local.get $channel)
        (i32.load16_u offset=12 (local.get $instrument-ptr)))

      ;; set channel instrument if the loop length > 0 and the current instrument is != 0.
      (br_if $exit-if
        (i32.or
          (f32.le (f32.load offset=8 (local.get $instrument-ptr)) (f32.const 0))
          (i32.eqz (i32.load (local.get $channel)))))
      (i32.store (local.get $channel) (local.get $instrument-ptr))))

  (if (i32.eq
        (local.tee $effect (i32.load8_u offset=31 (local.get $channel)))
        (i32.const 9))
    (then
      ;; Handle effect 9, sample offset.
      (i32.store offset=8 (local.get $channel)
        (i32.shl (i32.load8_u offset=32 (local.get $channel)) (i32.const 8)))))
  (if (i32.eq (local.get $effect) (i32.const 0x15))
    (then
      ;; Handle effect 0x15, fine tuning.
      (i32.store8 offset=33 (local.get $channel)
        (i32.load8_u offset=32 (local.get $channel)))))

  ;; key is non-zero
  (br_if 0
    (i32.eqz (local.tee $key (i32.load16_u offset=28 (local.get $channel)))))

  ;; Set porta-period.
  (i32.store16 offset=26 (local.get $channel)
    (i32.add
      (i32.shr_u
        ;; Calculate period w/ fine-tuning.
        (local.tee $period
          (i32.shr_u
            (i32.mul
              (local.get $key)
              (i32.load16_u offset=0x75
                (i32.shl
                  (i32.and (i32.load8_u offset=33 (local.get $channel)) (i32.const 0xf))
                  (i32.const 1))))
            (i32.const 11)))
        (i32.const 1))
      (i32.and (local.get $period) (i32.const 1))))

  ;; If not tone-portamento...
  (br_if 0
    (i32.or (i32.eq (local.get $effect) (i32.const 3))
            (i32.eq (local.get $effect) (i32.const 5))))
  ;; Set instrument pointer to assigned instrument.
  (i32.store (local.get $channel) (i32.load offset=4 (local.get $channel)))
  ;; Set period to porta period.
  (i32.store16 offset=24 (local.get $channel)
    (i32.load16_u offset=26 (local.get $channel)))
  ;; Set sample offset to sample index.
  (f32.store offset=12 (local.get $channel)
    (f32.convert_i32_u (i32.load offset=8 (local.get $channel))))

  ;; If vibrato_type < 4, vibrato_phase = 0
  (if (i32.lt_u (i32.load8_u offset=43 (local.get $channel)) (i32.const 4))
    (then
      (i32.store8 offset=44 (local.get $channel) (i32.const 0))))
  ;; If tremolo_type < 4, tremolo_phase = 0
  (if (i32.lt_u (i32.load8_u offset=47 (local.get $channel)) (i32.const 4))
    (then
      (i32.store8 offset=48 (local.get $channel) (i32.const 0))))
)

(func (export "run") (param $count i32)
  (local $offset i32)
  (local $remain i32)
  (local $channel-idx i32)
  (local $channel i32)
  (local $buf-idx i32)
  (local $buf-idx*4 i32)
  (local $buf-end i32)
  (local $instrument-ptr i32)
  (local $sample-data i32)
  (local $sample-idx f32)
  (local $sample-end f32)
  (local $sample-step f32)
  (local $left-ampl f32)
  (local $right-ampl f32)
  (local $ampl f32)
  (local $panning f32)
  (local $loop-length f32)
  (local $loop-end f32)

  (memory.fill (i32.const 0x1000) (i32.const 0) (i32.const 0x8000))

  (loop $loop
    ;; calculate number of ticks to run
    (local.set $remain
      (call $i32_clamp0_s
        (i32.sub (global.get $tick-len) (global.get $tick-offset))
        (local.get $count)))

    (local.set $channel-idx (i32.const 0))
    (loop $channel
      ;; resample
      (local.set $buf-end
        (i32.add
          (local.tee $buf-idx (local.get $offset))
          (local.get $remain)))
      (local.set $sample-idx
        (f32.load offset=12
          (local.tee $channel
            (i32.add
              (i32.const 0x275)
              (i32.mul (local.get $channel-idx) (i32.const 52))))))
      (local.set $sample-step (f32.load offset=16 (local.get $channel)))
      (local.set $loop-end
        (f32.add
          (f32.load offset=4 (local.tee $instrument-ptr (i32.load (local.get $channel))))
          (local.tee $loop-length
            (f32.load offset=8 (local.get $instrument-ptr)))))
      ;; TODO: chan->mute
      (local.set $right-ampl
        (f32.mul
          (local.tee $panning
            (f32.div
              (f32.convert_i32_u (i32.load8_u offset=35 (local.get $channel)))
              (f32.const 127)))
          (local.tee $ampl (f32.load offset=20 (local.get $channel)))))
      (local.set $left-ampl
        (f32.mul
          (f32.sub (f32.const 1) (local.get $panning))
          (local.get $ampl)))

      (local.set $sample-data (i32.load (local.get $instrument-ptr)))

      (if $exit-buffer
        (i32.and
          (i32.lt_u (local.get $buf-idx) (local.get $buf-end))
          (i32.eqz (i32.eqz (local.get $instrument-ptr))))
        (then
          (loop $buffer
            ;; loop the sample idx
            (if (f32.ge (local.get $sample-idx) (local.get $loop-end))
              (then
                (if (f32.le (local.get $loop-length) (f32.const 1))
                  (then
                    (local.set $sample-idx (local.get $loop-end))
                    (br $exit-buffer)))

                ;; Subtract loop-length until within loop points.
                (loop $loop
                  (br_if $loop
                    (f32.ge
                      (local.tee $sample-idx
                        (f32.sub (local.get $sample-idx) (local.get $loop-length)))
                      (local.get $loop-end))))))

            ;; calculate sample end
            (local.set $sample-end
              (f32.min
                (f32.add
                  (local.get $sample-idx)
                  (f32.mul
                    (f32.convert_i32_u
                      (i32.sub (local.get $buf-end) (local.get $buf-idx)))
                    (local.get $sample-step)))
                (local.get $loop-end)))

            ;; write each sample
            (loop $sample
              (br_if $exit-buffer (i32.ge_u (local.get $buf-idx) (local.get $buf-end)))

              (f32.store offset=0xffc
                (local.tee $buf-idx*4
                  (i32.shl
                    (local.tee $buf-idx (i32.add (local.get $buf-idx) (i32.const 1)))
                    (i32.const 2)))
                (f32.add
                  (f32.load offset=0xffc (local.get $buf-idx*4))
                  (f32.mul
                    (local.get $right-ampl)
                    (local.tee $ampl
                      (f32.div
                        (f32.convert_i32_s
                          (i32.load8_s
                            (i32.add
                              (local.get $sample-data)
                              (i32.trunc_f32_u (local.get $sample-idx)))))
                        (f32.const 128))))))
              (f32.store offset=0x4ffc
                (local.get $buf-idx*4)
                (f32.add
                  (f32.load offset=0x4ffc (local.get $buf-idx*4))
                  (f32.mul (local.get $left-ampl) (local.get $ampl))))

              (br_if $sample
                (f32.lt
                  (local.tee $sample-idx
                    (f32.add (local.get $sample-idx) (local.get $sample-step)))
                  (local.get $sample-end))))

            ;; continue until the buffer is filled
            (br_if $buffer (i32.lt_u (local.get $buf-idx) (local.get $buf-end))))))

      ;; update sample index
      (f32.store offset=12 (local.get $channel) (local.get $sample-idx))

      (br_if $channel
        (i32.lt_u
          (local.tee $channel-idx (i32.add (local.get $channel-idx) (i32.const 1)))
          (global.get $num-channels))))

    ;; update tick offset, if needed then handle a sequence tick
    (global.set $tick-offset (i32.add (global.get $tick-offset) (local.get $remain)))
    (if (i32.eq (global.get $tick-offset) (global.get $tick-len))
      (then
        (call $sequence-tick)
        (global.set $tick-offset (i32.const 0))))

    ;; update offset, which region of the output buffer to fill.
    (local.set $offset (i32.add (local.get $offset) (local.get $remain)))
    (br_if $loop
      (i32.gt_s
        (local.tee $count (i32.sub (local.get $count) (local.get $remain)))
        (i32.const 0))))
)

(data (i32.const 0)
  ;; =0x0000 - channel table (59 bytes)
  (i8  2  1  3 20 10 30  5 22 12 32
       4 21 11 31  4  8  5  6 23 13
       7 29 19  4  6  5  9 26 16  7
       8  8  4  6  7 24 14  4  4  5
       8 28 18  7  8 25 15  6  9 27
       17 6  4  4  8  4  4  9  8)

  ;; =0x003b - assoc table (+33) (58 bytes)
  (i8 17 59 59 59 59 16 59 59 59 59
      59 59 59 29 59 19 17 59  1  0
       2 10  6 17 34 44 26 48 40 20
      59 59  1 59  1 37 16 18 59  0
       8 59 12 59  8  0 11 15  7  0
       8  7 59  8 59  7 59  7)

  ;; =0x0075 - fine tuning (32 bytes)
  (i16 4096 4067 4037 4008 3979 3951 3922 3894
       4340 4308 4277 4247 4216 4186 4156 4126)

  ;; =0x0095 - arp tuning (32 bytes)
  (i16 4096 3866 3649 3444 3251 3069 2896 2734
	     2580 2435 2299 2170 2048 1933 1825 1722)

  ;; =0x00b5 - instrument data (32 x 14 bytes = 448 bytes)
    ;;  0 i32 sample data offset
    ;;  4 f32 loop start
    ;;  8 f32 loop length
    ;; 12 s8  fine tune  [-8, 7]
    ;; 13 u8  volume     [0, 64]

  ;; =0x0275 - channel data (32 x 52 bytes = 1664 bytes)
    ;;  0 i32 instrument pointer
    ;;  4 i32 assigned instrument pointer

    ;;  8 u32 sample-offset
    ;; 12 f32 sample-idx
    ;; 16 f32 step
    ;; 20 f32 amplitude

    ;; 24 u16 period
    ;; 26 u16 porta-period
    ;; 28 u16 note-key

    ;; 30 u8  note-instrument
    ;; 31 u8  note-effect
    ;; 32 u8  note-param
    ;; 33 u8  fine-tune
    ;; 34 u8  volume
    ;; 35 u8  panning
    ;; 36 u8  id
    ;; 37 u8  porta-speed
    ;; 38 u8  pl-row

    ;; 39 u8  fx-count
    ;; 40 s8  vibrato-add
    ;; 41 s8  tremolo-add
    ;; 42 s8  arpeggio-add
    ;; 43 u8  vibrato-type
    ;; 44 u8  vibrato-phase
    ;; 45 u8  vibrato-speed
    ;; 46 u8  vibrato-depth
    ;; 47 u8  tremolo-type
    ;; 48 u8  tremolo-phase
    ;; 49 u8  tremolo-speed
    ;; 50 u8  tremolo-depth

  ;; =0x1000 - channel0 - f32 x 4096 samples
  ;; =0x5000 - channel1 - f32 x 4096 samples
  ;; =0x9000
)
