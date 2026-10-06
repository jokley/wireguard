ARG CODE_SERVER_VERSION=4.139.1
FROM codercom/code-server:${CODE_SERVER_VERSION}

USER root

# Install only the two runtime tools this stack explicitly requires. Repeating
# an already present package is harmless and avoids relying on upstream details.
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        iproute2 \
        openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY route-entrypoint.sh /usr/local/bin/route-entrypoint.sh
RUN chmod 0755 /usr/local/bin/route-entrypoint.sh

# The wrapper needs NET_ADMIN while installing the namespace-local route. It
# then delegates to the upstream entrypoint, which is responsible for starting
# code-server as its regular `coder` user; this behavior is a preflight gate.
USER root
ENTRYPOINT ["/usr/local/bin/route-entrypoint.sh"]
