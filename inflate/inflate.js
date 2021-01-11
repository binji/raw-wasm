const fs = require('fs');
const buffer = fs.readFileSync('inflate.wasm');
const mod = new WebAssembly.Module(buffer);
const instance = new WebAssembly.Instance(mod);

const arrbuf = instance.exports.mem.buffer;
const u8arr = new Uint8Array(arrbuf);
const u16arr = new Uint16Array(arrbuf);

const end = instance.exports.inflate();
console.log(end);

// console.log(u8arr.slice(0, 0 + 318));
// console.log(u8arr.slice(382, 382 + 32));
// console.log(u16arr.slice(414>>1, (414>>1) + 318));
console.log(u8arr.slice(3000, end).reduce((p,c)=>p+String.fromCharCode(c),''));
