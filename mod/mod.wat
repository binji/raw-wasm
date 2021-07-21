;; Memory map:
;;
;; [0x1000 .. ??????]  mod file data
;; [0x1000 .. 0x1013]  mod file name
;; [0x1014 .. 0x13b5]  sample info (31 samples)
;; [0x13b8 .. 0x1437]  sequence (up to 128 orders)
;; [0x1438 .. 0x143b]  signature
;; [0x143c .. ??????]  pattern data

(import "" "rate" (global $sample-rate i32))
(import "" "log" (func $log (param i32)))
(import "" "mem" (memory 1))
(global $num-channels (mut i32) (i32.const 0))
(global $num-patterns (mut i32) (i32.const 0))
(global $tick-len (mut i32) (i32.const 6))
(global $tick-offset (mut i32) (i32.const 0))

(func $read16be_2x (param $addr i32) (result i32)
  (i32.shl
    (i32.or
      (i32.shl (i32.load8_u (local.get $addr)) (i32.const 8))
      (i32.load8_u offset=1 (local.get $addr)))
    (i32.const 1))
)

(func $start
  ;; calculate number of channels
  (local $channel i32)
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

  (call $log (global.get $num-patterns))
  (call $log (global.get $num-channels))

  ;; calculate sample info
  (local.set $sample-data (i32.add (i32.const 0x1043c)
                                   (i32.mul
                                     (i32.mul (global.get $num-patterns)
                                              (global.get $num-channels))
                                     (i32.const 256))))
  (local.set $i (i32.const 0x1001e))
  (local.set $j (i32.const 0x75))
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
    (i32.store offset=4 (local.get $j) (local.get $sample-length))
    (f32.store offset=8 (local.get $j) (f32.convert_i32_u (i32.add (local.get $loop-start) (local.get $loop-length))))
    (f32.store offset=12 (local.get $j) (f32.convert_i32_u (local.get $loop-length)))

    (local.set $sample-data (i32.add (local.get $sample-data) (local.get $sample-length)))
    (local.set $j (i32.add (local.get $j) (i32.const 20)))
    (br_if $loop (i32.lt_u (local.tee $i (i32.add (local.get $i) (i32.const 30)))
                           (i32.const 0x103a2))))

  (global.set $tick-len (i32.div_u (i32.mul (global.get $sample-rate) (i32.const 5))
                                   (i32.shl (global.get $sample-rate) (i32.const 1))))
)
(start $start)

(func (export "run") (param $count i32)
  (local $offset i32)
  (local $remain i32)
  (local $channel i32)
  (local $buf-idx i32)
  (local $buf-idx*4 i32)
  (local $buf-end i32)
  (local $sample-info i32)
  (local $sample-idx f32)
  (local $sample-end f32)
  (local $sample-step f32)
  (local $left-ampl f32)
  (local $right-ampl f32)
  (local $ampl f32)
  (local $loop-length f32)
  (local $loop-end f32)

  (loop $loop
    ;; calculate number of ticks to run
    (local.set $remain
      (select
        (local.get $count)
        (local.tee $remain (i32.sub (global.get $tick-len) (global.get $tick-offset)))
        (i32.gt_u (local.get $remain) (local.get $count))))

    (loop $channel
      ;; resample
      (local.set $buf-idx (local.get $offset))
      (local.set $buf-end (i32.add (local.get $buf-idx) (local.get $remain)))
      (local.set $loop-end (f32.load offset=4 (local.tee $sample-info (i32.load (local.get $channel)))))
      (local.set $loop-length (f32.load offset=8 (local.get $sample-info)))
      (local.set $sample-idx (f32.load offset=4 (local.get $channel)))
      (local.set $sample-step (f32.load offset=8 (local.get $channel)))
      (local.set $left-ampl (f32.load offset=12 (local.get $channel)))
      (local.set $right-ampl (f32.load offset=16 (local.get $channel)))

      (loop $buffer
        ;; loop the sample idx
        ;; TODO: Seems like I should be able to use mod here....

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
          (local.set $ampl (f32.div (f32.convert_i32_s (i32.load8_s (i32.trunc_f32_u (local.get $sample-idx)))) (f32.const 128)))
          (local.set $buf-idx*4 (i32.shl (local.get $buf-idx) (i32.const 4)))
          (f32.store offset=0x1000 (local.get $buf-idx*4) (f32.add (f32.load offset=0x1000 (local.get $buf-idx*4)) (f32.mul (local.get $right-ampl) (local.get $ampl))))
          (f32.store offset=0x5000 (local.get $buf-idx*4) (f32.add (f32.load offset=0x5000 (local.get $buf-idx*4)) (f32.mul (local.get $left-ampl) (local.get $ampl))))

          (local.set $buf-idx (i32.add (local.get $buf-idx) (i32.const 1)))
          (br_if $sample (f32.le (local.tee $sample-idx (f32.add (local.get $sample-idx) (local.get $sample-step)))
                                 (local.get $sample-end))))

        ;; continue until the buffer is filled
        (br_if $buffer (i32.lt_u (local.get $buf-idx) (local.get $buf-end))))

      ;; update sample index
      (f32.store offset=4 (local.get $sample-idx))

      (br_if $channel (i32.lt_u (local.tee $channel (i32.add (local.get $channel) (i32.const 20)))
                                (i32.mul (global.get $num-channels) (i32.const 20)))))

    ;; update tick offset, if needed then handle a sequence tick
    (global.set $tick-offset (i32.add (global.get $tick-offset) (local.get $remain)))
    (if (i32.eq (global.get $tick-offset) (global.get $tick-len))
      (then
        ;; sequence_tick
        (global.set $tick-offset (i32.const 0))))

    ;; update offset, which region of the output buffer to fill.
    (local.set $offset (i32.add (local.get $offset) (local.get $remain)))
    (br_if $loop (local.tee $count (i32.sub (local.get $count) (local.get $remain)))))
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

  ;; =0x0075 - sample data (31 x 8 bytes = 248 bytes)
    ;; i32 sample data offset
    ;; i32 sample length
    ;; f32 loop end
    ;; f32 loop length

  ;; =0x016d - channel data (32 x 20 bytes = 640 bytes)
    ;; i32 sample info pointer
    ;; f32 sample index (into sample data buffer)
    ;; f32 step
    ;; f32 left amplitude
    ;; f32 right amplitude
    ;; TODO

  ;; =0x1000 - channel0 - f32 x 4096 samples
  ;; =0x5000 - channel1 - f32 x 4096 samples
  ;; =0x9000
)
