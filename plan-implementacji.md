# Plan Implementacji — Konteneryzacja OpenCode CLI

> **Autor:** DevOps / Security Engineer  
> **Data:** 2026-06-21  
> **Wersja:** 1.0  
> **Status:** Szkic

---

## 1. Wymagania (Requirements)

### 1.1. Funkcjonalne
- OpenCode CLI działa w izolowanym kontenerze na systemie Linux Ubuntu 24
- Kontener zawiera: `opencode`, `git`, `python3`, `pip`, `nano`, `nmap`, `ping`, `ip`, `curl`, `wget`, `ca-certificates`
- Możliwość komunikacji wychodzącej (egress) do API zewnętrznych dostawców AI
- Możliwość montowania katalogu projektu z hosta do kontenera
- (Przyszłość) Montowanie `~/.ssh`, `~/.gitconfig`, `~/.config/opencode/`

### 1.2. Niefunkcjonalne
- Obraz < 800 MB
- Czas budowy < 5 minut w CI
- Uruchomienie kontenera < 2 sekundy
- Zero modyfikacji systemu hosta
- Obrazy publikowane na `ghcr.io`

### 1.3. Ograniczenia (Constraints)
- Silnik: **Podman rootless** (zakaz `--userns=keep-id`)
- Ubuntu 24 jako system hosta
- Kod źródłowy na GitHubie, CI/CD w GitHub Actions
- Zakaz używania Docker Hub (tylko ghcr.io)

---

## 2. Architektura i Bezpieczeństwo (Architecture & Security)

### 2.1. Diagram przepływu

```
┌─────────────────────────────────────────────────────────────┐
│                     Host (Ubuntu 24)                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │           Kontener Podman (rootless)                 │   │
│  │  ┌─────────┐  ┌────────┐  ┌──────────────────────┐  │   │
│  │  │ opencode │  │  git   │  │ python3, nmap, ping │  │   │
│  │  │  (bun)   │  │        │  │ ip, curl, wget, nano│  │   │
│  │  └────┬─────┘  └────────┘  └──────────────────────┘  │   │
│  │       │                                               │   │
│  │       ▼ (egress)                                      │   │
│  │  ┌──────────┐                                         │   │
│  │  │  Network │───► api.openai.com, api.anthropic.com, │   │
│  │  │  (wyj.)  │    ─► generativelanguage.googleapis.com │   │
│  │  └──────────┘    ─► api.mistral.ai, opencode.ai itd. │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  Volume: /home/user/project ──► /workspace (bind mount)     │
└─────────────────────────────────────────────────────────────┘
```

### 2.2. Sandboxing — flagi bezpieczeństwa

| Flaga | Opis |
|---|---|
| `--cap-drop=ALL` | Usunięcie wszystkich capability Linux |
| `--security-opt=no-new-privileges:true` | Blokada eskalacji uprawnień |
| `--read-only-rootfs` | System plików tylko do odczytu |
| `--tmpfs /tmp` | Tymczasowy zapis w RAM |
| `--tmpfs /home/opencode/.local/share/opencode` | Izolacja auth |
| `--network` | Ograniczenie do egress-only (patrz sekcja 3.2) |

### 2.3. Mapowanie użytkownika (rootless)

Bez `--userns=keep-id` — domyślne mapowanie Podmana:

- Użytkownik hosta (uid=N) → uid=0 w kontenerze  
- Podman automatycznie mapuje zakres `/etc/subuid`
- Wszystkie pliki tworzone w volume mają uid hosta

### 2.4. Wrażliwe pliki hosta (wersja przyszła)

Do montowania w SCOPE 3–4:
- `~/.ssh/` → `/home/opencode/.ssh/` (tylko do odczytu)
- `~/.gitconfig` → `/home/opencode/.gitconfig`
- `~/.config/opencode/` → `/home/opencode/.config/opencode/`

---

## 3. Implementacja — SCOPE 4-etapowy

---

### SCOPE 1: Containerfile i obraz podstawowy

| Element | Opis |
|---|---|
| **Scenariusz** | Budowa obrazu bazowego z opencode CLI |
| **Cel** | Działający obraz z opencode, git, python, narzędziami |
| **Ograniczenia** | Ubuntu 24, rootless Podman, ghcr.io |
| **Procedura weryfikacji** | `podman run --rm obraz opencode --version` |
| **Eskalacja** | Błąd kompilacji opencode → użyj oficjalnego binary |

