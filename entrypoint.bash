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

shopt -s \
  dotglob \
  extglob \
  globstar \
  nullglob \
;

LC_ALL=C
readonly LC_ALL
export LC_ALL

#-----------------------------------------------------------------------

declare -A deps
declare    host_gid
declare    host_uid
declare -A html_deps
declare -A new_html_deps
declare -A ys

#-----------------------------------------------------------------------

host_uid=$(stat -c %u:%g /tmp_dir)
host_gid=${host_uid#*:}
host_uid=${host_uid%:*}
readonly host_uid
readonly host_gid

if ((host_uid == 0)); then

  run_as_host() {
    "$@"
  }; readonly -f run_as_host

else

  if ((host_gid == 0)); then
    adduser -D -G root -H -u $host_uid host
  else
    addgroup -g $host_gid host
    adduser -D -G host -H -u $host_uid host
  fi

  echo permit keepenv nopass root >/etc/doas.conf

  run_as_host() {
    doas -u host -- "$@"
  }; readonly -f run_as_host

fi

umask $ADOCK_UMASK

#-----------------------------------------------------------------------

if [[ "${1-}" != --serve ]]; then
  run_as_host asciidoctor "$@"
  exit
fi

shift

#-----------------------------------------------------------------------

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

CHROMIUM_PATH=/usr/bin/chromium-browser
readonly CHROMIUM_PATH
export CHROMIUM_PATH

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

run_as_host mkdir /adock/out

pushd /adock/out >/dev/null

info "Starting HTTP server on $http_addr"

http-server \
  . \
  --port 80 \
  --proxy 'http://127.0.0.1:80?' \
  -c-1 \
  >/dev/null \
&

http_server_pid=$!
readonly http_server_pid

# TODO: Make -w/--wait an adock option.

info "Starting LiveReload server on $live_addr"
livereload . -w 100 >/dev/null &
livereload_pid=$!
readonly livereload_pid

popd >/dev/null

pwd=$PWD
if [[ "$pwd" == / ]]; then
  pwd=
fi
readonly pwd

while :; do

  info "Running asciidoctor"

  deps=()
  html_deps=()

  # We assume that all non-absolute open() paths are relative to $PWD.

  run_as_host strace \
    -e '?open' \
    -o /adock/deps \
    -xx \
    asciidoctor \
    "$@" \
  ;
  xs=$(
    sed -n '
      /^open(/ {
        s/open("//
        s/".*//
        p
      }
    ' /adock/deps
  )
  for x in $xs; do
    printf -v x "$x"
    if [[ "$x" != /* ]]; then
      y=$x
    elif [[ "$x" == "$pwd/"* ]]; then
      y=${x#"$pwd/"}
    else
      y=
    fi
    if [[ "$y" ]]; then
      deps[$y]=
      if [[ "$y" == *.html ]]; then
        html_deps[$y]=
        new_html_deps[$y]=
      fi
    fi
  done

  while ((${#new_html_deps[@]} > 0)); do
    xs=$(
      node -e '
        const fs = require("fs");
        const {parseHTML} = require("linkedom");
        const paths = new Set();
        for (const file of process.argv.slice(1)) {
          const prefix = file.replace(/[^\/]+$/, "");
          const {document} = parseHTML(fs.readFileSync(file, "utf8"));
          for (const [tag, attr] of [
            ["a", "href"],
            ["img", "src"],
            ["link", "href"],
            ["script", "src"],
          ]) {
            for (const node of document.getElementsByTagName(tag)) {
              const path = decodeURI(node.getAttribute(attr));
              if (!path.includes("://")) {
                paths.add(prefix + path);
              }
            }
          }
        }
        const q = "'\''";
        const qr = /'\''/g;
        const qe = q + "\\" + q + q;
        for (const path of paths) {
          console.log("[" + q + path.replace(qr, qe) + q + "]=");
        }
      ' -- "${!new_html_deps[@]}"
    )
    eval ys="($xs)"
    new_html_deps=()
    for x in "${!ys[@]}"; do
      if [[ ! "${deps[$x]+x}" && -e "$x" ]]; then
        deps[$x]=
        if [[ "$x" == *.html ]]; then
          html_deps[$x]=
          new_html_deps[$x]=
        fi
      fi
    done
  done

  for x in "${!deps[@]}"; do
    case $x in *$'\n'* | *$'\r'*)
      barf "Strange file names are not supported."
    esac
  done

  (
    IFS=$'\n'
    sort -u <<<"${!deps[*]}" >/adock/deps
  )

  rm -f -r /adock/tmp1
  run_as_host mkdir /adock/tmp1
  for x in "${!deps[@]}"; do
    if [[ "$x" == */* ]]; then
      run_as_host mkdir -p "/adock/tmp1/${x%/*}"
    fi
    cp -L -R -p -- "$x" "/adock/tmp1/$x"
  done

  for x in /adock/tmp1/**/*.html; do
    run_as_host sh -c '>/adock/tmp2'
    sed '
      s/<\/body>/\
        <script>\
          document.write("<script src=\\"http:\/\/"\
            + (location.host || "localhost").split(":")[0]\
            + ":'$live_port'\/livereload.js?snipver=1\\">"\
            + "<" + "\/script>");\
        <\/script>\
      &/g
    ' "$x" >/adock/tmp2
    mv -f /adock/tmp2 "$x"
  done

  for x in /adock/tmp1/**/*; do
    if [[ -f "$x" ]]; then
      y=/adock/out/${x#/adock/tmp1/}
      rm -f -r "$y"
      run_as_host mkdir -p "${y%/*}"
      mv -f "$x" "$y"
    fi
  done

  run_as_host inotifywait \
    --event "$inotifywait_events" \
    --format '[%T] File modified: %w' \
    --fromfile /adock/deps \
    --quiet \
    --timefmt '%Y-%m-%d %H:%M:%S' \
  ;

done
