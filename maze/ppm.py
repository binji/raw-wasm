#!/usr/bin/env python2

import argparse
import struct
import sys

def main(args):
  parser = argparse.ArgumentParser()
  parser.add_argument('file')
  args = parser.parse_args(args)

  groupinto = lambda l, n: [tuple(l[i:i+n]) for i in range(0, len(l), n)]
  combine = lambda l, shift: reduce(lambda x,y: (x<<shift)|y, l[::-1], 0)
  wasm = lambda b: ('\\%02x' % (b))

  data = open(args.file).readlines()
  # Not gonna be super robust here...
  # Assume the first four lines are:
  #    P3
  #    # Comment from GIMP
  #    <width> <height>
  #    <max color>
  #    <actual data, one byte per line>
  data = map(int, data[4:])

  # Convert colors into tuples of (R, G, B)
  data = groupinto(data, 3)

  # Extra colors into a palette
  colors = list(set(data))
  assert(len(colors) <= 4)

  # Map pixel data to palette index
  data = [colors.index(x) for x in data]

  # Group pixel data into groups of 4
  data = groupinto(data, 4)

  # Convert pixel data into 2bpp
  data = [combine(x, 2) for x in data]

  # Get run lengths, data = [(count, value),...]
  new_data = [[1, data[0]]]
  for x in data[1:]:
    if x == new_data[-1][1]:
      new_data[-1][0] += 1
    else:
      new_data.append([1, x])
  data = new_data

  # Encode runs:
  #  v**n        => (+n, v)
  #  v1,v2,..,vn => (-n, v1, v2,..,vn)
  new_data = []
  for x in data:
    if x[0] == 1:
      if new_data and new_data[-1][0] < 0:
        new_data[-1][0] -= 1
        new_data[-1].append(x[1])
      else:
        new_data.append([-1, x[1]])
    else:
      # Make sure run length is s8
      assert x[0] < 128
      new_data.append(x)
  data = new_data

  # Flatten data, and convert negative numbers to two's complement.
  data = [(x+256)&255 for l in data for x in l]

  # Convert data into wasm data string format, split into 24 byte chunks
  data = ''.join(('"%s"\n' % ''.join(wasm(j) for j in data[i:i+24]))
                 for i in range(0, len(data), 24))
  # Convert colors into ABGR format, each byte separate
  colors = [channel for color in colors
                    for channel in list(color) + [0xff]]

  # Convert colors into wasm data string format
  colors = '"%s"' % ''.join(wasm(x) for x in colors)

  print(';; pixel data\n' + data)
  print(';; palette data\n' + colors)

if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