#### Containerfile

```dockerfile
# Containerfile
# Etap 1: Pobranie opencode CLI
FROM ubuntu:24.04 AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://opencode.ai/install | bash -s -- --yes

# Etap 2: Obraz docelowy
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    python3 \
    python3-pip \
    python3-venv \
    nano \
    nmap \
    iproute2 \
    iputils-ping \
    curl \
    wget \
    ca-certificates \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/.opencode /opt/opencode

ENV PATH="/opt/opencode/bin:${PATH}"
ENV OPENCODE_HOME="/home/opencode/.opencode"

RUN groupadd -r opencode -g 1001 && \
    useradd -r -g opencode -u 1001 -m -d /home/opencode -s /bin/bash opencode

WORKDIR /workspace

USER opencode

ENTRYPOINT ["opencode"]
CMD []
```

#### Komenda budowy

```bash
podman build \
  --build-arg BUILDKIT_INLINE_CACHE=1 \
  --label "org.opencontainers.image.source=https://github.com/webbag/opencode-image" \
  --label "org.opencontainers.image.description=OpenCode CLI w kontenerze" \
  --label "org.opencontainers.image.licenses=MIT" \
  -t ghcr.io/webbag/opencode-image:latest \
  -f Containerfile .
```

---

### SCOPE 2: Bezpieczne uruchomienie i sieć

| Element | Opis |
|---|---|
| **Scenariusz** | Uruchomienie kontenera z pełnym sandboxingiem |
| **Cel** | Minimalizacja ryzyka container breakout |
| **Ograniczenia** | Egress-only do API AI, brak --userns=keep-id |
| **Procedura weryfikacji** | `nmap localhost` w kontenerze musi zwrócić błąd |
| **Eskalacja** | Jeśli API nieosiągalne → sprawdź DNS/iptables w kontenerze |

#### Skrypt uruchomieniowy `run.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/webbag/opencode-image:latest}"
WORKSPACE="${WORKSPACE:-$PWD}"

exec podman run \
  --rm \
  -it \
  --name opencode \
  --cap-drop=ALL \
  --security-opt=no-new-privileges:true \
  --security-opt=seccomp=unconfined \
  --read-only-rootfs \
  --tmpfs /tmp:noexec,nosuid,size=512M \
  --tmpfs /home/opencode/.local/share/opencode:noexec,nosuid,size=128M \
  --tmpfs /home/opencode/.cache:noexec,nosuid,size=256M \
  --tmpfs /home/opencode/.opencode:noexec,nosuid,size=128M \
  -v "${WORKSPACE}:/workspace:Z" \
  -v /etc/hosts:/etc/hosts:ro \
  --dns 1.1.1.1 \
  --dns 8.8.8.8 \
  "${IMAGE}" "$@"
```

> **Uwaga:** Użycie `--read-only-rootfs` wymaga tmpfs dla katalogów zapisu.

#### Network egress policy (iptables na hoście — opcjonalnie)

```bash
# Ograniczenie ruchu tylko z kontenera opencode do zaufanych API
# Identyfikacja sieci Podman: podman network inspect podman

# Otwórz egress tylko do zaufanych endpointów
ALLOWED_HOSTS=(
  "api.openai.com"
  "api.anthropic.com"
  "generativelanguage.googleapis.com"
  "api.mistral.ai"
  "api.groq.com"
  "api.deepseek.com"
  "api.together.xyz"
  "openrouter.ai"
  "opencode.ai"
  "api.github.com"
  "github.com"
  "raw.githubusercontent.com"
  "pypi.org"
  "files.pythonhosted.org"
  "registry.npmjs.org"
)

for host in "${ALLOWED_HOSTS[@]}"; do
  sudo iptables -A FORWARD -i podman1 -p tcp --dport 443 -d "$host" -j ACCEPT
  sudo iptables -A FORWARD -i podman1 -p tcp --dport 80 -d "$host" -j ACCEPT
