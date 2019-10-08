(func $start
  (local $i i32)
  (loop $loop
    (i32.store offset=0x4a (local.get $i) (i32.load (local.get $i)))
    (br_if $loop
      (i32.lt_u
        (local.tee $i (i32.add (local.get $i) (i32.const 4)))
        (i32.const 0x4a))))
)
(start $start)

(memory (export "") 1)
(data (i32.const 0)
  "\00\61\73\6d\01\00\00\00\01\04\01\60\00\00\03\02"
  "\01\00\05\03\01\00\01\07\04\01\00\02\00\08\01\00"
  "\0a\20\01\1e\01\01\7f\03\40\20\00\20\00\28\02\00"
  "\36\02\4a\20\00\41\04\6a\22\00\41\ca\00\49\0d\00"
  "\0b\0b\0b\50\01\00\41\00\0b\4a"
)
