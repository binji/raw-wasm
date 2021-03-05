.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wasp/wasp wat2wasm --enable-numeric-values

match3.wasm: match3.wat
	$(wat2wasm) -o $@ $<
