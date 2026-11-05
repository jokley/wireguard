ARG CODE_SERVER_VERSION=4.139.1
ARG NODE_VERSION=24.22.2
ARG PYTHON_VERSION=3.12.16

FROM node:${NODE_VERSION}-trixie-slim AS node-toolchain
FROM python:${PYTHON_VERSION}-slim-trixie AS python-toolchain
# Derive the interpreter/stdlib shared-library packages from the matching Debian
# release, rather than copying system libraries over the Code-Server base.
RUN find /usr/local -type f -executable -not -name '*tkinter*' -exec ldd '{}' ';' \
    | awk '/=>/ { so = $(NF-1); if (index(so, "/usr/local/") == 1) next; gsub("^/(usr/)?", "", so); print "*" so }' \
    | sort -u \
    | xargs -r dpkg-query --search \
    | awk 'sub(":$", "", $1) { print $1 }' \
    | sort -u > /tmp/python-runtime-packages
RUN test -s /tmp/python-runtime-packages

FROM codercom/code-server:${CODE_SERVER_VERSION}
ARG PNPM_VERSION=10.30.3

USER root

# Keep the existing route/privilege tools and add only generic native build
# tools. Python headers, pip and venv come with the official Python toolchain.
COPY --from=python-toolchain /tmp/python-runtime-packages /tmp/python-runtime-packages
RUN . /etc/os-release \
    && test "$VERSION_CODENAME" = trixie \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        $(cat /tmp/python-runtime-packages) \
        build-essential \
        ca-certificates \
        pkg-config \
        gosu \
        iproute2 \
        openssh-client \
    && rm -rf /var/lib/apt/lists/* /tmp/python-runtime-packages

# Both upstream toolchain stages use Debian 13/trixie, like Code-Server 4.139.1.
# Copy Python (including headers/ensurepip/venv), then only Node and its npm.
COPY --from=python-toolchain /usr/local/ /usr/local/
COPY --from=node-toolchain /usr/local/bin/node /usr/local/bin/node
COPY --from=node-toolchain /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && ldconfig \
    && npm --cache=/tmp/npm-cache install --global --no-audit --no-fund "pnpm@${PNPM_VERSION}" \
    && rm -rf /tmp/npm-cache \
    && node --version \
    && npm --version \
    && pnpm --version \
    && python3 -c 'import ssl, sqlite3, bz2, lzma, ctypes, venv; import sys; assert sys.version_info[:2] == (3, 12)' \
    && python3 -m venv /tmp/toolchain-venv \
    && /tmp/toolchain-venv/bin/python -m pip --version \
    && rm -rf /tmp/toolchain-venv

COPY config.yaml /etc/code-server/config.yaml
RUN chmod 0755 /etc/code-server && chmod 0644 /etc/code-server/config.yaml

COPY route-entrypoint.sh /usr/local/bin/route-entrypoint.sh
RUN chmod 0755 /usr/local/bin/route-entrypoint.sh

# The wrapper needs NET_ADMIN while installing the namespace-local route. It
# then uses gosu to start dumb-init/code-server directly as `coder:coder`.
USER root
ENTRYPOINT ["/usr/local/bin/route-entrypoint.sh"]
