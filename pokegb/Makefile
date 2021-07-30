.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wasp/wasp wat2wasm --enable-numeric-values --enable-sign-extension

pokegb.wasm: pokegb.wat
	$(wat2wasm) -o $@ $<
