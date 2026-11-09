# Pinned Linux host for publishable evidence: GNU time, /proc, taskset, and glibc
# mallinfo2 match the protocol the retained Linux datasets were recorded with.
ARG RUBY_VERSION
FROM ruby:${RUBY_VERSION}-bookworm

RUN apt-get update \
 && apt-get install -y --no-install-recommends time util-linux git libsqlite3-dev \
 && rm -rf /var/lib/apt/lists/* \
 && gem install bundler -v 2.6.9 --no-document \
 && git config --system --add safe.directory '*' \
 && mkdir -p /bundle && chmod 1777 /bundle

ARG TASK_VERSION=3.54.0
RUN curl -fsSL "https://github.com/go-task/task/releases/download/v${TASK_VERSION}/task_linux_$(dpkg --print-architecture).tar.gz" \
  | tar -xz -C /usr/local/bin task

ENV BUNDLE_PATH=/bundle HOME=/tmp
