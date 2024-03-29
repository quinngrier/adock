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

shopt -s nullglob

image=${2+"--image=$2"}
readonly image

cd examples/"$1"

rm -f diag-*

x=../../adock
if [[ "${2+x}" ]]; then
  x+=' --image="$2"'
fi
x+=' -r asciidoctor-diagram'
x+=' index.adoc'
eval " $x"

# TODO: Right now, this is hardcoded to fail if no diag-* files are
#       generated. I might later have examples that don't have diagrams,
#       so they wouldn't generate diag-* files. This script will likely
#       need an option that says whether it should expect diag-* files
#       to be generated.

for x in diag-*; do
  exit 0
done
exit 1
