const fs = require('fs');
const buffer = fs.readFileSync('inflate.wasm');
const mod = new WebAssembly.Module(buffer);
const instance = new WebAssembly.Instance(mod);

const arrbuf = instance.exports.mem.buffer;
const u8arr = new Uint8Array(arrbuf);

const examples = [
  {name:'alice.gz', skip:16},
  {name:'tm.txt.gz', skip:17},
  {name:'inflate.wat.gz', skip:22},
  {name:'fixed.gz', skip:19},
];

const example = examples[0];
const gzip = fs.readFileSync(example.name);
const skip = example.skip;  // skip gzip header
const src = 2000;
const dst = 2000 + gzip.byteLength;

u8arr.set(gzip.slice(skip), src);

const dstend = instance.exports.inflate(src, dst);
console.log(u8arr.slice(dst, dstend).reduce((p,c)=>p+String.fromCharCode(c),''));
// console.log(u8arr.slice(dst, dstend));
