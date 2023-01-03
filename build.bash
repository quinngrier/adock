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
  chromium \
  doas \
  gcc \
  gnuplot \
  inotify-tools \
  musl-dev \
  nodejs \
  npm \
  strace \
  wget \
;

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
make CFLAGS='-O3 -s'
cp pikchr /bin
popd >/dev/null
popd >/dev/null
rm -f -r pikchr

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
  wget \
;

#-----------------------------------------------------------------------
