ARG CODE_SERVER_VERSION=4.139.1
FROM codercom/code-server:${CODE_SERVER_VERSION}

USER root

# Install the two runtime tools plus the small, purpose-built privilege-drop
# helper. Repeating an already present package is harmless and keeps the derived
# image independent of implicit upstream package contents.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gosu \
        iproute2 \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY route-entrypoint.sh /usr/local/bin/route-entrypoint.sh
RUN chmod 0755 /usr/local/bin/route-entrypoint.sh

# The wrapper needs NET_ADMIN while installing the namespace-local route. It
# then uses gosu to delegate to the upstream entrypoint as `coder:coder`.
USER root
ENTRYPOINT ["/usr/local/bin/route-entrypoint.sh"]
