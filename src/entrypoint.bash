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
declare    group_id
declare    group_name
declare -A html_deps
declare    s
declare    user_id
declare    user_name
declare -A ys

IN_ADOCK=1
readonly IN_ADOCK
export IN_ADOCK

#-----------------------------------------------------------------------

user_id=$(stat -c %u /tmp_dir)
readonly user_id

group_id=$(stat -c %g /tmp_dir)
readonly group_id

group_name=$(getent group $group_id) && :
s=$?
if ((s == 0)); then
  group_name=${group_name%%:*}
elif ((s == 2)); then
  group_name=adock_group
  addgroup -g $group_id $group_name
else
  exit $s
fi
readonly group_name

user_name=$(getent passwd $user_id) && :
s=$?
if ((s == 0)); then
  user_name=${user_name%%:*}
  sed -i '
    /^'$user_name':/ {
      s/^\([^:]*:[^:]*:[^:]*\):[^:]*:\(.*\)/\1:'$group_id':\2/
    }
  ' /etc/passwd
elif ((s == 2)); then
  user_name=adock_user
  adduser -D -G $group_name -u $user_id $user_name
else
  exit $s
fi
readonly user_name

run_as_host() {
  doas -u $user_name -- "$@"
}; readonly -f run_as_host

umask $ADOCK_UMASK

#-----------------------------------------------------------------------

CHROMIUM_PATH=/usr/bin/chromium-browser
readonly CHROMIUM_PATH
export CHROMIUM_PATH

PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
readonly PUPPETEER_EXECUTABLE_PATH
export PUPPETEER_EXECUTABLE_PATH

#-----------------------------------------------------------------------

# TODO: Should probably always use environment variables to communicate
#       options from adock to entrypoint.sh.

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

NODE_NO_WARNINGS=1
readonly NODE_NO_WARNINGS
export NODE_NO_WARNINGS

#-----------------------------------------------------------------------

x=(
  /usr/local/lib/node_modules
  /usr/lib/node_modules
)

NODE_PATH="${x[@]}"
NODE_PATH=${NODE_PATH// /:}
readonly NODE_PATH
export NODE_PATH

#-----------------------------------------------------------------------

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
      fi
    fi
  done

  while ((${#html_deps[@]} > 0)); do
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
            ["audio", "src"],
            ["img", "src"],
            ["link", "href"],
            ["script", "src"],
            ["source", "src"],
            ["video", "src"],
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
      ' -- "${!html_deps[@]}"
    )
    eval ys="($xs)"
    html_deps=()
    for x in "${!ys[@]}"; do
      if [[ ! "${deps[$x]+x}" && -e "$x" ]]; then
        deps[$x]=
        if [[ "$x" == *.html ]]; then
          html_deps[$x]=
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
    if $ADOCK_LINK; then
      ln -s -- "$pwd/$x" "/adock/tmp1/$x"
    else
      cp -L -p -- "$x" "/adock/tmp1/$x"
    fi
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
