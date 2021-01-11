#!/usr/bin/env python

import argparse
import sys

MAXBITS = 15
MAXCLCODES = 19
MAXLCODES = 286
MAXDCODES = 30
FIXLCODES = 288

FIXED_LIT_LENS = [8] * 144 + [9] * 112 + [7] * 24 + [8] * 8
FIXED_DIST_LENS = [5] * 32
CODELEN_LITS = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
LENGTH_BASE = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
DIST_BASE = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
EXTRA_LENGTH_BITS = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
EXTRA_DIST_BITS = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]


class Huffman(object):
  def __init__(self, lens, maxsyms):
    # build count
    self.count = [0] * (MAXBITS+1)
    for l in lens:
      self.count[l] += 1

    # build offset
    offs = [0, 0]
    for i in range(1, MAXBITS):
      offs.append(offs[i] + self.count[i])

    # build code -> symbol
    self.symbol = [0] * maxsyms
    for i, l in enumerate(lens):
      if l != 0:
        self.symbol[offs[l]] = i
        offs[l] += 1


class Inflater(object):
  def __init__(self, data):
    self.input = data + b'\0\0'  # So we can read a little past the end
    # gzip header
    assert(self.input[0] == 0x1f)
    assert(self.input[1] == 0x8b)
    assert(self.input[2] == 0x08)

    flags = self.input[3]
    has_text = (flags & 1) != 0
    has_crc16 = (flags & 2) != 0
    has_extra = (flags & 4) != 0
    has_name = (flags & 8) != 0
    has_comment = (flags & 0x10) != 0

    assert(not has_text)
    assert(not has_crc16)
    assert(not has_extra)
    assert(not has_comment)

    self.bit_idx = 80  # After the header

    if has_name:
      while self.input[self.bit_idx // 8] != 0:
        self.bit_idx += 8
      self.bit_idx += 8

    self.output = []

  def Inflate(self):
    while self.ReadBlock():
      pass
    return self.output

  def ReadBits(self, n):
    byte_idx = self.bit_idx // 8
    bit_idx = self.bit_idx & 7
    data = self.input[byte_idx]
    data |= self.input[byte_idx + 1] << 8
    data |= self.input[byte_idx + 2] << 16
    data >>= bit_idx
    data &= ((1 << n) - 1)
    self.bit_idx += n
    # print(f'ReadBits({n}) => {data}')
    return data

  def ReadBlock(self):
    bfinal = self.ReadBits(1)
    btype = self.ReadBits(2)

    if btype == 0:  # uncompressed
      self.bit_idx = (self.bit_idx + 7) & ~7  # align
      len_ = self.ReadBits(16)
      nlen_ = self.ReadBits(16)
      self.output.extend(self.input[0:len_])
      self.bit_idx += len_ * 8
      return not bfinal
    elif btype == 1:  # fixed huffman
      lit_huff  = Huffman(FIXED_LIT_LENS, FIXLCODES)
      dist_huff = Huffman(FIXED_DIST_LENS, MAXDCODES)
    elif btype == 2:  # dynamic huffman
      hlit = self.ReadBits(5) + 257
      hdist = self.ReadBits(5) + 1
      hclen = self.ReadBits(4) + 4
      lens = [0] * MAXCLCODES
      for i in range(hclen):
        lens[CODELEN_LITS[i]] = self.ReadBits(3)
      codelen_huff = Huffman(lens, MAXCLCODES)

      lits_dists = self.ReadCodeLens(codelen_huff, hlit + hdist)
      lit_huff = Huffman(lits_dists[:hlit], MAXLCODES)
      dist_huff = Huffman(lits_dists[hlit:], MAXDCODES)
    else:  # reserved
      assert(False)

    while True:
      code = self.ReadCode(lit_huff)
      if code < 256:
        self.output.append(code)
        print(f'>> Output ({repr(chr(code))})')
      elif code == 256:
        print(f'>> Stop')
        break
      else:
        lextra = self.ReadBits(EXTRA_LENGTH_BITS[code - 257])
        length = LENGTH_BASE[code - 257] + lextra
        dcode = self.ReadCode(dist_huff)
        dextra = self.ReadBits(EXTRA_DIST_BITS[dcode])
        dist = DIST_BASE[dcode] + dextra
        for i in range(length):
          self.output.append(self.output[-dist])
        print(f">> Ref ({dist}, {length}) = {repr(''.join(map(chr, self.output[-length:])))}")

    return not bfinal

  def ReadCode(self, huffman):
    code = 0
    first = 0
    index = 0
    for i in range(1, MAXBITS+1):
      code |= self.ReadBits(1)
      count = huffman.count[i]
      if code - count < first:
        sym = huffman.symbol[index + (code - first)]
        # print(f'ReadCode() => {sym} ({repr(chr(sym))})')
        return sym
      index += count
      first += count
      first <<= 1
      code <<= 1
    raise Exception('Unknown code!')

  def ReadCodeLens(self, huffman, count):
    res = []
    while len(res) < count:
      x = self.ReadCode(huffman)
      if x < 16:
        res.append(x)
        continue
      elif x == 16:
        rep_val = res[-1]
        rep_cnt = 3 + self.ReadBits(2)
      elif x == 17:
        rep_val = 0
        rep_cnt = 3 + self.ReadBits(3)
      elif x == 18:
        rep_val = 0
        rep_cnt = 11 + self.ReadBits(7)

      res += [rep_val] * rep_cnt
    return res


def main(args):
  parser = argparse.ArgumentParser()
  parser.add_argument('file')
  args = parser.parse_args(args)

  inflater = Inflater(open(args.file, 'rb').read())
  output = ''.join(map(chr, inflater.Inflate()))
  # print('output', output)
  # print('len', len(output))

if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
