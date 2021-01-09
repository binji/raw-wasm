const fs = require('fs');
const buffer = fs.readFileSync('inflate.wasm');
const mod = new WebAssembly.Module(buffer);
const instance = new WebAssembly.Instance(mod);

const arrbuf = instance.exports.mem.buffer;
const u8buf = new Uint8Array(arrbuf, 167);

instance.exports.inflate();
