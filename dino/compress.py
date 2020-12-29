#!/usr/bin/env python2

import argparse
import heapq
import collections
import struct
import sys

min_match = 10
max_run = 15
max_dist = 512
use_len_huffman = False

groupinto = lambda l, n: [tuple(l[i:i+n]) for i in range(0, len(l), n)]
combine = lambda l, shift: reduce(lambda x,y: (x<<shift)|y, l[::-1], 0)
wasm = lambda b: ('\\%02x' % (b))
padz = lambda l, s: '0' * (l - len(s)) + s
padbin = lambda l, n: padz(l, bin(n)[2:])
tobits = lambda l, n: map(int, bin(n)[2:])[::-1] + ([0] * (l - len(bin(n)) + 2))
tobytes = lambda data: [combine(x, 1) for x in groupinto(data, 8)]

def read_file(f):

  data = open(f).readlines()
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
  return [colors.index(x) for x in data]


class Node(object):
  def __init__(self, key, l=None, r=None):
    self.key = key
    self.l = l
    self.r = r

def make_huffman(dic):
  if len(dic) == 0: return {}

  heap = []
  for key, count in dic.iteritems():
    heapq.heappush(heap, (count, Node(key)))

  while len(heap) >= 2:
    count1, node1 = heapq.heappop(heap)
    count2, node2 = heapq.heappop(heap)
    heapq.heappush(heap, (count1 + count2, Node(None, node1, node2)))

  # Decode huffman into encoding dict
  result = {}
  def Build(node, cur):
    if node.key is not None:
      result[node.key] = cur
    else:
      assert(node.l is not None and node.r is not None)
      Build(node.l, cur + '0')
      Build(node.r, cur + '1')

  Build(heap[0][1], '')

  # Canonicalize huffman encoding
  max_len = max(len(code) for code in result.values()) + 1
  lens = [[] for _ in range(max_len)]
  for key, code in result.iteritems():
    lens[len(code)].append(key)

  # print([(i, len(x)) for i, x in enumerate(lens)])

  result = {}
  code = 0
  for l, keys in enumerate(lens):
    for key in keys:
      result[key] = padbin(l, code)
      # print('%s=>%s' % (key, result[key]))
      code += 1
    code <<= 1

  return result

def align_byte(n):
  return (n + 7) & ~7

def huffman_cost(huff):
  max_len = max(len(code) for code in huff.values()) + 1
  lens = [0] * max_len
  for key, code in huff.iteritems():
    lens[len(code)] += 1

  sums = [0]
  for l in lens:
    sums.append(sums[-1] + l)
  sums = sums[1:]

  keybits = log2(max([-key for key in huff.keys()] + huff.keys())) + 1
  sumbits = log2(max(sums)) + 7

  # keybits = align_byte(keybits)
  # sumbits = align_byte(sumbits)
  return len(huff) * keybits + len(sums) * (sumbits * 2)


