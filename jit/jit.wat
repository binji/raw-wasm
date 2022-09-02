(import "" "compile" (func $compile (param i32)))
(memory (export "mem") 1)
(table (export "table") 1 funcref)

(func (export "gen") (result i32)
  (local $p i32)
  (local $d i32)
  (local $o i32)
  (local $count i32)
  (local $c i32)
  (local $op i32)
  (local $oval i32)

  block $error
  block $endparse
  loop $parse
    block $push block $op block $num
      (br_if $endparse
        (i32.eqz
          (local.tee $c
            (i32.load8_u offset=255
              (local.tee $p (i32.add (local.get $p) (i32.const 1)))))))

      (br_table
        $push $op $op $op $error $op $error $op
        $num $num $num $num $num $num $num $num $num $num
        $error
        (local.tee $op (i32.sub (local.get $c) (i32.const 0x28))))

    end $num
      (i32.store16 offset=45
        (local.tee $d (i32.add (local.get $d) (i32.const 2)))
        (i32.or
          (i32.shl (i32.sub (local.get $c) (i32.const 0x30)) (i32.const 8))
          (i32.const 0x41)))

      (local.set $count (i32.add (local.get $count) (i32.const 1)))
      br $parse

    end $op
      block $exit
        loop $pop
          (br_if $exit (i32.eqz (local.get $o)))
          (br_if $exit
            (i32.or
              (i32.eqz
                (local.tee $oval
                  (i32.load8_u offset=512 (i32.sub (local.get $o) (i32.const 1)))))
              (i32.lt_u
                (i32.load8_u (local.get $oval))
                (i32.load8_u (local.get $op)))))
          (br_if $error
            (i32.lt_s (local.tee $count (i32.sub (local.get $count) (i32.const 1)))
                      (i32.const 1)))
          (local.set $o (i32.sub (local.get $o) (i32.const 1)))
          (i32.store8 offset=46
            (local.tee $d (i32.add (local.get $d) (i32.const 1)))
            (i32.load8_u offset=8 (local.get $oval)))

          br $pop
        end
      end $exit
      ;; everything except rpar should push
      (br_if $push (i32.ne (local.get $op) (i32.const 1)))
      ;; error if the stack is empty (should have lpar)
      (br_if $error (i32.eqz (local.get $o)))
      ;; pop lpar
      (local.set $o (i32.sub (local.get $o) (i32.const 1)))
      br $parse

    end $push
      (i32.store8 offset=511
        (local.tee $o (i32.add (local.get $o) (i32.const 1)))
        (local.get $op))
      br $parse
  end
  end $endparse

  block $exit
    loop $pop
      (br_if $exit (i32.eqz (local.get $o)))
      (br_if $error
        (i32.lt_s (local.tee $count (i32.sub (local.get $count) (i32.const 1)))
                  (i32.const 1)))
      (i32.store8 offset=46
        (local.tee $d (i32.add (local.get $d) (i32.const 1)))
        (i32.load8_u offset=8
          (i32.load8_u offset=512
            (local.tee $o (i32.sub (local.get $o) (i32.const 1))))))
      br $pop
    end
  end

  ;;error if count != 1
  (br_if $error (i32.ne (local.get $count) (i32.const 1)))

  ;; write 'end' instruction
  (i32.store8 offset=47 (local.get $d) (i32.const 0xb))

  ;; write code section length
  (i32.store8 (i32.const 43) (i32.add (local.get $d) (i32.const 4)))

  ;; write function length
  (i32.store8 (i32.const 45) (i32.add (local.get $d) (i32.const 2)))

  (call $compile (i32.add (local.get $d) (i32.const 32)))
  (return (i32.const 1))

  end $error
  (i32.const 0)
)

(func (export "call") (result i32)
  (call_indirect (result i32) (i32.const 0))
)

(data (i32.const 0)
  ;; 0  1  2  3  4  5  6  7
  ;; (  )  *  +  ,  -  .  /
  ;; x  0  2  1  x  1  x  2
  "\00\00\02\01\00\01\00\02"  ;; precedence
  "\00\00\6c\6a\00\6b\00\6d"  ;; wasm op

  "\00\61\73\6d\01\00\00\00"  ;; magic/version
  "\01\05\01\60\00\01\7f"     ;; type: func () -> i32
  "\03\02\01\00"              ;; func: type 0
  "\07\05\01\01\30\00\00"     ;; export: func 0 -> "0"
  "\0a\ff\01\ff\00"
)
