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
  width, height = map(int, data[2].split())
  data = map(int, data[4:])

  # Convert colors into tuples of (R, G, B)
  data = groupinto(data, 3)

  # Extra colors into a palette
  colors = list(set(data))
  # Sort colors so white is first.
  colors.sort(reverse=True)
  assert(len(colors) <= 4)

  # Map pixel data to palette index
  data = [colors.index(x) for x in data]

  # Group pixel data into groups of 8
  data = groupinto(data, 8)

  # Convert pixel data into 1bpp
  data = [combine(x, 1) for x in data]

  # Convert data into wasm data string format, split into 24 byte chunks
  data = ''.join(('"%s"\n' % ''.join(wasm(j) for j in data[i:i+24]))
                 for i in range(0, len(data), 24))
  # Convert colors into ABGR format, each byte separate
  colors = [channel for color in colors
                    for channel in list(color) + [0xff]]

  # Convert colors into wasm data string format
  colors = '"%s"' % ''.join(wasm(x) for x in colors)

  print(';; %s %d %d\n%s' % (args.file, width, height, data))
  print(';; colors\n' + colors)

if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
