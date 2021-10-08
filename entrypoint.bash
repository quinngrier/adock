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

LC_ALL=C
readonly LC_ALL
export LC_ALL

if [[ "${1-}" != --serve ]]; then
  exec asciidoctor "$@"
fi

info() {
  declare d
  d=$(date '+%Y-%m-%d %H:%M:%S')
  printf '%s' "[$d]"
  printf ' %s' "$@"
  echo
}

trap exit INT

NODE_NO_WARNINGS=1
readonly NODE_NO_WARNINGS
export NODE_NO_WARNINGS

NODE_PATH=/usr/lib/node_modules
readonly NODE_PATH
export NODE_PATH

inotifywait_events=attrib
inotifywait_events+=,create
inotifywait_events+=,delete
inotifywait_events+=,delete_self
inotifywait_events+=,modify
inotifywait_events+=,move_self
inotifywait_events+=,moved_from
inotifywait_events+=,moved_to
readonly inotifywait_events

shift

http_addr=$1
readonly http_addr
shift

live_addr=$1
readonly live_addr
shift

live_port=${live_addr#*:}
readonly live_port

mkdir -p /adock/out

pushd /adock/out >/dev/null

info "Starting HTTP server on $http_addr"
http-server . -p 80 >/dev/null &
http_server_pid=$!
readonly http_server_pid

info "Starting LiveReload server on $live_addr"
livereload . >/dev/null &
livereload_pid=$!
readonly livereload_pid

popd >/dev/null

while :; do

  info "Running asciidoctor"

  strace \
    -e open \
    -o /adock/deps \
    asciidoctor \
    -o /adock/out/index.tmp.html \
    "$@" \
  ;

  deps=$(
    sed -n '/^open(/ p' /adock/deps | sed -n '
      s/open("//
      s/".*//
      s|^[^/]|'$PWD'/&|
      s|^'$PWD'/|&|p
    '
  )

  xs=$(
    node -e '
      const fs = require("fs");
      const {parseHTML} = require("linkedom");
      const file = "/adock/out/index.tmp.html";
      const data = fs.readFileSync(file, "utf8");
      const {document} = parseHTML(data);
      for (const [tag, attr] of [["a", "href"], ["img", "src"]]) {
        for (const node of document.getElementsByTagName(tag)) {
          const path = node.getAttribute(attr);
          if (!path.includes("://")) {
            console.log(path);
          }
        }
      }
    ' | sed 's|^|'$PWD'/|' | sort -u
  )

  for x in $xs; do
    if [[ -f "$x" ]]; then
      deps+=${deps:+$'\n'}$x
      y=/adock/out/${x#$PWD/}
      mkdir -p ${y%/*}
      ln -f -s $x $y
    fi
  done

  sort -u <<<"$deps" >/adock/deps

  inotifywait \
    --event "$inotifywait_events" \
    --format '[%T] File modified: %w' \
    --fromfile /adock/deps \
    --quiet \
    --timefmt '%Y-%m-%d %H:%M:%S' \
  &
  inotifywait_pid=$!

  sed '
    /<body/ a\
      <script>\
        document.write("<script src=\\"http://"\
          + (location.host || "localhost").split(":")[0]\
          + ":'$live_port'/livereload.js?snipver=1\\"></" + "script>");\
      </script>
  ' /adock/out/index.tmp.html >/adock/tmp

  mv -f /adock/tmp /adock/out/index.html

  wait $inotifywait_pid

done