done
sudo iptables -A FORWARD -i podman1 -j DROP
```

> Zastosowanie w SCOPE 4 jako hardening produkcyjny.

---

### SCOPE 3: Integracja z repozytorium i git

| Element | Opis |
|---|---|
| **Scenariusz** | Montowanie projektu z gitem, możliwość commit/push |
| **Cel** | W pełni funkcjonalne opencode w kontenerze |
| **Ograniczenia** | Klucze SSH i gitconfig muszą być dostępne |
| **Procedura weryfikacji** | `git status`, `git commit -m "test"`, `git push` |
| **Eskalacja** | Błąd SSH → sprawdź `~/.ssh/known_hosts` i permissions |

#### Rozszerzony `run.sh` (SCOPE 3)

```bash
#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/webbag/opencode-image:latest}"
WORKSPACE="${WORKSPACE:-$PWD}"

SSH_MOUNT=""
GITCONFIG_MOUNT=""
OPENCODE_CONFIG_MOUNT=""

if [ -d "$HOME/.ssh" ]; then
  SSH_MOUNT="-v $HOME/.ssh:/home/opencode/.ssh:ro"
fi
if [ -f "$HOME/.gitconfig" ]; then
  GITCONFIG_MOUNT="-v $HOME/.gitconfig:/home/opencode/.gitconfig:ro"
fi
if [ -d "$HOME/.config/opencode" ]; then
  OPENCODE_CONFIG_MOUNT="-v $HOME/.config/opencode:/home/opencode/.config/opencode:ro"
fi

SHARED_VOLUMES=()
if [ -n "$SSH_MOUNT" ]; then SHARED_VOLUMES+=("$SSH_MOUNT"); fi
if [ -n "$GITCONFIG_MOUNT" ]; then SHARED_VOLUMES+=("$GITCONFIG_MOUNT"); fi
if [ -n "$OPENCODE_CONFIG_MOUNT" ]; then SHARED_VOLUMES+=("$OPENCODE_CONFIG_MOUNT"); fi

exec podman run \
  --rm \
  -it \
  --name opencode \
  --cap-drop=ALL \
  --cap-add=DAC_OVERRIDE \
  --security-opt=no-new-privileges:true \
  --read-only-rootfs \
  --tmpfs /tmp:noexec,nosuid,size=512M \
  --tmpfs /home/opencode/.local/share/opencode:noexec,nosuid,size=128M \
  --tmpfs /home/opencode/.cache:noexec,nosuid,size=256M \
  --tmpfs /home/opencode/.opencode:noexec,nosuid,size=128M \
  --tmpfs /home/opencode/.config/git:exec,size=64M \
  -v "${WORKSPACE}:/workspace:Z" \
  "${SHARED_VOLUMES[@]}" \
  --dns 1.1.1.1 \
  --dns 8.8.8.8 \
  "${IMAGE}" "$@"
