.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wabt/bin/wat2wasm

metaball.wasm: metaball.wat
	$(wat2wasm) -o $@ $<
