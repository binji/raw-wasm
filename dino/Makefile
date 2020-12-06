.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wasp/wasp wat2wasm --enable-numeric-values

dino.wasm: dino.wat
	$(wat2wasm) -o $@ $<