```

> **Uwaga:** `--cap-add=DAC_OVERRIDE` jest potrzebne dla `~/.ssh` z uprawnieniami 600.

---

### SCOPE 4: CI/CD i publikacja obrazów

| Element | Opis |
|---|---|
| **Scenariusz** | Automatyczne budowanie i publikacja obrazów |
| **Cel** | CI/CD w GitHub Actions → ghcr.io |
| **Ograniczenia** | Budowanie w GitHub Actions, push do ghcr.io |
| **Procedura weryfikacji** | `podman pull ghcr.io/webbag/opencode-image:latest` |
| **Eskalacja** | Błąd budowy → sprawdź logi GitHub Actions |

#### GitHub Actions — `.github/workflows/build.yml`

```yaml
name: Build and publish image

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 6 * * 1'  # co poniedziałek

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      packages: write
      attestations: write
      id-token: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install Podman
        run: |
          sudo apt-get update
          sudo apt-get install -y podman

      - name: Log in to GitHub Container Registry
        uses: redhat-actions/podman-login@v1
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build image
        run: |
          podman build \
            --label "org.opencontainers.image.source=${{ github.server_url }}/${{ github.repository }}" \
            --label "org.opencontainers.image.revision=${{ github.sha }}" \
            --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
            -t "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}" \
            -t "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest" \
            -f Containerfile .

      - name: Push image
        if: github.event_name != 'pull_request'
        run: |
          podman push "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}"
          podman push "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest"

      - name: Tag and push version
        if: startsWith(github.ref, 'refs/tags/v')
        run: |
          VERSION=${GITHUB_REF#refs/tags/}
          podman tag "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}" \
            "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:$VERSION"
          podman push "${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:$VERSION"
```

#### Tagowanie obrazów

| Tag | Opis |
|---|---|
| `latest` | Ostatnia stabilna wersja z main |
| `vX.Y.Z` | Release semver |
| `sha-<commit>` | (domyślnie) weryfikowalny |
| `nightly` | Codzienna nocna (opcjonalnie) |

---

## 4. Testowanie

### 4.1. Testy integracyjne

```bash
#!/usr/bin/env bash
# tests/test.bats — Bats test framework
# Instalacja: sudo apt install bats

setup() {
  IMAGE="ghcr.io/webbag/opencode-image:latest"
}

@test "opencode --version" {
  run podman run --rm "$IMAGE" opencode --version
  [ "$status" -eq 0 ]
}

@test "git version" {
  run podman run --rm "$IMAGE" git --version
  [ "$status" -eq 0 ]
}

@test "python3 version" {
  run podman run --rm "$IMAGE" python3 --version
  [ "$status" -eq 0 ]
}

@test "nano installed" {
  run podman run --rm "$IMAGE" which nano
  [ "$status" -eq 0 ]
}

@test "nmap installed" {
  run podman run --rm "$IMAGE" which nmap
  [ "$status" -eq 0 ]
}

@test "ping installed" {
  run podman run --rm "$IMAGE" which ping
  [ "$status" -eq 0 ]
}

@test "no capabilities" {
  run podman run --rm --cap-drop=ALL "$IMAGE" sh -c 'cat /proc/1/status | grep CapEff'
  [[ "$output" == "CapEff:	0000000000000000" ]]
}

@test "rootfs is read-only" {
  run podman run --rm --read-only-rootfs "$IMAGE" touch /test
  [ "$status" -ne 0 ]
}

@test "curl to openai.com" {
  run podman run --rm "$IMAGE" curl -s -o /dev/null -w "%{http_code}" \
    https://api.openai.com/v1/models
  [ "$status" -eq 0 ]
}

@test "no network to internal host" {
  run podman run --rm "$IMAGE" ping -c 1 -W 2 10.0.0.1
  [ "$status" -ne 0 ]
}
```

### 4.2. Testy bezpieczeństwa

```bash
#!/usr/bin/env bash
# test-security.sh

IMAGE="ghcr.io/webbag/opencode-image:latest"
PASS=0
FAIL=0

check() {
  local desc="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "  ✔ $desc"
    ((PASS++))
  else
    echo "  ✘ $desc"
    ((FAIL++))
  fi
}

echo "=== Testy bezpieczeństwa ==="

# 1. Próba montowania /host (powinna się nie udać)
check "Brak dostępu do /host" \
  podman run --rm "$IMAGE" test -f /host/etc/shadow

# 2. Sprawdzenie no-new-privileges
check "no-new-privileges aktywny" \
  podman run --rm --security-opt=no-new-privileges:true \
    "$IMAGE" sh -c 'grep -q "NoNewPrivs:.*true" /proc/1/status 2>/dev/null'

# 3. Próba uruchomienia setuid
check "setuid zablokowany" \
  ! podman run --rm --cap-drop=ALL \
    "$IMAGE" sh -c 'chmod u+s /tmp/test 2>/dev/null; ls -la /tmp/test 2>/dev/null | grep -q s'

echo "---"
echo "Passed: $PASS, Failed: $FAIL"
[ "$FAIL" -eq 0 ]
```

---

## 5. CI/CD — szczegóły

### 5.1. Pipeline GitHub Actions

```
┌─────────────┐    ┌──────────────┐    ┌──────────────┐    ┌─────────────┐
│   Checkout  │───►│  Podman      │───►│  Test        │───►│  Push       │
│   źródła    │    │  Build       │    │  (bats)      │    │  do ghcr.io │
└─────────────┘    └──────────────┘    └──────────────┘    └─────────────┘
```

### 5.2. Zmienne środowiskowe i secrety

| Secret | Opis |
|---|---|
| `GITHUB_TOKEN` | Automatyczny, dostęp do packages |
| (opcjonalnie) `REGISTRY_PASSWORD` | Jeśli nie GHCR |

### 5.3. Harmonogram publikacji

| Trigger | Akcja |
|---|---|
| Push do `main` | Budowa + test + push `latest` |
| Tag `v*` | Budowa + test + push `vX.Y.Z` + `latest` |
| PR do `main` | Budowa + test (bez push) |
| `cron` (poniedziałek 6:00) | Nocna przebudowa + push `nightly` |

---

## 6. Utrzymanie (Maintenance)

### 6.1. Aktualizacja opencode w kontenerze

```bash
# Ręczna aktualizacja
podman run --rm -it ghcr.io/webbag/opencode-image:latest opencode upgrade

# Przebudowa obrazu (opcja lepsza — odświeża całość)
git pull && podman build -t ghcr.io/webbag/opencode-image:latest .
```

### 6.2. Znane problemy i rozwiązania

| Problem | Rozwiązanie |
|---|---|
| `--read-only-rootfs` blokuje zapis | Użyj `--tmpfs` dla katalogów zapisu |
| DNS nie działa w kontenerze | Dodaj `--dns 1.1.1.1` |
| git push wymaga SSH agenta | Zamontuj `$SSH_AUTH_SOCK` lub klucze `ro` |
| opencode nie ma configu | Zamontuj `~/.config/opencode/` |
| Permissions denied na volume | Użyj `:Z` (SELinux) lub `:z` |
| Błąd `--cap-add=DAC_OVERRIDE` z SSH | Ustaw `~/.ssh/id_*` na 600 na hoście |

### 6.3. Skrypt pomocniczy `oc.sh`

```bash
#!/usr/bin/env bash
# oc.sh — wrapper dla wygody
# Użycie: ./oc.sh "twoja wiadomość"
#         ./oc.sh run "opisz ten kod"

IMAGE="${IMAGE:-ghcr.io/webbag/opencode-image:latest}"
WORKSPACE="${WORKSPACE:-$PWD}"

PODMAN_OPTS=(
  --rm -it --name opencode
  --cap-drop=ALL
  --security-opt=no-new-privileges:true
  --read-only-rootfs
  --tmpfs /tmp:noexec,nosuid,size=512M
  --tmpfs /home/opencode/.local/share/opencode:noexec,nosuid,size=128M
  --tmpfs /home/opencode/.cache:noexec,nosuid,size=256M
  --tmpfs /home/opencode/.opencode:noexec,nosuid,size=128M
  -v "${WORKSPACE}:/workspace:Z"
)

if [ -d "$HOME/.ssh" ]; then
  PODMAN_OPTS+=(-v "$HOME/.ssh:/home/opencode/.ssh:ro")
fi
if [ -f "$HOME/.gitconfig" ]; then
  PODMAN_OPTS+=(-v "$HOME/.gitconfig:/home/opencode/.gitconfig:ro")
fi
if [ -d "$HOME/.config/opencode" ]; then
  PODMAN_OPTS+=(-v "$HOME/.config/opencode:/home/opencode/.config/opencode:ro")
fi

exec podman run "${PODMAN_OPTS[@]}" "${IMAGE}" "$@"
```

---

## 7. Podsumowanie SCOPE

| SCOPE | Opis | Status |
|---|---|---|
| **1** | Containerfile + obraz podstawowy (opencode, git, python, narzędzia) | Do implementacji |
| **2** | Bezpieczne uruchomienie (sandboxing, egress, tmpfs) | Do implementacji |
| **3** | Integracja z hostem (git, SSH, gitconfig, opencode config) | Do implementacji |
| **4** | CI/CD (GitHub Actions → ghcr.io, tagowanie, testy) | Do implementacji |

---

## 8. Referencje

- [OpenCode CLI Docs](https://opencode.ai/docs)
- [Podman Rootless Tutorial](https://github.com/containers/podman/blob/main/docs/tutorials/rootless_tutorial.md)
- [GitHub Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Open Container Initiative — Labels](https://github.com/opencontainers/image-spec/blob/main/annotations.md)
- [NIST Container Security Guide](https://www.nist.gov/publications/application-container-security-guide)
