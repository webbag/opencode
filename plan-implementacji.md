# Plan implementacji — Konteneryzacja OpenCode CLI

> **Status dokumentu:** Roboczy v2  
> **Data:** 2026-06-21  
> **Autor:** DevOps/Security Engineer  
> **Cel:** Rootless Podman container dla OpenCode CLI z sandboxingiem i CI/CD do ghcr.io  
> **GitHub:** [webbag/opencode](https://github.com/webbag/opencode)  
> **Rejestr obrazów:** `ghcr.io/webbag/opencode`

---

## Spis treści

1. [Wymagania](#1-wymagania)
2. [Architektura i Bezpieczeństwo](#2-architektura-i-bezpieczeństwo)
3. [Plan implementacji (SCOPE)](#3-plan-implementacji-scope)
   - [SCOPE 1: Obraz bazowy i narzędzia](#scope-1-obraz-bazowy-i-narzędzia)
   - [SCOPE 2: Bezpieczeństwo i sandboxing](#scope-2-bezpieczeństwo-i-sandboxing)
   - [SCOPE 3: Sieć i integracja z API](#scope-3-sieć-i-integracja-z-api)
   - [SCOPE 4: CI/CD i publikacja](#scope-4-cicd-i-publikacja)
4. [Testowanie](#4-testowanie)
5. [Utrzymanie](#5-utrzymanie)

---

## 1. Wymagania

### 1.1 Funkcjonalne

| ID | Wymaganie | Priorytet |
|---|---|---|
| F-01 | Kontener uruchamia OpenCode CLI w trybie TUI i headless | Krytyczny |
| F-02 | Obraz zawiera: opencode CLI, git, Python 3, nano | Krytyczny |
| F-03 | Obraz zawiera narzędzia diagnostyczne: nmap, ping/ping6, ip (iproute2), curl, wget | Wysoki |
| F-04 | Kontener ma dostęp wychodzący (egress) do API: OpenAI, Anthropic, Google, Mistral, OpenCode Zen | Krytyczny |
| F-05 | OpenCode może przeszukiwać internet (websearch) i pobierać treści z wielu stron (webfetch) | Krytyczny |
| F-06 | OpenCode wewnątrz kontenera może zapisywać pliki do montowanego wolumenu | Wysoki |
| F-07 | W przyszłości (v2): montowanie ~/.ssh, ~/.gitconfig z hosta | Średni |
| F-08 | W przyszłości (v2): wysyłanie artefaktów do GitHub z kontenera | Średni |

### 1.2 Niefunkcjonalne

| ID | Wymaganie | Priorytet |
|---|---|---|
| NF-01 | Silnik: Podman w trybie rootless na Ubuntu 24.04 | Krytyczny |
| NF-02 | Mapowanie UID/GID bez `--userns=keep-id` | Krytyczny |
| NF-03 | Wszystkie capability zrzucone (`--cap-drop=ALL`) | Krytyczny |
| NF-04 | `no-new-privileges` włączone | Krytyczny |
| NF-05 | Obraz publikowany na `ghcr.io` przez GitHub Actions | Krytyczny |
| NF-06 | Kod źródłowy (Containerfile + skrypty) na GitHubie | Krytyczny |
| NF-07 | Wieloarchitekturowość (linux/amd64, linux/arm64) | Wysoki |
| NF-08 | Rozmiar obrazu ≤ 1.5 GB | Średni |

### 1.3 Ograniczenia (Constraints)

- Brak `--userns=keep-id` — mapowanie przez Podman `--uidmap` / `--gidmap`
- AVX wymagane przez opencode → CPU type `host` w QEMU/KVM
- Binary opencode waży ~157 MB — wpływa na czas budowy
- OpenCode nie ma oficjalnego Dockerfile — budujemy od zera

---

## 2. Architektura i Bezpieczeństwo

### 2.1 Architektura kontenera

```
┌─────────────────────────────────────────────────────────┐
│                    Host (Ubuntu 24.04)                   │
│  ┌───────────────────────────────────────────────────┐  │
│  │           Podman rootless (uid=1000)               │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │         Kontener OpenCode                     │  │  │
│  │  │  ┌───────────────────────────────────────┐  │  │  │
│  │  │  │  opencode CLI (TUI / headless)         │  │  │  │
│  │  │  ├───────────────────────────────────────┤  │  │  │
│  │  │  │  Narzędzia: git, python3, nano        │  │  │  │
│  │  │  ├───────────────────────────────────────┤  │  │  │
│  │  │  │  Diagnostyka: nmap, ping, ip          │  │  │  │
│  │  │  ├───────────────────────────────────────┤  │  │  │
│  │  │  │  Użytkownik: opencode (uid=1000)      │  │  │  │
│  │  │  └───────────────────────────────────────┘  │  │  │
│  │  │        │                                     │  │  │
│  │  │        ▼                                     │  │  │
│  │  │  ┌──────────┐   ┌───────────────────────────┐│  │  │
│  │  │  │ Volumes  │   │  Network egress           ││  │  │
│  │  │  │ /workdir │   │  → api.openai.com         ││  │  │
│  │  │  │ /config  │   │  → api.anthropic.com     ││  │  │
│  │  │  └──────────┘   │  → api.google.*           ││  │  │
│  │  │                 │  → api.mistral.ai          ││  │  │
│  │  │                 │  → api.opencode.ai         ││  │  │
│  │  │                 │  → Internet (websearch)    ││  │  │
│  │  │                 │    → dowolna domena/strona ││  │  │
│  │  │                 └───────────────────────────┘│  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### 2.2 Model bezpieczeństwa

| Warstwa | Mechanizm | Uzasadnienie |
|---|---|---|
| **Capabilities** | `--cap-drop=ALL` | Eliminuje wszystkie capability Linuksa — kontener nie może wykonywać operacji wymagających przywilejów (mount, raw socket, ptrace itp.) |
| **Nowe privileges** | `--security-opt=no-new-privileges` | Zapobiega eskalacji przez setuid/binary z capability |
| **User namespace** | Podman rootless + `--uidmap` | Domyślne mapowanie użytkownika host → root/boundary w kontenerze; unikamy `keep-id`, które mapuje host UID 1:1 |
| **Seccomp** | Domyślny profil Podmana | Ogranicza dostępne syscalle |
| **Filesystem** | Volumes tylko do odczytu (gdzie możliwe) | Zmniejsza ryzyko modyfikacji binarek kontenera |
| **SELinux/AppArmor** | Profil `container` (domyślny) | Dodatkowa izolacja na Ubuntu |

### 2.3 Zarządzanie tożsamością

- Użytkownik w kontenerze: **opencode** (UID 1000) — odpowiada domyślnemu UID użytkownika na typowym hoście Ubuntu
- Mapowanie: UID 1000 hosta → UID 1000 w kontenerze (za pomocą `--uidmap`, a nie `--userns=keep-id`)
- Grupa: **opencode** (GID 1000)

Mapowanie realizowane przez:

```bash
# Automatyczne mapowanie (Podman rootless):
# Host UID=1000 → Container UID=0..65535 przez /etc/subuid
# My tworzymy własne mapowanie by uniknąć keep-id:
podman run --uidmap=0:100000:1000 --uidmap=1000:1000:1 --uidmap=1001:101001:64536 ...
```

**Uwaga:** Rzeczywiste mapowanie zależy od konfiguracji `/etc/subuid` i `/etc/subgid` na hoście. W rootless Podman domyślnie: uid 1000 hosta → uid 0 w kontenerze. Aby zachować uid 1000 wewnątrz bez `keep-id`, stosujemy jawne `--uidmap`.

### 2.4 Obsługa wolumenów (v1 vs v2)

**Wersja 1 (obecna):**
- Montowany wolumen roboczy: `-v /host/project:/workdir:Z`
- Plik konfiguracyjny opencode montowany: `-v /host/config:/home/opencode/.config/opencode:Z`

**Wersja 2 (przyszłość):**
- Montowanie `~/.ssh`: `-v /home/user/.ssh:/home/opencode/.ssh:ro,Z`
- Montowanie `~/.gitconfig`: `-v /home/user/.gitconfig:/home/opencode/.gitconfig:ro,Z`
- Montowanie `~/.git-credentials`: `-v /home/user/.git-credentials:/home/opencode/.git-credentials:ro,Z`
- Obsługa `git push` przez SSH z kluczami z hosta

---

## 3. Plan implementacji (SCOPE)

Projekt podzielono na **4 etapy (SCOPE)**. Każdy SCOPE zawiera:

| Element | Opis |
|---|---|
| **S**cenariusz | Kontekst i przypadek użycia |
| **C**el | Konkretny, mierzalny rezultat |
| **O**graniczenia | Znane limity i założenia |
| **P**rocedura weryfikacji | Jak sprawdzamy poprawność |
| **E**skalacja | Co robimy przy niepowodzeniu |

---

### SCOPE 1: Obraz bazowy i narzędzia

#### Scenariusz

Użytkownik buduje obraz kontenera zawierający wszystkie wymagane narzędzia: opencode CLI, git, Python 3, nmap, ping, iproute2, nano. Obraz musi być gotowy na Ubuntu 24.04 (LTS) z uruchomieniem opencode w trybie TUI lub headless.

#### Cel

- Działający `Containerfile` budujący obraz z Ubuntu 24.04
- Zainstalowane: opencode CLI (najnowsza stable), git, python3, python3-pip, nano
- Zainstalowane narzędzia: nmap, iputils-ping, iproute2
- Użytkownik `opencode` (UID/GID 1000) z domyślnym shellem `/bin/bash`
- Wolumen roboczy `/home/opencode/workdir`
- Binary opencode dostępny w `$PATH` dla użytkownika `opencode`

#### Ograniczenia

- AVX wymagane przez opencode — CPU type `host` w VM
- Obraz musi być budowalny na amd64 i arm64
- Rozmiar ≤ 1.5 GB
- Brak warstwy sieciowej w tym SCOPE

#### Procedura weryfikacji

```bash
# 1. Budowa obrazu
podman build -t opencode:scope1 -f Containerfile .

# 2. Uruchomienie testowe
podman run --rm -it opencode:scope1 /bin/bash -c "
  opencode --version &&
  git --version &&
  python3 --version &&
  nmap --version &&
  ping -c 1 127.0.0.1 &&
  ip addr &&
  nano --version &&
  whoami
"

# 3. Sprawdzenie rozmiaru
podman images opencode:scope1 --format '{{.Size}}'
```

#### Eskalacja

- Problem z AVX → sprawdź `cat /proc/cpuinfo | grep avx` na hoście; użyj `--cpuset-cpus` dla dedykowanych rdzeni
- Binary opencode nie działa → pobierz binarkę z GitHub Releases zamiast skryptem instalacyjnym
- Zbyt duży obraz → przeanalizuj warstwy `podman history` i rozdziel instalacje

---

### SCOPE 2: Bezpieczeństwo i sandboxing

#### Scenariusz

Uruchomienie kontenera z maksymalnym ograniczeniem uprawnień. AI może wygenerować złośliwy kod — kontener musi uniemożliwiać ucieczkę (container breakout), eskalację przywilejów i modyfikację krytycznych zasobów systemowych.

#### Cel

- Kontener uruchomiony z `--cap-drop=ALL`
- `--security-opt=no-new-privileges=true`
- Użytkownik `opencode` (UID 1000) bez praw `sudo`
- Mapowanie UID przez `--uidmap`/`--gidmap` bez `--userns=keep-id`
- Root wewnątrz kontenera (UID 0) — jeśli istnieje — nie ma rzeczywistych uprawnień na hoście
- Domyślny profil seccomp Podmana
- Potwierdzenie, że `ip link` (operacje wymagające CAP_NET_ADMIN) nie działają

#### Ograniczenia

- `nmap` wymaga CAP_NET_RAW do skanowania SYN — z `--cap-drop=ALL` będzie działał tylko w trybie połączeniowym (`-sT`)
- `ping` wymaga CAP_NET_RAW lub setcap → nie będzie działał
- Nie używamy `--privileged`, `--device`, `--pid=host`

**Decyzja:** `nmap` i `ping` będą działać w ograniczonym zakresie. Są to narzędzia *diagnostyczne*, nie pentesterskie. Akceptujemy to jako feature, nie bug.

#### Procedura weryfikacji

```bash
# 1. Uruchomienie z flagami bezpieczeństwa
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --uidmap=0:100000:1000 \
  --uidmap=1000:1000:1 \
  --uidmap=1001:101001:64536 \
  opencode:scope2

# 2. Weryfikacja wewnątrz kontenera
cat /proc/self/status | grep -E "CapEff|CapInh|NoNewPrivs|Uid"
# Oczekiwane: CapEff=0000000000000000, NoNewPrivs=1, Uid=1000

# 3. Próba eskalacji (powinna się nie udać)
sudo -l           # → nie ma sudo
capsh --print     # → wszystkie capability = 0
ping -c 1 8.8.8.8 # → permission denied (lub works tylko z setcap)
```

#### Eskalacja

- `ping` całkowicie nie działa → rozważ dodanie `--cap-add=CAP_NET_RAW` tylko dla tego przypadku, ale to *obniża* bezpieczeństwo. Alternatywnie: użyj `nping` (z nmap) w trybie TCP: `nping --tcp -p 80 8.8.8.8`
- Procesy dziecka uciekają → dodaj `--pids-limit=100`
- Potrzebny dostęp do hosta → rozważ `--read-only-rootfs` z tmpfs dla `/tmp`

---

### SCOPE 3: Sieć, web search i integracja z API

#### Scenariusz

Kontener musi łączyć się z zewnętrznymi API modeli językowych oraz przeszukiwać internet. OpenCode CLI ma wbudowane narzędzia `websearch` (wyszukiwanie w sieci) i `webfetch` (pobieranie treści stron), które są używane przez agenta `plan` i inne podagenty do zbierania informacji. Ruch sieciowy jest wyłącznie wychodzący (egress) — do domen API oraz dowolnych stron internetowych.

#### Cel

- Wychodzący ruch HTTPS działa dla domen API: `api.openai.com`, `api.anthropic.com`, `generativelanguage.googleapis.com`, `api.mistral.ai`, `api.opencode.ai`
- OpenCode może przeszukiwać internet w poszukiwaniu informacji (dowolne domeny)
- OpenCode może pobierać (fetch) treści z dowolnych stron WWW
- Domyślna sieć Podmana (bridge/pasta) z translacją NAT dla pełnego egressu
- Zainstalowane narzędzia pomocnicze: curl, wget (przydatne do diagnostyki i web scrapingu)
- Sprawdzona łączność przez `curl -v https://api.opencode.ai` oraz `curl -v https://example.com`
- Konfiguracja uwierzytelniania przez zmienne środowiskowe lub montowany config

#### Ograniczenia

- Brak wchodzącego ruchu (ingress) — kontener nie nasłuchuje na portach
- DNS musi działać w kontenerze dla rozwiązywania dowolnych domen
- Proxy HTTP może być potrzebne w środowiskach korporacyjnych — `$HTTP_PROXY`, `$HTTPS_PROXY`
- Web search wymaga API wyszukiwarki (np. `OPENCODE_SEARCH_API_KEY`) — klucz jest przekazywany jako zmienna środowiskowa
- `webfetch` działa przez czyste HTTP/HTTPS — nie wymaga dodatkowych uprawnień

#### Procedura weryfikacji

```bash
# 1. Uruchomienie z API key dla web search
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -e OPENAI_API_KEY="sk-..." \
  -e OPENCODE_SEARCH_API_KEY="..." \
  -v "$(pwd)/opencode.json:/home/opencode/.config/opencode/opencode.json:ro,Z" \
  -v "$(pwd)/projekt:/home/opencode/workdir:Z" \
  opencode:scope3

# 2. Test web search przez opencode (headless)
podman run --rm -it opencode:scope3 \
  opencode run "Wyszukaj najnowsze informacje o Python 3.13"

# 3. Test webfetch — pobranie treści strony
podman run --rm -it opencode:scope3 \
  opencode run "Pobierz i streść artykuł z https://docs.python.org/3/whatsnew/3.13.html"

# 4. Test łączności z API
podman run --rm -it opencode:scope3 \
  curl -s -o /dev/null -w "%{http_code}" https://api.opencode.ai

# 5. Test łączności z ogólnym internetem
podman run --rm -it opencode:scope3 \
  curl -s -o /dev/null -w "%{http_code}" https://example.com

# 6. Sprawdzenie, czy nie ma nasłuchujących portów
podman run --rm -it opencode:scope3 ss -tlnp
# Oczekiwane: puste (brak nasłuchujących)
```

#### Eskalacja

- API nieosiągalne → sprawdź firewall hosta, sprawdź DNS (`dig api.openai.com`), sprawdź przekierowania Podmana (`podman system connection list`)
- Web search nie działa → sprawdź `OPENCODE_SEARCH_API_KEY` — opencode wymaga klucza do API wyszukiwarki (np. Brave, Google Custom Search, Bing)
- `webfetch` nie działa → sprawdź, czy domena nie jest blokowana przez firewall; sprawdź certyfikaty TLS (`curl -v` pokaze szczegóły)
- Potrzebny proxy → dodaj `-e HTTP_PROXY=http://proxy:port` i `-e HTTPS_PROXY=http://proxy:port`
- Limit czasu połączenia → opencode ma wbudowany timeout; zwiększ przez `OPENCODE_TIMEOUT`
- Strona zwraca CAPTCHA → web scraping może być blokowany; opencode `webfetch` pobiera czysty HTML, nie wykonuje JS

---

### SCOPE 4: CI/CD i publikacja

#### Scenariusz

Automatyczna budowa i publikacja obrazów do GitHub Container Registry (ghcr.io) przy każdym tagu lub pushu do gałęzi głównej. Obrazy budowane zarówno dla linux/amd64, jak i linux/arm64.

#### Cel

- GitHub Actions workflow budujący obrazy na push do `main` i na tagi semver (v*)
- Publikacja na `ghcr.io/webbag/opencode`
- Build wieloarchitekturowy (linux/amd64, linux/arm64) z QEMU + buildx (podman buildx)
- Obrazy z podwójnym tagiem: `ghcr.io/webbag/opencode:latest`, `ghcr.io/webbag/opencode:1.2.3`
- Automatyczny README w ghcr.io z instrukcją użycia
- Scan bezpieczeństwa (Trivy) po zbudowaniu

#### Ograniczenia

- GHCR wymaga `write` permissions dla `GITHUB_TOKEN`
- Budget Actions: ~2000 min/miesiąc (free tier) — build może trwać 15-20 min
- Budowa na arm64 wymaga emulacji QEMU — może być wolniejsza
- Trivy scan wymaga osobnej konfiguracji

#### Procedura weryfikacji

```bash
# 1. Ręczna bubowa (symulacja CI)
podman build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/webbag/opencode:test \
  -f Containerfile .

# 2. Push testowy
podman push ghcr.io/webbag/opencode:test

# 3. Pociągnięcie i uruchomienie
podman pull ghcr.io/webbag/opencode:test
podman run --rm -it ghcr.io/webbag/opencode:test opencode --version

# 4. Skany bezpieczeństwa
trivy image ghcr.io/webbag/opencode:test
```

#### Eskalacja

- Brak uprawnień do ghcr.io → skonfiguruj `GITHUB_TOKEN` z `packages: write` w repository secrets
- Build arm64 failuje w QEMU → sprawdź CPU type (`--cpu=host`), AVX dla opencode na arm64 nie jest wymagane (ARM64 ma NEON)
- Przekroczony limit czasu → zoptymalizuj warstwy, użyj cache z ghcr.io (`--cache-from`)

---

## 4. Testowanie

### 4.1 Testy jednostkowe (Containerfile)

```bash
# Test składni Containerfile
podman build --no-cache -t opencode:test -f Containerfile . 2>&1 | grep -i error
```

### 4.2 Testy integracyjne

```bash
#!/bin/bash
# test_integration.sh
set -euo pipefail

IMAGE="opencode:test"
WORKDIR="/tmp/opencode-test-$$"

cleanup() {
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

mkdir -p "$WORKDIR"

echo "=== Test 1: OpenCode version ==="
podman run --rm "$IMAGE" opencode --version

echo "=== Test 2: Git działa ==="
podman run --rm "$IMAGE" git --version

echo "=== Test 3: Python działa ==="
podman run --rm "$IMAGE" python3 -c "print('OK')"

echo "=== Test 4: Użytkownik opencode ==="
podman run --rm "$IMAGE" whoami | grep opencode

echo "=== Test 5: Zapis do wolumenu ==="
podman run --rm -v "$WORKDIR:/home/opencode/workdir:Z" "$IMAGE" \
  bash -c "echo test > /home/opencode/workdir/test.txt"
cat "$WORKDIR/test.txt" | grep test

echo "=== Test 6: Capabilities ==="
podman run --rm --cap-drop=ALL "$IMAGE" \
  bash -c "cat /proc/self/status | grep CapEff" | grep 0000000000000000

echo "=== Test 7: Sieć (egress) do API ==="
podman run --rm "$IMAGE" curl -s -o /dev/null -w "%{http_code}" https://api.opencode.ai

echo "=== Test 8: Sieć (egress) do ogólnego internetu ==="
podman run --rm "$IMAGE" curl -s -o /dev/null -w "%{http_code}" https://example.com

echo "=== Test 9: nmap działa w trybie TCP ==="
podman run --rm "$IMAGE" nmap -sT -p 443 openai.com | grep open

echo "=== Test 10: Web fetch (pobranie strony) ==="
podman run --rm "$IMAGE" curl -s https://example.com | grep "Example Domain"

echo "=== Test 11: wget działa ==="
podman run --rm "$IMAGE" wget --version

echo "=== WSZYSTKIE TESTY ZALICZONE ==="
```

### 4.3 Testy bezpieczeństwa

```bash
# Trivy scan
trivy image --severity CRITICAL,HIGH --no-progress opencode:test

# Sprawdzenie czy kontener może uciec (manual)
podman run --rm --cap-drop=ALL "$IMAGE" \
  bash -c "
    # Próba mountowania
    mount /dev/sda1 /mnt 2>&1 || echo 'mount blocked - OK'
    # Próba dostępu do /dev
    ls -la /dev/sda* 2>&1 || echo 'no block devices - OK'
    # Próba dostępu do kernel modules
    lsmod 2>&1 || echo 'no lsmod - OK'
  "
```

---

## 5. Utrzymanie

### 5.1 Aktualizacje obrazu

- **OpenCode CLI**: Rebuild obrazu przy każdym release opencode (trigger z GitHub Releases)
- **System packages**: Comiesięczny rebuild z `apt update && apt upgrade`
- **CVEs**: Monitorowanie przez Dependabot + Trivy w CI

### 5.2 Proces aktualizacji

```bash
# Ręczna aktualizacja opencode wersji
podman build \
  --build-arg OPENCODE_VERSION=v1.17.10 \
  -t ghcr.io/webbag/opencode:1.17.10 \
  -t ghcr.io/webbag/opencode:latest \
  -f Containerfile .
```

### 5.3 Backup konfiguracji

```bash
# Konfiguracja opencode w kontenerze
podman run --rm -v opencode-config:/home/opencode/.config/opencode "$IMAGE" \
  opencode config list
```

### 5.4 Monitoring i logowanie

- Logi kontenera przez `podman logs <container>`
- Logi opencode: `~/.local/state/opencode/logs/` na wolumenie
- Healthcheck: opcjonalnie `--health-cmd "opencode --version"`

### 5.5 Plan na wersję 2 (przyszłość)

| Obszar | Co należy dodać |
|---|---|
| **SSH klucze** | Montowanie `~/.ssh/*` z hosta (`ro,Z`) |
| **Git config** | Montowanie `~/.gitconfig` i `~/.git-credentials` |
| **Git push** | Test `git push` przez SSH do GitHub z wnętrza kontenera |
| **OpenCode serve** | Odsłonięcie portu (np. -p 8080:8080) dla trybu HTTP server |
| **docker-compose** | Plik compose dla łatwego uruchamiania |
| **SELinux** | Dodanie własnego profilu SELinux dla kontenera |
| **Read-only rootfs** | `--read-only-rootfs` z tmpfs na `/tmp` i `/var` |

---

## A. Containerfile

```dockerfile
# Containerfile — OpenCode CLI w rootless Podman
# Bazuje na Ubuntu 24.04 LTS
# Budowa: podman build -t opencode:latest -f Containerfile .

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION} AS base

LABEL org.opencontainers.image.title="OpenCode CLI Container"
LABEL org.opencontainers.image.description="Rootless Podman container for OpenCode AI coding agent"
LABEL org.opencontainers.image.source="https://github.com/webbag/opencode"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="1.0.0"

# ============================================================
# SCOPE 1: System packages and tools
# ============================================================

RUN apt-get update && apt-get upgrade -y && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    # Podstawowe narzędzia
    git \
    python3 \
    python3-pip \
    python3-venv \
    nano \
    curl \
    ca-certificates \
    # Narzędzia diagnostyczne i web
    nmap \
    iputils-ping \
    iproute2 \
    dnsutils \
    netcat-openbsd \
    wget \
    # Narzędzia systemowe
    bash \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# SCOPE 1: OpenCode CLI installation
# ============================================================

ARG OPENCODE_VERSION=latest
ARG TARGETARCH

# Instalacja opencode przez oficjalny skrypt
RUN curl -fsSL https://opencode.ai/install | bash -s -- ${OPENCODE_VERSION} && \
    ln -sf /root/.opencode/bin/opencode /usr/local/bin/opencode

# Weryfikacja instalacji
RUN opencode --version

# ============================================================
# SCOPE 2: User setup (sandboxing)
# ============================================================

RUN groupadd -g 1000 opencode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash opencode && \
    mkdir -p /home/opencode/workdir /home/opencode/.config/opencode /home/opencode/.local && \
    chown -R opencode:opencode /home/opencode

# Przyznajemy caps net_raw do ping (opcjonalnie)
# RUN setcap cap_net_raw+p /bin/ping

# ============================================================
# SCOPE 3: Configuration and entrypoint
# ============================================================

# Kopiujemy domyślną konfigurację (jeśli istnieje)
# COPY opencode.json /home/opencode/.config/opencode/opencode.json

# Ustawiamy zmienne środowiskowe
ENV HOME=/home/opencode
ENV OPENCODE_HOME=/home/opencode/.config/opencode
ENV PATH="/home/opencode/.local/bin:${PATH}"

WORKDIR /home/opencode/workdir

# Użytkownik domyślny
USER opencode

# Entrypoint
ENTRYPOINT ["opencode"]
CMD ["--help"]
```

### Budowa i uruchomienie (kompletne)

```bash
# Budowa
podman build \
  --build-arg OPENCODE_VERSION=latest \
  -t opencode:latest \
  -f Containerfile .

# Uruchomienie z pełnym sandboxingiem
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --uidmap=0:100000:1000 \
  --uidmap=1000:1000:1 \
  --uidmap=1001:101001:64536 \
  -e OPENAI_API_KEY="${OPENAI_API_KEY}" \
  -v "$(pwd):/home/opencode/workdir:Z" \
  -v "$(pwd)/opencode.json:/home/opencode/.config/opencode/opencode.json:ro,Z" \
  opencode:latest
```

---

## B. GitHub Actions (CI/CD)

```yaml
# .github/workflows/build-and-publish.yml
name: Build and publish OpenCode image

on:
  push:
    branches: [main]
    tags: ["v*"]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-push:
    runs-on: ubuntu-24.04
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Install Podman
        run: |
          sudo apt-get update
          sudo apt-get install -y podman podman-docker qemu-user-static

      - name: Log in to GHCR
        uses: redhat-actions/podman-login@v1
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build image
        id: build-image
        uses: redhat-actions/buildah-build@v2
        with:
          image: ${{ env.IMAGE_NAME }}
          tags: |
            latest
            ${{ github.ref_name }}
          containerfiles: |
            ./Containerfile
          platforms: linux/amd64, linux/arm64

      - name: Push to GHCR
        uses: redhat-actions/push-to-registry@v2
        with:
          image: ${{ steps.build-image.outputs.image }}
          tags: ${{ steps.build-image.outputs.tags }}
          registry: ${{ env.REGISTRY }}

      - name: Run Trivy scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          format: sarif
          output: trivy-results.sarif
          severity: CRITICAL,HIGH

      - name: Upload Trivy results
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: trivy-results.sarif
```

---

## C. Użycie (dla użytkowników końcowych)

```bash
# Pobranie obrazu
podman pull ghcr.io/webbag/opencode:latest

# Uruchomienie interaktywne (TUI)
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -e OPENAI_API_KEY="sk-..." \
  -v "$(pwd):/home/opencode/workdir:Z" \
  ghcr.io/webbag/opencode:latest

# Uruchomienie headless (opencode run)
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -e ANTHROPIC_API_KEY="sk-ant-..." \
  -v "$(pwd):/home/opencode/workdir:Z" \
  ghcr.io/webbag/opencode:latest \
  run "Zrefaktoruj plik main.py"

# Uruchomienie z web search (wyszukiwanie w internecie)
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -e OPENAI_API_KEY="sk-..." \
  -e OPENCODE_SEARCH_API_KEY="..." \
  -v "$(pwd):/home/opencode/workdir:Z" \
  ghcr.io/webbag/opencode:latest \
  run "Znajdź najnowszą wersję Pythona i porównaj z Python 3.12"
```

---

> **Dokumentacja zgodna z SDLC i najlepszymi praktykami architektonicznymi dla konteneryzacji narzędzi CLI z sandboxingiem.**
