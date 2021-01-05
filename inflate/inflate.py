#!/usr/bin/env python

import argparse
import struct
import sys

MAXBITS = 15
MAXCLCODES = 19
MAXLCODES = 286
MAXDCODES = 30
FIXLCODES = 288

FIXED_LIT_LENS = [8] * 144 + [9] * 112 + [7] * 24 + [8] * 8
FIXED_DIST_LENS = [5] * 32
CODELEN_LITS = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]


def LengthBase(i):
  if i < 4: base = 1
  elif i >= 28: base = 2
  else: base = 3
  base += (i & 3) * (1 << ExtraLengthBits(i)) + (1 << ((i + 4) >> 2))
  return base


def ExtraLengthBits(code):
  return max(0, (code - 4) >> 2) if code < 28 else 0


def DistBase(i):
  if i < 2: base = 0
  else: base = 1
  base += (i & 1) * (1 << ExtraDistBits(i)) + (1 << (i >> 1))
  return base


def ExtraDistBits(code):
  return max(0, (code - 2) >> 1)


class Huffman(object):
  def __init__(self, lens, maxsyms):
    # build count
    self.count = [0] * MAXBITS
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
      elif code == 256:
        break
      else:
        lextra = self.ReadBits(ExtraLengthBits(code - 257))
        length = LengthBase(code - 257) + lextra
        dcode = self.ReadCode(dist_huff)
        dextra = self.ReadBits(ExtraDistBits(dcode))
        dist = DistBase(dcode) + dextra
        for i in range(length):
          self.output.append(self.output[-dist])

    return not bfinal

  def ReadCode(self, huffman):
    code = 0
    first = 0
    index = 0
    for i in range(1, MAXBITS+1):
      code |= self.ReadBits(1)
      count = huffman.count[i]
      if code - count < first:
        return huffman.symbol[index + (code - first)] 
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
  print('output', output)
  print('len', len(output))

if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
