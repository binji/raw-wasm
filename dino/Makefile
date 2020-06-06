.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wabt/bin/wat2wasm

dino.wasm: dino.wat
	$(wat2wasm) -o $@ $<
