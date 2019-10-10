# Raw WebAssembly Demos

## Quine

A little WebAssembly [quine][9]. Without a way to do output, I decided that a
WebAssembly quine should export a memory object with a copy its bytes. [**148 bytes**]

[Demo!][10]

## Doomfire

An implementation of the Doom fire effect described in
[Fabien Sanglard's blog][1], using hand-written WebAssembly. [**398 bytes**]

[Demo!][2]

## Metaball

An implementation of the metaball effect described in [Jamie Wong's blog][3],
using hand-written WebAssembly. Unlike the implementation described there, this
just updates every pixel. [**452 bytes**]

[Demo!][4]

## Raytrace

A simple raytracer, using techniques from [tinyraytracer][5], in hand-written
WebAssembly. 4 spheres, 1 light, reflections, and shadows. [**1486 bytes**]

[Demo!][6]

## Snake

A snake-eats-the-dots game, but with 360° rotation. Use left and right arrow
keys, or tap on the left or right side of the screen to turn. [**1976 bytes**]

[Demo!][7]

## Maze

A Wolfenstein-style 3d maze race. Each ray is tested against all walls,
brute-force style. Walls, floors and ceilings are textured. Palettes are made
up of 120-levels of brightness, which fade into black in the distance. [**2184 bytes**]

[Demo!][8]

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
