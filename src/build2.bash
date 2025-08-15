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
patch -p1 </src/pikchr.patch
make CFLAGS='-O3 -s'
cp pikchr /bin
popd >/dev/null
popd >/dev/null
rm -f -r pikchr

#-----------------------------------------------------------------------
# Install Lasem
#-----------------------------------------------------------------------
#
# Note that we symlink on top of an older version here. It works fine.
#

rm -f -r /usr/lib/liblasem*
git clone https://github.com/LasemProject/lasem.git lasem
cd lasem
git checkout 62b629413ed9465ee0b54e784b89d78bcce2bd03
patch -p1 </src/lasem.patch
meson --prefix /usr build
cd build
ninja
ninja install
cd ../..
rm -r lasem
ln -s liblasem-0.6.so.0.5.2 /usr/lib/liblasem-0.6.so.5.0.1
ln -s liblasem-0.6.so.0.5.2 /usr/lib/liblasem-0.6.so.5

#-----------------------------------------------------------------------

cd /usr/lib/ruby/gems/*/gems/asciidoctor-mathematical-*/lib/asciidoctor-mathematical
patch -p1 </src/asciidoctor-mathematical.patch
cd /

#-----------------------------------------------------------------------

export PUPPETEER_SKIP_DOWNLOAD=1

cp -R /src/adock-bpmn-js-cmd /
(
  cd /adock-bpmn-js-cmd
  npm install
)

npm install \
  --unsafe-perm \
  -g \
  /adock-bpmn-js-cmd \
  http-server \
  linkedom \
  livereload \
;

echo -n 'node version: '
node -v

echo -n 'npm version: '
npm -v

npm ls -g --all

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

mv /src/adock-theme.yml /

#-----------------------------------------------------------------------

mv /src/entrypoint.bash /
chmod +x /entrypoint.bash

rm -r /src
