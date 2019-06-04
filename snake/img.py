import sys

data = open(sys.argv[1]).read()

s = ''
for line in data.split('\n')[:16]:
  bit = 0x8000
  data = 0
  for c in line:
    if c != ' ':
      data |= bit
    bit >>= 1
  s += "\\%02x\\%02x" % (data & 0xff, data >> 8)
print('"%s"\n"%s"' % (s[:16*3], s[16*3:]))
