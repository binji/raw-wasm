.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wasp/wasp wat2wasm --enable-numeric-values

mod.wasm: mod.wat
	$(wat2wasm) -o $@ $<
