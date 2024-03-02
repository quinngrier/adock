#! /bin/bash -
#
# The authors of this file have waived all copyright and
# related or neighboring rights to the extent permitted by
# law as described by the CC0 1.0 Universal Public Domain
# Dedication. You should have received a copy of the full
# dedication along with this file, typically as a file
# named <CC0-1.0.txt>. If not, it may be available at
# <https://creativecommons.org/publicdomain/zero/1.0/>.
#

set -E -e -u -o pipefail || exit $?
trap exit ERR

apk add --no-cache \
  autoconf \
  automake \
  bison \
  cairo-dev \
  chromium \
  clang \
  cmake \
  doas \
  flex \
  font-bakoma-ttf \
  gcc \
  gdk-pixbuf-dev \
  git \
  glib-dev \
  gnuplot \
  gtk-doc \
  inotify-tools \
  intltool \
  libtool \
  libxml2-dev \
  meson \
  musl-dev \
  ninja \
  nodejs \
  npm \
  pango-dev \
  patch \
  strace \
  wget \
;

#-----------------------------------------------------------------------
# Install the KaTeX fonts
#-----------------------------------------------------------------------

git clone https://github.com/KaTeX/KaTeX.git katex
mkdir /usr/share/fonts/katex
rmdir /usr/share/fonts/katex
cp -R katex/fonts /usr/share/fonts/katex
rm -r katex
fc-cache -r -v

#-----------------------------------------------------------------------
# Install Pikchr
#-----------------------------------------------------------------------

mkdir pikchr
pushd pikchr >/dev/null
wget \
  -O pikchr.tar.gz \
  https://pikchr.org/home/tarball/trunk/pikchr.tar.gz \
;
tar xzf pikchr.tar.gz
pushd */ >/dev/null
patch -p1 </patches/pikchr.patch
make CFLAGS='-O3 -s'
cp pikchr /bin
popd >/dev/null
popd >/dev/null
rm -f -r pikchr

#-----------------------------------------------------------------------
# Install Lasem 0.5.1
#-----------------------------------------------------------------------

git clone https://github.com/LasemProject/lasem.git lasem
cd lasem
git checkout LASEM_0_5_1
patch -p1 </patches/lasem/0.5.1.patch
./autogen.sh
./configure --prefix /usr PKG_CONFIG=pkg-config
make
make install
cd ..
rm -r lasem

#-----------------------------------------------------------------------

npm install \
  --unsafe-perm \
  -g \
  bpmn-js-cmd \
  http-server \
  linkedom \
  livereload \
;

mkdir /adock
chmod 777 /adock

echo permit keepenv nopass root >/etc/doas.d/doas.conf

#-----------------------------------------------------------------------
# Remove some unnecessary packages
#-----------------------------------------------------------------------

apk del \
  gcc \
  musl-dev \
  patch \
  wget \
;

#-----------------------------------------------------------------------
