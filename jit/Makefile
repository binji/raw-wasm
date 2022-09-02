.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wabt/bin/wat2wasm

jit.wasm: jit.wat
	$(wat2wasm) -o $@ $<
