# Containerfile — OpenCode CLI w rootless Podman
# Bazuje na Ubuntu 24.04 LTS
# Budowa: podman build -t opencode:latest -f Containerfile .
#
# Kolejność warstw (ważna!):
#   1. apt packages
#   2. opencode CLI (instalacja jako root — globalny dostęp)
#   3. user opencode (UID/GID 1000)
#   4. zmienne środowiskowe
#   5. USER opencode
#   6. ENTRYPOINT

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

LABEL org.opencontainers.image.title="OpenCode CLI Container"
LABEL org.opencontainers.image.description="Rootless Podman container for OpenCode AI coding agent"
LABEL org.opencontainers.image.source="https://github.com/webbag/opencode"
LABEL org.opencontainers.image.licenses="Apache 2.0"
LABEL org.opencontainers.image.version="1.0.0"

# ============================================================
# SCOPE 1: System packages and tools
# ============================================================
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

# ============================================================
# SCOPE 1: OpenCode CLI installation
# ============================================================
# Instalacja jako root → binary w /usr/local/bin (dostępny dla wszystkich).
# Oficjalny skrypt sam wykrywa architekturę — ARG TARGETARCH nie jest potrzebny.

ARG OPENCODE_VERSION=latest

RUN curl -fsSL https://opencode.ai/install | bash -s -- ${OPENCODE_VERSION} && \
    ln -sf /root/.opencode/bin/opencode /usr/local/bin/opencode

RUN opencode --version

# ============================================================
# SCOPE 2: User setup (sandboxing)
# ============================================================
# Użytkownik opencode (UID/GID 1000) odpowiada domyślnemu UID na hoście Ubuntu.
# Katalogi konfiguracyjne tworzone przed USER opencode — mają odpowiednie prawa.

RUN groupadd -g 1000 opencode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash opencode && \
    mkdir -p /home/opencode/workdir \
             /home/opencode/.config/opencode \
             /home/opencode/.local && \
    chown -R opencode:opencode /home/opencode

# CAP_NET_RAW dla ping — celowo zakomentowane.
# Decyzja: narzędzia diagnostyczne działają w ograniczonym zakresie.
# Alternatywa dla ping: nping --tcp -p 80 <host>
# RUN setcap cap_net_raw+p /bin/ping

# ============================================================
# SCOPE 3: Configuration and environment
# ============================================================
# Klucze API NIGDY nie są buildowane w obraz.
# Przekazywane przez -e OPENAI_API_KEY=... w podman run.

ENV HOME=/home/opencode
ENV OPENCODE_HOME=/home/opencode/.config/opencode
ENV PATH="/home/opencode/.local/bin:${PATH}"

WORKDIR /home/opencode/workdir

USER opencode

ENTRYPOINT ["opencode"]
CMD ["--help"]