def lz77(runs):
  # Find repeated patterns
  pattern_def = {}
  result = runs[:]
  for l in range(min_match, len(runs)):
    found = False
    for i in range(len(runs) - l):
      pattern = tuple(runs[i:i+l])
      if pattern in pattern_def:
        dist = pattern_def[pattern] - i
        if dist > -max_dist:
          found = True
          result[i] = (dist, len(pattern))

      pattern_def[pattern] = i

    if not found:
      break

  # Determine path that uses the most patterns
  score = [0] * (len(runs) + 1)
  back = [0] * (len(runs) + 1)
  for i, value in enumerate(result):
    if type(value) is tuple:
      l = value[1]
      if score[i] + l > score[i + l]:
        score[i + l] = score[i] + l
        back[i + l] = i
    elif score[i] > score[i + 1]:
      score[i + 1] = score[i]
      back[i + 1] = i

  # Reconstruct path
  final = [None] * len(runs)
  next = len(runs)
  while back[next] != 0:
    next = back[next]
    final[next] = result[next]
  for i in range(next):
    final[i] = result[i]

  # Remove Nones
  new_final = []
  for val in final:
    if val is not None:
      new_final.append(val)

  print('original (%d items) %s\n' % (len(runs), runs))
  print('compressed (%d items) %s\n' % (len(new_final), new_final))

  offsets = collections.defaultdict(int)
  lens = collections.defaultdict(int)

  offset_set = set()
  len_set = set()
  lit_set = set()

  for t in new_final:
    if type(t) is tuple:
      offsets[t[0]] += 1
      offset_set.add(t[0])
      len_set.add(t[1])
      if use_len_huffman:
        lens[t[1]] += 1
      else:
        offsets[t[1]] += 1
    else:
      offsets[t] += 1
      lit_set.add(t)

  # Calculate fixed-size cost
  fixed_offset = log2(max([-x for x in offset_set]))
  fixed_len = log2(max(len_set))
  fixed_lit = log2(max(lit_set))
  print('offset=%d len=%d lit=%d\n' % (fixed_offset, fixed_len, fixed_lit))

  # Create huffman trees
  offset_huffman = make_huffman(offsets)
  print('huffman (%d items) %s\n' % (len(offset_huffman), offset_huffman))

  if use_len_huffman:
    len_huffman = make_huffman(lens)
    print('len huffman (%d items) %s\n' % (len(len_huffman), len_huffman))
  else:
    len_huffman = offset_huffman

  data = []
  bits = ''
  total = 0
  was_tuple = True
  for i, t in enumerate(new_final):
    if was_tuple:
      total += fixed_offset
      count = 0
      while i < len(new_final):
        if type(new_final[i]) is tuple:
          break
        count += 1
        i += 1
      bits += padbin(fixed_offset, count) + ' '
      data += tobits(fixed_offset, count)

    if type(t) is tuple:
      was_tuple = True
      total += fixed_offset + fixed_len
      # total += len(offset_huffman[t[0]]) + len(len_huffman[t[1]])
      # bits += '%s|%s ' % (offset_huffman[t[0]], len_huffman[t[1]])
      bits += '%s|%s ' % (padbin(fixed_offset, -t[0]), padbin(fixed_len, t[1]))
      data += tobits(fixed_offset, -t[0]) + tobits(fixed_len, t[1])
    else:
      was_tuple = False
      total += fixed_lit
      # total += len(offset_huffman[t])
      # bits += offset_huffman[t] + ' '
      bits += padbin(fixed_lit, t) + ' '
      data += tobits(fixed_lit, t)

  print('(1bits/pixel) => %d bytes' % (sum(runs) / 8))
  print('  (4bits/run) => %d bytes' % (len(runs) / 2))
  # print('  (w/o table) => %d bytes (+%d bits)' % (total / 8, total % 8))

  # total += huffman_cost(offset_huffman)
  # if use_len_huffman:
  #   total += huffman_cost(len_huffman)

  # print(' (compressed) => %d bytes (+%d bits)' % (total / 8, total % 8))

  print('savings = %d' % (total / 8 - sum(runs) / 8))
  print(' (no huffman) => %d bytes (+%d bits)' % (total / 8, total % 8))
  print('savings = %d\n' % (total / 8 - sum(runs) / 8))

  print('encoded (no huffman): %s\n' % bits)
  # print('encoded (huffman): %s\n' % bits)
  # print(data)
  # print(map(hex, tobytes(data)))

  data = tobytes(data)
  data = ''.join(('"%s"\n' % ''.join(wasm(j) for j in data[i:i+24]))
                  for i in range(0, len(data), 24))
  print(data)



def log2(n):
  t = 0
  while n > 0:
    n >>= 1
    t += 1
  return t


def lzw(runs):
  dic = dict([((x,), x) for x in range(16)])
  i = 0
  result = []
  seq = []
  total = 0
  while i < len(runs) - 1:
    new_seq = seq + [runs[i]]
    tup_new_seq = tuple(new_seq)
    if tup_new_seq not in dic:
      code = dic[tuple(seq)]
      if code > 15:
        print '%d => %s' % (code, tuple(seq))
      result.append(code)
      dic[tup_new_seq] = len(dic)
      seq = [runs[i]]
    else:
      seq = new_seq
    i += 1
    total += log2(len(dic))

  print('%d bits = %d bytes' % (4 * len(runs), len(runs)/2), len(runs), runs)
  print('%d bits = %d bytes' % (total, total/8), len(result), result)


def main(args):
  parser = argparse.ArgumentParser()
  parser.add_argument('-m', '--min-match', type=int, default=10)
  parser.add_argument('-M', '--max-run', type=int, default=15)
  parser.add_argument('-d', '--max-dist', type=int, default=512)
  parser.add_argument('files', nargs='*')
  args = parser.parse_args(args)

  global min_match, max_run, max_dist
  min_match = args.min_match
  max_run = args.max_run
  max_dist = args.max_dist

  offsets = []
  data = []
  for f in args.files:
    offsets.append((f, len(data)))
    data.extend(read_file(f))

  if False:
    open('combined.dat', 'wb').write(''.join(map(chr, tobytes(data))))

  # Find run lengths
  last = 0
  runs = [0]
  for bit in data:
    if bit == last and runs[-1] < max_run:
      runs[-1] += 1
    else:
      if bit == last:
        runs.append(0)
      last = bit
      runs.append(1)

  lz77(runs)
  print('\n'.join(';; %s => %d' % t for t in offsets))


if __name__ == '__main__':
  sys.exit(main(sys.argv[1:]))
