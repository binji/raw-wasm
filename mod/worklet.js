const MAX_FRAMES = 4096;

class Player extends AudioWorkletProcessor {
  constructor(options) {
    super(options)

    this.mem = null;
    this.run = null;
    this.channels = null;
    this.playing = false;
    this.sampleRate = options.processorOptions.sampleRate;
    this.module = options.processorOptions.module;
    this.port.onmessage = this.onmessage.bind(this);
  }

  onmessage(event) {
    switch (event.data.msg) {
      case 'load':
        this.load(event.data.file);
        break;

      case 'play':
        this.playing = event.data.value;
        break;
    }
  }

  async load(file) {
    this.mem =
      new WebAssembly.Memory({initial: 1 + Math.ceil(file.byteLength / 65536)});
    this.channels = [
      new Float32Array(this.mem.buffer, 0x1000, MAX_FRAMES),
      new Float32Array(this.mem.buffer, 0x1000 + MAX_FRAMES*4, MAX_FRAMES),
    ];
    (new Uint8Array(this.mem.buffer, 0x10000)).set(new Uint8Array(file));

    const imports = {'': {
      rate: sampleRate,
      init: channels => this.port.postMessage({msg: 'init', channels}),
      draw: (pattern, row) => this.port.postMessage({msg: 'draw', pattern, row}),
      mem: this.mem,
      // log: x => console.log(x.toString(16)),
    }};

    const instance = await WebAssembly.instantiate(this.module, imports);
    this.run = instance.exports.run;
  }

  process(inputs, outputs, params) {
    if (this.run && this.playing) {
      const output = outputs[0];
      let offset = 0;
      let length = output[0].length;
      while (offset < length) {
        const frames = Math.min(output[0].length, MAX_FRAMES);
        this.run(frames);
        for (let i = 0; i < output.length; ++i) {
          output[i].set(this.channels[i].subarray(0, frames), offset);
        }
        offset += frames;
      }
    }
    return true;
  }
}

registerProcessor('player', Player);
