# Containerfile — OpenCode CLI w rootless Podman
# Bazuje na Ubuntu 24.04 LTS
# Budowa: podman build -t opencode:latest -f Containerfile .
#
# Multi-stage build:
#   Stage 1 (opencode-builder): pobiera binary opencode CLI
#   Stage 2 (final):            obraz właściwy z narzędziami i użytkownikiem
#
# Kolejność warstw (ważna!):
#   1. apt packages
#   2. opencode CLI (kopiowany z buildera)
#   3. user opencode (UID/GID 1000)
#   4. zmienne środowiskowe
#   5. USER opencode
#   6. HEALTHCHECK + ENTRYPOINT

# ============================================================
# Stage 1: opencode-builder
# ============================================================

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION} AS opencode-builder

ARG OPENCODE_VERSION=latest

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://opencode.ai/install | bash && \
    cp /root/.opencode/bin/opencode /opencode && \
    opencode --version

# ============================================================
# Stage 2: final
# ============================================================

FROM ubuntu:${UBUNTU_VERSION}

LABEL org.opencontainers.image.title="OpenCode CLI Container"
LABEL org.opencontainers.image.description="Rootless Podman container for OpenCode AI coding agent"
LABEL org.opencontainers.image.source="https://github.com/webbag/opencode"
LABEL org.opencontainers.image.licenses="Apache 2.0"
LABEL org.opencontainers.image.version="1.0.0"

# sudo celowo pominięte — użytkownik opencode nie ma praw sudo,
# binary sudo to niepotrzebny wektor ataku.

RUN apt-get update && apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        git \
        python3 \
        python3-pip \
        python3-venv \
        nano \
        curl \
        ca-certificates \
        nmap \
        iputils-ping \
        iproute2 \
        dnsutils \
        netcat-openbsd \
        wget \
        bash \
    && rm -rf /var/lib/apt/lists/*

COPY --from=opencode-builder /opencode /usr/local/bin/opencode

RUN opencode --version

# CAP_NET_RAW dla ping — celowo zakomentowane.
# Decyzja: narzędzia diagnostyczne działają w ograniczonym zakresie.
# Alternatywa dla ping: nping --tcp -p 80 <host>
# RUN setcap cap_net_raw+p /bin/ping

# Użytkownik opencode (UID/GID 1000) odpowiada domyślnemu UID na hoście Ubuntu.
# Katalogi konfiguracyjne tworzone przed USER opencode — mają odpowiednie prawa.

RUN userdel -r ubuntu 2>/dev/null; \
    groupdel ubuntu 2>/dev/null; \
    groupadd -g 1000 opencode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash opencode && \
    mkdir -p /home/opencode/workdir \
             /home/opencode/.config/opencode \
             /home/opencode/.local && \
    chown -R opencode:opencode /home/opencode

# Klucze API NIGDY nie są buildowane w obraz.
# Przekazywane przez -e OPENAI_API_KEY=... w podman run.

ENV HOME=/home/opencode
ENV OPENCODE_HOME=/home/opencode/.config/opencode
ENV PATH="/home/opencode/.local/bin:${PATH}"

WORKDIR /home/opencode/workdir

USER opencode

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD opencode --version > /dev/null 2>&1 || exit 1

ENV OPENCODE_DEFAULT_MODEL=opencode/big-pickle
ENV OPENCODE_MODEL=opencode/big-pickle

ENTRYPOINT ["opencode"]
CMD ["-m", "opencode/big-pickle"]
