.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wabt/bin/wat2wasm

chip8.wasm: chip8.wat
	$(wat2wasm) -o $@ $<
