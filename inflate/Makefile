.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wasp/wasp wat2wasm --enable-numeric-values

inflate.wasm: inflate.wat
	$(wat2wasm) -o $@ $<
