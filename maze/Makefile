.SUFFIXES:

wat2wasm = /home/binji/dev/wasm/wabt/bin/wat2wasm

maze.wasm: maze.wat
	$(wat2wasm) -o $@ $<
