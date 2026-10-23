# Keep the proven Alpine/Python/venv design from the legacy image while using a
# fixed Alpine release instead of its floating architecture-specific latest tag.
FROM arm64v8/alpine:3.22.1

# The deployed WebSSH package version is not derivable from this repo. Pin it
# only after the target host's current runtime version is recorded.
RUN apk add --no-cache \
      iproute2 \
      py3-pip \
      py3-virtualenv \
      python3 \
      su-exec \
    && addgroup -S -g 10001 webssh \
    && adduser -S -D -u 10001 -h /home/webssh -s /sbin/nologin \
      -G webssh webssh \
    && python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir webssh

ENV PATH="/opt/venv/bin:${PATH}"

COPY route-entrypoint.sh /usr/local/bin/route-entrypoint.sh
RUN chmod 0755 /usr/local/bin/route-entrypoint.sh

USER root
ENTRYPOINT ["/usr/local/bin/route-entrypoint.sh"]
