#
# The authors of this file have waived all copyright and
# related or neighboring rights to the extent permitted by
# law as described by the CC0 1.0 Universal Public Domain
# Dedication. You should have received a copy of the full
# dedication along with this file, typically as a file
# named <CC0-1.0.txt>. If not, it may be available at
# <https://creativecommons.org/publicdomain/zero/1.0/>.
#

import fontforge
import shutil

fileses = [
  [
    "/katex/fonts/KaTeX_Main-Regular.ttf",
    "/usr/lib/ruby/gems/3.2.0/gems/asciidoctor-pdf-2.3.13/data/fonts/notoserif-regular-subset.ttf",
    "/usr/lib/ruby/gems/3.2.0/gems/asciidoctor-pdf-2.3.13/data/fonts/notoemoji-subset.ttf",
  ],
  [
    "/katex/fonts/KaTeX_Main-Bold.ttf",
    "/usr/lib/ruby/gems/3.2.0/gems/asciidoctor-pdf-2.3.13/data/fonts/notoserif-bold-subset.ttf",
    "/usr/lib/ruby/gems/3.2.0/gems/asciidoctor-pdf-2.3.13/data/fonts/notoemoji-subset.ttf",
  ],
  [
    "/katex/fonts/KaTeX_Main-Italic.ttf",
    "/usr/lib/ruby/gems/3.2.0/gems/asciidoctor-pdf-2.3.13/data/fonts/notoserif-italic-subset.ttf",
    "/usr/lib/ruby/gems/3.2.0/gems/asciidoctor-pdf-2.3.13/data/fonts/notoemoji-subset.ttf",
  ],
  [
    "/katex/fonts/KaTeX_Main-BoldItalic.ttf",
    "/usr/lib/ruby/gems/3.2.0/gems/asciidoctor-pdf-2.3.13/data/fonts/notoserif-bold_italic-subset.ttf",
    "/usr/lib/ruby/gems/3.2.0/gems/asciidoctor-pdf-2.3.13/data/fonts/notoemoji-subset.ttf",
  ],
]

charses = [
  (0x004D, 0x00A9), # copyright sign
]

for files in fileses:
  fonts = [fontforge.open(file) for file in files]
  dst = fonts[0]
  for chars in charses:
    ref = chars[0]
    chr = chars[1]
    if not chr in dst:
      for src in fonts[1:]:
        if chr in src:
          src.selection.select(chr)
          dst.selection.select(chr)
          src.copy()
          dst.paste()
          glyph = dst[ref]
          box = glyph.boundingBox()
          height1 = box[3] - box[1]
          glyph = dst[chr]
          box = glyph.boundingBox()
          height2 = box[3] - box[1]
          scale = float(height1) / float(height2)
          glyph.transform([scale, 0, 0, scale, 0, 0])
          break
  dst.generate("/tmp.ttf", flags=("opentype", "old-kern"))
  for font in fonts:
    font.close()
  shutil.copy("/tmp.ttf", files[0])
