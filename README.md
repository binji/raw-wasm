# Raw WebAssembly Demos

## Quine

A little WebAssembly [quine][9]. Without a way to do output, I decided that a
WebAssembly quine should export a memory object with a copy its bytes. [**148 bytes**]

[Demo!][10]

## Doomfire

An implementation of the Doom fire effect described in
[Fabien Sanglard's blog][1], using hand-written WebAssembly. [**398 bytes**]

[Demo!][2]

## JIT

A *very* simple expression compiler using the [Shunting Yard algorithm][23].
It parses an infix expression, compiles it to WebAssembly, then copies
the generated function into the original WebAssembly module. [**449 bytes**]

[Demo!][24]

## Metaball

An implementation of the metaball effect described in [Jamie Wong's blog][3],
using hand-written WebAssembly. Unlike the implementation described there, this
just updates every pixel. [**452 bytes**]

[Demo!][4]

## Inflate

An implementation of the INFLATE algorithm, as specified in [RFC1951][17]. It
uses some tricks from [Piotr Fusik's 6502 implementation][18], such as storing
the literal and distance huffman trees in the same array, and programmatically
calculating the length/distance encoding rather than using tables. [**991 bytes**]

[Demo!][19]

## Chip-8

A [CHIP-8 interpreter][11], with support for the original chip-8 instruction
set. It starts up with a simple demo I wrote (thanks, [Octo][15]!). You can
also try some of the public domain games and demos at [dmatlack/chip8][12] and
the [CHIP-8 archive][13]. [**1020 bytes**]

[Demo!][14]

## Raytrace

A simple raytracer, using techniques from [tinyraytracer][5], in hand-written
WebAssembly. 4 spheres, 1 light, reflections, and shadows. [**1486 bytes**]

[Demo!][6]

## Snake

A snake-eats-the-dots game, but with 360° rotation. Use left and right arrow
keys, or tap on the left or right side of the screen to turn. [**1976 bytes**]

[Demo!][7]

## Dino

A dinosaur endlessly running through the desert, jumping over cacti and
pterodactyls. Graphics are compressed using a LZ77-like algorithm. [**2020 bytes**]

[Demo!][16]

## Maze

A Wolfenstein-style 3d maze race. Each ray is tested against all walls,
brute-force style. Walls, floors and ceilings are textured. Palettes are made
up of 120-levels of brightness, which fade into black in the distance. [**2047 bytes**]

[Demo!][8]

## Match3

An implementation of a [match 3][20]-style game, with an 8x8 grid and 8
different emojis. [**2662 bytes**]

[Demo!][21]

## BadGB

A very simple gameboy emulator that only plays a few games. [**3072 bytes**]

[Demo!][22]

[1]: http://fabiensanglard.net/doom_fire_psx/index.html
[2]: https://binji.github.io/raw-wasm/doomfire
[3]: http://jamie-wong.com/2014/08/19/metaballs-and-marching-squares/
[4]: https://binji.github.io/raw-wasm/metaball
[5]: https://github.com/ssloy/tinyraytracer/wiki/Part-1:-understandable-raytracing
[6]: https://binji.github.io/raw-wasm/raytrace
[7]: https://binji.github.io/raw-wasm/snake
[8]: https://binji.github.io/raw-wasm/maze
[9]: https://en.wikipedia.org/wiki/Quine_(computing)
[10]: https://binji.github.io/raw-wasm/quine
[11]: https://en.wikipedia.org/wiki/CHIP-8
[12]: https://github.com/dmatlack/chip8/tree/master/roms
[13]: https://johnearnest.github.io/chip8Archive/?sort=platform
[14]: https://binji.github.io/raw-wasm/chip8
[15]: http://johnearnest.github.io/Octo
[16]: https://binji.github.io/raw-wasm/dino
[17]: https://tools.ietf.org/html/rfc1951
[18]: https://github.com/pfusik/zlib6502
[19]: https://binji.github.io/raw-wasm/inflate
[20]: https://en.wikipedia.org/?title=Match-3&redirect=no
[21]: https://binji.github.io/raw-wasm/match3
[22]: https://binji.github.io/raw-wasm/badgb
[23]: https://en.wikipedia.org/wiki/Shunting_yard_algorithm
[24]: https://binji.github.io/raw-wasm/jit
