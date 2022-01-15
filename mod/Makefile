.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wasp/wasp wat2wasm --enable-numeric-values --enable-bulk-memory

mod.wasm: mod.wat
	$(wat2wasm) -o $@ $<
