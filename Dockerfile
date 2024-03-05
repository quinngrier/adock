#
# The authors of this file have waived all copyright and
# related or neighboring rights to the extent permitted by
# law as described by the CC0 1.0 Universal Public Domain
# Dedication. You should have received a copy of the full
# dedication along with this file, typically as a file
# named <CC0-1.0.txt>. If not, it may be available at
# <https://creativecommons.org/publicdomain/zero/1.0/>.
#

FROM asciidoctor/docker-asciidoctor AS build1
RUN apk add --no-cache bash
COPY build1.bash /
COPY patches /patches/
RUN bash /build1.bash

FROM asciidoctor/docker-asciidoctor AS build2
RUN apk add --no-cache bash
COPY [ \
  "adock-theme.yml", \
  "build2.bash", \
"/"]
COPY patches /patches/
COPY --from=build1 /katex/fonts /usr/share/fonts/katex/
RUN bash /build2.bash
RUN rm /build2.bash
COPY entrypoint.bash /
RUN chmod +x /entrypoint.bash

FROM scratch
COPY --from=build2 / /
ENTRYPOINT ["/entrypoint.bash"]
CMD []
