# opencode-image — Plan implementacji

## 1. Wymagania i ograniczenia

**Cel:** Obraz kontenera do izolowanego uruchamiania OpenCode CLI na Ubuntu 24.04 z Podmanem rootless.

**Wymagania niefunkcjonalne:**
- Izolacja procesów, systemu plików i sieci
- Reproducowalny build (wersjonowanie pakietów)
- Zero capabilities + no-new-privileges

**Ograniczenia:**
- Tylko Podman (brak Docker daemon)
- Host: Ubuntu 24.04 (AppArmor, nie SELinux)
- User opencode w kontenerze, WORKDIR /workspace

## 2. Architektura

```
[Host Ubuntu 24.04]
    |
    | Podman (rootless) --userns=keep-id
    v
[debian:bookworm-slim — OpenCode Runtime]
    |
    | -v $PWD:/workspace   (mount roboczy)
    | -v ~/.gitconfig:/home/opencode/.gitconfig:ro
    | -v ~/.ssh:/home/opencode/.ssh:ro
    v
[/workspace (projekt użytkownika)]
```

**Model bezpieczeństwa:**
- read-only root (opcjonalnie)
- no-new-privileges
- drop ALL capabilities
- --network=none (opcjonalnie, domyślnie mostkowana)
- --pids-limit=512
- --memory=8g, --cpus=4

## 3. Containerfile (multi-stage)

```dockerfile
# Stage 1: instalacja opencode-ai (potrzebuje Node.js do postinstall)
FROM node:bookworm-slim AS builder

ARG OPENCODE_VERSION=1.17.9

RUN npm install -g opencode-ai@${OPENCODE_VERSION}

# Stage 2: finalny obraz (bez Node.js)
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    git \
    curl \
    ca-certificates \
    tar \
    gzip \
    unzip \
    findutils \
    procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /usr/local/lib/node_modules/opencode-ai/bin/opencode.exe /usr/local/bin/opencode

RUN groupadd --gid 1000 opencode && \
    useradd --uid 1000 --gid opencode --shell /bin/bash --create-home opencode && \
    mkdir -p /home/opencode/.config /home/opencode/.cache /home/opencode/.opencode && \
    chown -R opencode:opencode /home/opencode

USER opencode
WORKDIR /workspace

CMD ["opencode"]
```

## 4. Build

```bash
podman build -t opencode:bookworm .
```

Wymagany `.containerignore`:
```
*
!Containerfile
```

## 5. Uruchomienie

### 5.1 Standard (domyślny)

```bash
podman run -it --rm \
  --userns=keep-id \
  -v $PWD:/workspace \
  -v ~/.gitconfig:/home/opencode/.gitconfig:ro \
  -v ~/.ssh:/home/opencode/.ssh:ro \
  opencode:bookworm
```

### 5.2 Hardened (rekomendowany)

```bash
podman run -it --rm \
  --userns=keep-id \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --pids-limit=512 \
  --memory=8g \
  --cpus=4 \
  -v $PWD:/workspace \
  -v ~/.gitconfig:/home/opencode/.gitconfig:ro \
  -v ~/.ssh:/home/opencode/.ssh:ro \
  opencode:bookworm
```

### 5.3 Locked-down (bez sieci, RO)

```bash
podman run -it --rm \
  --userns=keep-id \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --network=none \
  --read-only \
  --tmpfs /tmp:noexec,nosuid,size=64M \
  --tmpfs /home/opencode/.config:noexec,nosuid,size=16M \
  --tmpfs /home/opencode/.cache:noexec,nosuid,size=256M \
  --tmpfs /home/opencode/.opencode:noexec,nosuid,size=16M \
  -v $PWD:/workspace \
  -v ~/.gitconfig:/home/opencode/.gitconfig:ro \
  opencode:bookworm
```

Uwaga: `--network=none` wyłącza SSH, więc `~/.ssh` nie ma sensu mountować — git nie będzie klonował/pushował przez sieć.

## 6. Weryfikacja

### Testy bezpieczeństwa

```bash
# Sprawdź capability procesu
podman run --rm opencode:bookworm capsh --print 2>/dev/null || \
  grep CapBnd /proc/self/status

# Próba mount (powinna się nie udać)
podman run --rm opencode:bookworm sh -c "mount /dev/sda1 /mnt 2>&1" || true

# Próba ptrace innego procesu
podman run --rm opencode:bookworm sh -c "kill -0 1 2>&1" || true

# Sprawdź PID 1 (powinien być proces opencode)
podman run --rm opencode:bookworm sh -c "readlink /proc/1/exe"

# Próba dostępu do /sys z hosta
podman run --rm opencode:bookworm sh -c "ls /sys/class/block 2>&1" || true
```

### Testy funkcjonalne

```bash
# OpenCode wersja
podman run --rm opencode:bookworm opencode --version

# Git działa
podman run --rm opencode:bookworm git version

# Python działa
podman run --rm opencode:bookworm python3 --version
```

## 7. Git auth — strategia

Kontener montuje z hosta:
- `~/.gitconfig` jako RO → `user.name`, `user.email`, aliasy
- `~/.ssh` jako RO → klucze prywatne do repo

SSH agent forwarding alternatywnie:
```bash
podman run -it --rm \
  -v $SSH_AUTH_SOCK:$SSH_AUTH_SOCK \
  -e SSH_AUTH_SOCK \
  ...opencode:bookworm
```

## 8. Hardening (opcjonalny)

- **Seccomp profile**: `--security-opt seccomp=/path/to/custom.json` (domyślny Podman jest OK)
- **gVisor**: `--runtime=runsc` (dodatkowa izolacja kernel space)
- **Network egress only**: zamiast `--network=none`, użyć `--network=slirp4netns` + iptables allowlist
- **Secrets**: Podman secrets store dla API keys, `--secret id=opencode-env`

## 9. CI/CD

```yaml
build:
  script:
    - podman build -t opencode:bookworm-v1.0.0 .
    - trivy image opencode:bookworm-v1.0.0
```

- Tagowanie: `opencode:bookworm-v${OPENCODE_VERSION}` (immutable)
- Skanowanie: Trivy / Grype przed push

## 10. Uzasadnienie kluczowych decyzji

| Decyzja | Alternatywa | Powód |
|---------|------------|-------|
| `debian:bookworm-slim` (final) | UBI9 | Mniejszy obraz, brak zależności RHEL, AppArmor zamiast SELinux (Ubuntu host) |
| Multi-stage (Node w builder) | Node w runtime | `postinstall` nadpisuje wrapper natywnym binarym; Node niepotrzebny w runtime |
| `CMD` zamiast `ENTRYPOINT` | `ENTRYPOINT ["opencode"]` | Użytkownik może podać `--version`, `--help`, `sh` |
| Brak `:Z` w volume | `:Z` | Ubuntu używa AppArmor, SELinux ignorowany; flaga zbędna |
| Python3 zachowany | Bez Pythona | Użytkownik potrzebuje narzędzi Python w projekcie |
| Wersjonowanie `opencode-ai@1.17.9` | `opencode-ai` (latest) | Reproducowalność builda |
