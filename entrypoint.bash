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

barf() {
  if (($# == 0)); then
    printf '%s\n' "$0: Unknown error." >&2
  else
    printf '%s' "$0: $1" >&2
    shift
    printf ' %s' "$@" >&2
    echo >&2
  fi
  exit 1
}

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
r='^[1-9][0-9]{1,4}$'
if [[ ! "$live_port" =~ $r ]] || ((live_port > 65535)); then
  barf "Invalid live_port: $live_port"
fi

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

pwd=$PWD
if [[ "$pwd" == / ]]; then
  pwd=
fi
readonly pwd

pwd_hex=
for ((i = 0; i < ${#pwd}; ++i)); do
  pwd_hex+=$(printf '\\\\x%02x' "'${pwd:i:1}")
done
readonly pwd_hex

while :; do

  info "Running asciidoctor"

  deps=()

  # We assume that all non-absolute open() paths are relative to $PWD.

  strace \
    -e open \
    -o /adock/deps \
    -xx \
    asciidoctor \
    -o /adock/out/index.tmp.html \
    "$@" \
  ;
  xs=$(
    sed -n '/^open(/ p' /adock/deps | sed -n '
      s/open("//
      s/".*//
      s/^\\x\([^2]\|2[^f]\)/'$pwd_hex'\\x2f&/
      /^'$pwd_hex'\\x2f/ p
    '
  )
  for x in $xs; do
    printf -v x "$x"
    deps+=("$x")
  done

  xs=$(
    node -e '
      const fs = require("fs");
      const {parseHTML} = require("linkedom");
      const file = "/adock/out/index.tmp.html";
      const data = fs.readFileSync(file, "utf8");
      const {document} = parseHTML(data);
      const q = "'\''";
      const qr = /'\''/g;
      const qe = q + "\\" + q + q;
      let paths = [];
      for (const [tag, attr] of [["a", "href"], ["img", "src"]]) {
        for (const node of document.getElementsByTagName(tag)) {
          const path = decodeURI(node.getAttribute(attr));
          if (!path.includes("://")) {
            paths.push(path);
          }
        }
      }
      for (const path of new Set(paths)) {
        console.log(q + path.replace(qr, qe) + q);
      }
    '
  )
  eval xs="($xs)"
  for x in "${xs[@]}"; do
    x=$pwd/$x
    if [[ -f "$x" ]]; then
      deps+=("$x")
      y=/adock/out/${x#"$pwd/"}
      mkdir -p "${y%/*}"
      ln -f -s "$x" "$y"
    fi
  done

  for x in "${deps[@]}"; do
    case $x in *$'\n'* | *$'\r'*)
      barf "Strange file names are not supported."
    esac
  done

  (IFS=$'\n'; sort -u <<<"${deps[*]}" >/adock/deps)

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
