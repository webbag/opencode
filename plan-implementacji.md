# Plan implementacji — Konteneryzacja OpenCode CLI

> **Status dokumentu:** Roboczy  
> **Data:** 2026-06-21  
> **Autor:** DevOps/Security Engineer  
> **Cel:** Rootless Podman container dla OpenCode CLI z sandboxingiem i CI/CD do ghcr.io  
> **GitHub:** [webbag/opencode](https://github.com/webbag/opencode)  
> **Rejestr obrazów:** `ghcr.io/webbag/opencode`  
> **Uwaga:** Scan Trivy nie został zaimplementowany w CI — świadoma rezygnacja (GitHub Code Scanning nieaktywne w repo). Treść dotycząca Trivy w dokumencie pozostawiona jako dokumentacja planu.

---

## Spis treści

0. [Faza 0: Przygotowanie repozytorium](#faza-0-przygotowanie-repozytorium)
1. [Wymagania](#1-wymagania)
2. [Architektura i Bezpieczeństwo](#2-architektura-i-bezpieczeństwo)
3. [Plan implementacji (SCOPE)](#3-plan-implementacji-scope)
   - [Faza 0: Przygotowanie repozytorium](#faza-0-przygotowanie-repozytorium)
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
| F-07 | W przyszłości: montowanie ~/.ssh, ~/.gitconfig z hosta | Średni |
| F-08 | W przyszłości: wysyłanie artefaktów do GitHub z kontenera | Średni |

### 1.2 Niefunkcjonalne

| ID | Wymaganie | Priorytet |
|---|---|---|
| NF-01 | Silnik: Podman w trybie rootless | Krytyczny |
| NF-01b | Obraz dostępny w dwóch wariantach: Ubuntu 24.04 i Red Hat UBI 9 | Wysoki |
| NF-02 | Mapowanie UID/GID bez `--userns=keep-id` | Krytyczny |
| NF-03 | Wszystkie capability zrzucone (`--cap-drop=ALL`) | Krytyczny |
| NF-04 | `no-new-privileges` włączone | Krytyczny |
| NF-05 | Obraz publikowany na `ghcr.io` przez GitHub Actions | Krytyczny |
| NF-06 | Kod źródłowy (Containerfile + skrypty) na GitHubie | Krytyczny |
| NF-07 | Wieloarchitekturowość (linux/amd64, linux/arm64) | Wysoki |
| NF-08 | Rozmiar obrazu ≤ 1.5 GB | Średni |

### 1.3 Ograniczenia (Constraints)

- Brak `--userns=keep-id` — mapowanie przez domyślny mechanizm user namespace Podmana
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
| **User namespace** | Podman rootless | Domyślne mapowanie użytkownika host → root/boundary w kontenerze; unikamy `keep-id`, które mapuje host UID 1:1 |
| **Seccomp** | Domyślny profil Podmana | Ogranicza dostępne syscalle |
| **Filesystem** | Volumes tylko do odczytu (gdzie możliwe) | Zmniejsza ryzyko modyfikacji binarek kontenera |
| **SELinux/AppArmor** | Profil `container` (domyślny) | Dodatkowa izolacja na Ubuntu |

### 2.3 Zarządzanie tożsamością

- Użytkownik w kontenerze: **opencode** (UID 1000) — odpowiada domyślnemu UID użytkownika na typowym hoście Ubuntu
- Mapowanie: UID 1000 hosta → UID 1000 w kontenerze (bez `--userns=keep-id`)
- Grupa: **opencode** (GID 1000)

Mapowanie realizowane przez domyślny mechanizm user namespace Podmana — bez `--userns=keep-id`.

### 2.4 Obsługa wolumenów

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

Projekt podzielono na **4 etapy (SCOPE)** oraz **Fazę 0 (przygotowawczą)**. Każdy SCOPE zawiera:

| Element | Opis |
|---|---|
| **S**cenariusz | Kontekst i przypadek użycia |
| **C**el | Konkretny, mierzalny rezultat |
| **O**graniczenia | Znane limity i założenia |
| **P**rocedura weryfikacji | Jak sprawdzamy poprawność |
| **E**skalacja | Co robimy przy niepowodzeniu |

---

### Faza 0: Przygotowanie repozytorium

#### Scenariusz

Przed rozpoczęciem budowy obrazu należy przygotować strukturę repozytorium, narzędzia developerskie (Makefile) oraz pliki konfiguracyjne usprawniające pracę i zapobiegające wyciekowi zbędnych plików do kontekstu builda.

#### Cel

- `.gitignore` — ignorowanie artifactów, kluczy API, `.env`, katalogów tymczasowych
- `.dockerignore` — wykluczenie zbędnych plików z kontekstu `podman build` (znacząco przyspiesza budowę)
- `.editorconfig` — spójność stylu kodowania (UTF-8, wcięcia, trailing whitespace)
- `Makefile` — zestaw komend: `make build`, `make run`, `make test`, `make shell`, `make secure-run`
- Struktura katalogów `.github/workflows/` i `tests/`

#### Procedura weryfikacji

```bash
ls -la .gitignore .dockerignore .editorconfig Makefile .github/

# Test Makefile
make help  # → wyświetla dostępne targety
```

#### Uwagi techniczne

- **.dockerignore jest krytyczny** — bez niego `podman build` przesyła całe repo do demona builda. Repo może zawierać duże pliki (node_modules, .git, test artifacts). Dla obrazu ~1.5 GB to różnica kilkudziesięciu sekund budowy.
- **Makefile** — celowo jako nakładka, a nie wymóg. Użytkownik może używać bezpośrednio `podman build`, ale Makefile skraca często używane komendy i dokumentuje je w jednym miejscu.

---

### SCOPE 1: Obraz bazowy i narzędzia

#### Scenariusz

Użytkownik buduje obraz kontenera zawierający wszystkie wymagane narzędzia: opencode CLI, git, Python 3, nmap, ping, iproute2, nano. Obraz dostępny w dwóch wariantach: Ubuntu 24.04 (LTS) oraz Red Hat UBI 9, z uruchomieniem opencode w trybie TUI lub headless.

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
- `sudo` **nie** jest instalowane w obrazie — zbędne (opencode user nie ma praw sudo), zwiększa powierzchnię ataku
- `dnsutils` w Ubuntu 24.04 → `bind9-dnsutils` (pakiet `dnsutils` jest przejściowy, ale działa — zachowujemy dla kompatybilności)

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

#### Uwagi techniczne (SCOPE 1)

1. **Brak `sudo`** — użytkownik `opencode` nie ma uprawnień sudo. Binary sudo to niepotrzebny wektor ataku — nie został zainstalowany.
2. **`python3-pip` i `python3-venv`** — dodają ~200 MB do obrazu. Jeśli opencode nie wymaga pip w runtime, rozważyć usunięcie. Póki co pozostawiamy, bo mogą być potrzebne do skryptów Python generowanych przez AI.
3. **ARG TARGETARCH** — oficjalny skrypt instalacyjny opencode sam wykrywa architekturę. Parametr nie jest potrzebny w Containerfile.
4. **Instalacja opencode jako root** — celowa: binary ląduje w `/usr/local/bin` (dostępny dla wszystkich użytkowników). Instalacja jako `opencode` user wymagałaby kopiowania do katalogu w `$PATH` użytkownika.
5. **`netcat-openbsd`** — nie jest wymagany, ale pozostawiamy jako narzędzie przydatne do debugowania sieci.

6. **Wariant UBI9** — obraz budowany jest również na Red Hat UBI 9. Różnice względem Ubuntu:

| Pakiet (Ubuntu) | Pakiet (UBI9) | Uwagi |
|---|---|---|
| `apt-get` | `microdnf` | Menedżer pakietów — inne komendy |
| `iputils-ping` | `iputils` | Różna nazwa pakietu |
| `iproute2` | `iproute` | Różna nazwa pakietu |
| `dnsutils` | `bind-utils` | Różna nazwa pakietu |
| `netcat-openbsd` | `nmap-ncat` | Różna nazwa pakietu |
| `userdel ubuntu` | (brak) | UBI nie ma domyślnego usera |
| `rm -rf /var/lib/apt/lists/*` | `microdnf clean all` | Inny mechanizm czyszczenia cache |

`Containerfile.ubi9` to osobny plik (nie ARG-i w Containerfile), co utrzymuje czystość i czytelność obu wariantów.

---

### SCOPE 2: Bezpieczeństwo i sandboxing

#### Scenariusz

Uruchomienie kontenera z maksymalnym ograniczeniem uprawnień. AI może wygenerować złośliwy kod — kontener musi uniemożliwiać ucieczkę (container breakout), eskalację przywilejów i modyfikację krytycznych zasobów systemowych.

#### Cel

- Kontener uruchomiony z `--cap-drop=ALL`
- `--security-opt=no-new-privileges=true`
- Użytkownik `opencode` (UID 1000) bez praw `sudo`
- Mapowanie UID/GID przez Podman rootless bez `--userns=keep-id`
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

#### Uwagi techniczne (SCOPE 2)

1. **User creation w build time** — użytkownik `opencode` (UID 1000) jest tworzony w Containerfile, jeszcze przed instalacją opencode (ale po instalacji pakietów systemowych). Dzięki temu opencode jest dostępne globalnie, a user ma gotowy `$HOME`.
2. **Brak `setcap` dla ping** — zgodnie z decyzją projektową: narzędzia diagnostyczne działają w ograniczonym zakresie. `nping --tcp` i `curl` są alternatywami.
3. **Kolejność warstw w Containerfile** — ważna dla warstwowania:
   ```
   apt packages → opencode CLI → user opencode → ENV → USER → ENTRYPOINT
   ```
   Jeśli opencode wymaga zapisu do `~/.config/opencode`, katalog musi być stworzony z odpowiednimi prawami przed `USER opencode`.
4. **ENTRYPOINT ["opencode"] vs CMD ["--help"]** — pozwala na `podman run image run "polecenie"` (headless) lub `podman run image` (TUI przez --help).

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

#### Uwagi techniczne (SCOPE 3)

1. **Websearch i webfetch** — to wbudowane funkcje opencode, nie wymagają dodatkowych pakietów w obrazie. `curl` i `wget` są dla diagnostyki i potencjalnych skryptów użytkownika.
2. **Zmienne środowiskowe** — klucze API są przekazywane przez `-e` w `podman run`, NIGDY nie buildowane w obraz. To krytyczne dla bezpieczeństwa (klucze nie wyciekają do rejestru).
3. **Brak ingress** — kontener nie nasłuchuje na żadnych portach. Potwierdzamy przez `ss -tlnp` które powinno zwrócić pusty wynik.

---

### SCOPE 4: CI/CD i publikacja

#### Scenariusz

Automatyczna budowa i publikacja obrazów do GitHub Container Registry (ghcr.io) przy każdym tagu lub pushu do gałęzi głównej. Obrazy budowane zarówno dla linux/amd64, jak i linux/arm64.

#### Cel

- GitHub Actions workflow budujący obrazy na push do `main` i na tagi semver (v*)
- Publikacja na `ghcr.io/webbag/opencode`
- Build wieloarchitekturowy (linux/amd64, linux/arm64) z QEMU + buildah
- Budowa dwóch wariantów przez matrix: ubuntu (Containerfile) i ubi9 (Containerfile.ubi9)
- Obrazy z tagami: `latest`/`v*` (Ubuntu) oraz `ubi9`/`v*-ubi9` (UBI9)
- Automatyczny README w ghcr.io z instrukcją użycia
- Scan bezpieczeństwa (Trivy) po zbudowaniu

#### Ograniczenia

- GHCR wymaga `write` permissions dla `GITHUB_TOKEN`
- Budget Actions: ~2000 min/miesiąc (free tier) — build może trwać 15-20 min
- Budowa na arm64 wymaga emulacji QEMU — może być wolniejsza
- Trivy scan wymaga osobnej konfiguracji

#### Procedura weryfikacji

```bash
# 1. Ręczna budowa Ububtu (symulacja CI)
podman build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/webbag/opencode:test \
  -f Containerfile .

# 2. Push testowy
podman push ghcr.io/webbag/opencode:test

# 3. Pociągnięcie i uruchomienie
podman pull ghcr.io/webbag/opencode:test
podman run --rm -it ghcr.io/webbag/opencode:test opencode --version

# 4. Budowa UBI9
podman build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/webbag/opencode:test-ubi9 \
  -f Containerfile.ubi9 .
podman run --rm -it ghcr.io/webbag/opencode:test-ubi9 opencode --version

# 5. Skany bezpieczeństwa
trivy image ghcr.io/webbag/opencode:test
```

#### Eskalacja

- Brak uprawnień do ghcr.io → skonfiguruj `GITHUB_TOKEN` z `packages: write` w repository secrets
- Build arm64 failuje w QEMU → sprawdź CPU type (`--cpu=host`), AVX dla opencode na arm64 nie jest wymagane (ARM64 ma NEON)
- Przekroczony limit czasu → zoptymalizuj warstwy, użyj cache z ghcr.io (`--cache-from`)

#### Uwagi techniczne (SCOPE 4)

1. **buildah-build action** — zamiast `podman build` w CI używamy `redhat-actions/buildah-build`, które lepiej wspiera buildx i multi-arch.
2. **QEMU dla arm64** — `qemu-user-static` musi być zainstalowane na runnerze. W Ubuntu 24.04 działa z `apt-get install qemu-user-static`.
3. **Trivy scan** — tylko CRITICAL i HIGH severity. Lower severity (MEDIUM, LOW) są zwykle fałszywie pozytywne dla obrazów opartych na Ubuntu.
4. **Tagowanie** — dwa warianty w matrix: ubuntu (`latest`, `v*`) i ubi9 (`ubi9`, `v*-ubi9`). Pull requesty też budują obraz (dla weryfikacji), ale nie pushują do rejestru.
5. **Matrix wariantów** — workflow buduje równolegle oba warianty przez `strategy.matrix`. Push do rejestru tylko z gałęzi `main` i tagów `v*` (warunek: `github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')`). Feature branche budują ale nie pushują, co pozwala na CI weryfikację przed PR.

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

### Darmowe modele opencode (bez kluczy API)

OpenCode CLI zawiera wbudowane darmowe modele, które nie wymagają żadnych kluczy API. Są one dostępne od razu po instalacji opencode.

| Model | Status |
|---|---|
| `opencode/big-pickle` | Domyślny, przetestowany |
| `opencode/deepseek-v4-flash-free` | Dostępny |
| `opencode/mimo-v2.5-free` | Dostępny |
| `opencode/nemotron-3-ultra-free` | Dostępny |
| `opencode/north-mini-code-free` | Dostępny |

### Konfiguracja domyślnego modelu

Aby opencode zawsze uruchamiał się z modelem `opencode/big-pickle`:

1. **Containerfile**: `CMD ["-m", "opencode/big-pickle"]` — domyślny model przy `podman run image`
2. **Makefile**: `MODEL ?= opencode/big-pickle` — używane w targetach `run` i `run-headless`
3. **docker-compose.yml**: `command: -m opencode/big-pickle` — dla `podman-compose up`

Zmiana modelu w runtime:
```bash
# Przez Makefile
make run MODEL=opencode/deepseek-v4-flash-free

# Ręcznie
podman run --rm -it opencode:latest -m opencode/deepseek-v4-flash-free
```

---

## A. Containerfile

```dockerfile
# Containerfile — OpenCode CLI w rootless Podman
# Bazuje na Ubuntu 24.04 LTS
# Budowa: podman build -t opencode:latest -f Containerfile .
#
# Kolejność warstw (ważna!):
#   1. apt packages → 2. opencode CLI (root) → 3. user opencode → 4. ENV → 5. USER → 6. ENTRYPOINT

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

LABEL org.opencontainers.image.title="OpenCode CLI Container"
LABEL org.opencontainers.image.description="Rootless Podman container for OpenCode AI coding agent"
LABEL org.opencontainers.image.source="https://github.com/webbag/opencode"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.version="1.0.0"

# ============================================================
# SCOPE 1: System packages and tools
# ============================================================
# Uwaga: sudo celowo pominięte — użytkownik opencode nie ma praw sudo,
# a binary sudo to niepotrzebny wektor ataku.
# netcat-openbsd: opcjonalne, ale przydatne do debugowania sieci.

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
# Oficjalny skrypt sam wykrywa architekturę — nie potrzebujemy ARG TARGETARCH.

ARG OPENCODE_VERSION=latest

RUN curl -fsSL https://opencode.ai/install | bash && \
    cp /root/.opencode/bin/opencode /usr/local/bin/opencode

RUN opencode --version

# ============================================================
# SCOPE 2: User setup (sandboxing)
# ============================================================
# Użytkownik opencode (UID/GID 1000) — odpowiada domyślnemu UID na hoście Ubuntu.
# Katalogi konfiguracyjne tworzone przed USER opencode, by miały odpowiednie prawa.

RUN userdel -r ubuntu 2>/dev/null; \
    groupdel ubuntu 2>/dev/null; \
    groupadd -g 1000 opencode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash opencode && \
    mkdir -p /home/opencode/workdir \
             /home/opencode/.config/opencode \
             /home/opencode/.local && \
    chown -R opencode:opencode /home/opencode

# CAP_NET_RAW dla ping — celowo zakomentowane (decyzja: narzędzia diagnostyczne
# działają w ograniczonym zakresie; alternatywa: nping --tcp).
# RUN setcap cap_net_raw+p /bin/ping

# ============================================================
# SCOPE 3: Configuration and environment
# ============================================================
# Klucze API NIGDY nie są buildowane w obraz — przekazywane przez -e w runtime.

ENV HOME=/home/opencode
ENV OPENCODE_HOME=/home/opencode/.config/opencode
ENV PATH="/home/opencode/.local/bin:${PATH}"

WORKDIR /home/opencode/workdir

USER opencode

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
  -e OPENAI_API_KEY="${OPENAI_API_KEY}" \
  -v "$(pwd):/home/opencode/workdir:Z" \
  -v "$(pwd)/opencode.json:/home/opencode/.config/opencode/opencode.json:ro,Z" \
  opencode:latest
```

---

## A.2 Containerfile.ubi9

```dockerfile
# Containerfile.ubi9 — OpenCode CLI w rootless Podman (Red Hat UBI 9)
# Bazuje na Red Hat Universal Base Image 9 (microdnf zamiast apt).
# Budowa: podman build -t opencode:ubi9 -f Containerfile.ubi9 .

FROM registry.access.redhat.com/ubi9/ubi:latest AS opencode-builder

ARG OPENCODE_VERSION=latest

RUN microdnf install -y curl ca-certificates && microdnf clean all

RUN curl -fsSL https://opencode.ai/install | bash && \
    cp /root/.opencode/bin/opencode /opencode && \
    /opencode --version

FROM registry.access.redhat.com/ubi9/ubi:latest

LABEL org.opencontainers.image.title="OpenCode CLI Container (UBI9)"
LABEL org.opencontainers.image.description="Rootless Podman container for OpenCode AI coding agent, UBI9 variant"
LABEL org.opencontainers.image.source="https://github.com/webbag/opencode"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.version="1.0.0"

RUN microdnf upgrade -y && \
    microdnf install -y \
        git \
        python3 \
        python3-pip \
        python3-venv \
        nano \
        curl \
        ca-certificates \
        nmap \
        iputils \
        iproute \
        bind-utils \
        nmap-ncat \
        wget \
        bash \
    && microdnf clean all

COPY --from=opencode-builder /opencode /usr/local/bin/opencode

RUN opencode --version

RUN groupadd -g 1000 opencode && \
    useradd -m -u 1000 -g 1000 -s /bin/bash opencode && \
    mkdir -p /home/opencode/workdir \
             /home/opencode/.config/opencode \
             /home/opencode/.local && \
    chown -R opencode:opencode /home/opencode

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
```

---

## B. GitHub Actions (CI/CD)

```yaml
# .github/workflows/build-and-publish.yml
# Budowa i publikacja obrazu OpenCode CLI na ghcr.io
# Buduje dwa warianty: Ubuntu 24.04 i Red Hat UBI 9

name: Build and publish OpenCode image

on:
  push:
    branches: ["**"]
    tags: ["v*"]
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-push:
    strategy:
      matrix:
        variant: [ubuntu, ubi9]
      fail-fast: false
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
            ${{ matrix.variant == 'ubi9' && 'ubi9' || 'latest' }}
            ${{ matrix.variant == 'ubi9' && format('{0}-ubi9', github.ref_name) || github.ref_name }}
          containerfiles: |
            ${{ matrix.variant == 'ubi9' && './Containerfile.ubi9' || './Containerfile' }}
          platforms: linux/amd64, linux/arm64

      - name: Push to GHCR
        if: github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')
        uses: redhat-actions/push-to-registry@v2
        with:
          image: ${{ steps.build-image.outputs.image }}
          tags: ${{ steps.build-image.outputs.tags }}
          registry: ${{ env.REGISTRY }}

      - name: Run Trivy scan
        if: (github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/v')) && matrix.variant == 'ubuntu'
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:latest
          format: sarif
          output: trivy-results.sarif
          severity: CRITICAL,HIGH
```

---

## D. Makefile

```makefile
# Makefile — OpenCode CLI Container
# Użycie: make build — zbuduj obraz
#         make run — uruchom interaktywnie
#         make shell — shell w kontenerze
#         make test — testy integracyjne

IMAGE_NAME ?= opencode
IMAGE_TAG ?= latest
CONTAINERFILE ?= Containerfile
PLATFORM ?= linux/amd64

# Detekcja architektury hosta
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),x86_64)
	PLATFORM = linux/amd64
else ifeq ($(UNAME_M),aarch64)
	PLATFORM = linux/arm64
endif

# ============================================================
# Budowa
# ============================================================

.PHONY: build
build:
	podman build \
		--platform $(PLATFORM) \
		--build-arg OPENCODE_VERSION=latest \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		-f $(CONTAINERFILE) .

.PHONY: build-no-cache
build-no-cache:
	podman build --no-cache \
		--platform $(PLATFORM) \
		--build-arg OPENCODE_VERSION=latest \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		-f $(CONTAINERFILE) .

.PHONY: build-ubi9
build-ubi9:
	$(MAKE) build CONTAINERFILE=Containerfile.ubi9 IMAGE_TAG=ubi9

.PHONY: build-ubi9-no-cache
build-ubi9-no-cache:
	$(MAKE) build-no-cache CONTAINERFILE=Containerfile.ubi9 IMAGE_TAG=ubi9

# ============================================================
# Uruchomienie
# ============================================================

.PHONY: run
run:
	podman run --rm -it \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-e OPENAI_API_KEY \
		-v "$(PWD):/home/opencode/workdir:Z" \
		$(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: run-headless
run-headless:
	podman run --rm -it \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-e OPENAI_API_KEY \
		-v "$(PWD):/home/opencode/workdir:Z" \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		run "$(CMD)"

.PHONY: shell
shell:
	podman run --rm -it \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-e OPENAI_API_KEY \
		-v "$(PWD):/home/opencode/workdir:Z" \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: shell-root
shell-root:
	podman run --rm -it \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-v "$(PWD):/home/opencode/workdir:Z" \
		--user root \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):$(IMAGE_TAG)

# ============================================================
# Testy
# ============================================================

.PHONY: test
test: build
	./tests/test_integration.sh $(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: test-ubi9
test-ubi9: build-ubi9
	./tests/test_integration.sh $(IMAGE_NAME):ubi9

.PHONY: test-quick
test-quick:
	podman run --rm $(IMAGE_NAME):$(IMAGE_TAG) opencode --version
	podman run --rm $(IMAGE_NAME):$(IMAGE_TAG) git --version
	podman run --rm $(IMAGE_NAME):$(IMAGE_TAG) whoami | grep opencode

# ============================================================
# Informacje
# ============================================================

.PHONY: size
size:
	podman images $(IMAGE_NAME):$(IMAGE_TAG) --format '{{.Size}}'

.PHONY: history
history:
	podman history $(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: help
help:
	@echo "Targety Makefile:"
	@echo "  build                   — zbuduj obraz (domyślnie: $(IMAGE_NAME):$(IMAGE_TAG))"
	@echo "  build-no-cache          — zbuduj bez cache"
	@echo "  build-ubi9             — zbuduj obraz na UBI 9 (tag: ubi9)"
	@echo "  build-ubi9-no-cache    — zbuduj UBI 9 bez cache"
	@echo "  run                    — uruchom TUI"
	@echo "  run-headless           — uruchom headless (make run-headless CMD='twoja komenda')"
	@echo "  shell                  — wejdź do shella jako opencode"
	@echo "  shell-root             — wejdź do shella jako root"
	@echo "  test                   — testy integracyjne"
	@echo "  test-ubi9             — testy integracyjne na UBI 9"
	@echo "  test-quick             — szybki test (wersja, git, whoami)"
	@echo "  size                   — sprawdź rozmiar obrazu"
	@echo "  history                — historia warstw obrazu"
```

---

---

## E. docker-compose.yml

```yaml
# docker-compose.yml — OpenCode CLI w rootless Podman
#
# Uruchomienie:
#   podman-compose up           # TUI (interaktywne)
#   podman-compose run --rm opencode run "komenda"  # headless
#
# Wymagany plik .env z kluczami API:
#   OPENAI_API_KEY=sk-...
#   ANTHROPIC_API_KEY=sk-ant-...
#   OPENCODE_SEARCH_API_KEY=...

version: "3.9"

services:
  opencode:
    image: ghcr.io/webbag/opencode:latest
    build:
      context: .
      dockerfile: Containerfile
      args:
        OPENCODE_VERSION: latest
    container_name: opencode
    stdin_open: true
    tty: true
    environment:
      - OPENAI_API_KEY=${OPENAI_API_KEY:-}
      - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
      - GOOGLE_API_KEY=${GOOGLE_API_KEY:-}
      - MISTRAL_API_KEY=${MISTRAL_API_KEY:-}
      - OPENCODE_SEARCH_API_KEY=${OPENCODE_SEARCH_API_KEY:-}
      - OPENCODE_TIMEOUT=${OPENCODE_TIMEOUT:-120000}
    volumes:
      - "${PWD}:/home/opencode/workdir:Z"
      - "${HOME}/.config/opencode/opencode.json:/home/opencode/.config/opencode/opencode.json:ro,Z"
    cap_drop:
      - ALL
    security_opt:
      - no-new-privileges:true
    user: "1000:1000"
    working_dir: /home/opencode/workdir
```

---

## F. Struktura repozytorium (po implementacji)

```
opencode-image/
├── .editorconfig
├── .gitignore
├── .dockerignore
├── Containerfile
├── Containerfile.ubi9
├── LICENSE
├── Makefile
├── README.md
├── AGENTS.md
├── cel.md
├── docker-compose.yml
├── plan-implementacji.md
├── .github/
│   └── workflows/
│       ├── build-and-publish.yml
│       ├── scheduled-rebuild.yml
│       └── dependabot.yml
└── tests/
    ├── test_integration.sh
    └── test_security.sh
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
