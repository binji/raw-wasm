.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wabt/bin/wat2wasm

quine.wasm: quine.wat
	$(wat2wasm) -o $@ $<
