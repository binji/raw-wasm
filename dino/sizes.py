import math

sizes = [
  ('dead', 20, 22, 83),
  ('stand', 20, 22, 83),
  ('run1', 20, 22, 83),
  ('run2', 20, 22, 83),
  ('duck1', 28, 13, 83),
  ('duck2', 28, 13, 83),
  ('cactus1', 13, 26, 83),
  ('cactus2', 19, 18, 83),
  ('cactus3', 28, 18, 83),
  ('cactus4', 9, 18, 83),
  ('cactus5', 40, 26, 83),
  ('cloud', 26, 8, 83),
  ('ground1', 32, 5, 83),
  ('ground2', 32, 5, 83),
  ('ground3', 32, 5, 83),
]

addr = 0
for name, w, h, alpha in sizes:
  print(';; %+d %s.ppm %d %d' % (addr, name, w, h))
  print('"\%02x\%02x\%02x"' % (w, h, alpha))
  addr += math.ceil((w * h) / 8 + 3)
