FROM docker.io/library/perl:5.40
RUN curl -fsSL --compressed https://git.io/cpm > /usr/local/bin/cpm && chmod +x /usr/local/bin/cpm

COPY cpanfile /tmp/cpanfile
RUN cd /tmp && \
  cpm install -g && \
  rm -rf ~/.perl-cpm ~/.cpanm /tmp/cpanfile
