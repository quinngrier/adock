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
  gnuplot \
  inotify-tools \
  nodejs \
  npm \
  strace \
;

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
