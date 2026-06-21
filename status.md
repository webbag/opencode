# Status implementacji — OpenCode CLI Container

**Data:** 2026-06-21  
**Plan:** `plan-implementacji.md` (v3)

---

## Zrealizowane

### Faza 0: Przygotowanie repozytorium ✅

| Plik | Status |
|---|---|
| `.gitignore` | ✅ |
| `.dockerignore` | ✅ |
| `.editorconfig` | ✅ |
| `Makefile` | ✅ |
| `entrypoint.sh` | ✅ |
| `docker-compose.yml` | ✅ |
| `README.md` | ✅ |

### SCOPE 1: Obraz bazowy i narzędzia ✅

- Ubuntu 24.04 jako base image
- Zainstalowane: git, python3, python3-pip, python3-venv, nano, curl, ca-certificates
- Narzędzia: nmap, iputils-ping, iproute2, dnsutils, netcat-openbsd, wget
- OpenCode CLI 1.17.9 zainstalowane przez oficjalny skrypt
- `sudo` usunięte — zbędne
- Rozmiar obrazu: **~610 MB** (limit 1.5 GB) — redukcja ~30 MB dzięki multi-stage
- **Weryfikacja:** `opencode --version`, `git --version`, `python3`, `wget`
- **Poprawki:** `cp` zamiast `ln -s` (dostęp do /root zablokowany dla usera opencode)
- **Multi-stage build:** builder dla opencode, final stage z apt + kopia binary

### SCOPE 2: Bezpieczeństwo i sandboxing ✅

- Użytkownik `opencode` (UID/GID 1000)
- `--cap-drop=ALL` działa (CapEff=0000000000000000)
- `--security-opt=no-new-privileges` działa (NoNewPrivs=1)
- Brak `sudo` w obrazie
- Brak nasłuchujących portów (ss -tlnp pusty)
- **Poprawki:** usunięto `ubuntu` user/group przed stworzeniem `opencode`

### SCOPE 3: Sieć i integracja z API ✅ (częściowo)

- Egress do `api.opencode.ai` — działa
- Egress do `example.com` — działa
- `curl`, `wget` — działają
- `nmap -sT` — działa w trybie TCP
- Brak ingress (ss -tlnp pusty)
- **Nieprzetestowane:** websearch/webfetch opencode (wymaga kluczy API), egress do OpenAI/Anthropic/Mistral/Google

### Darmowe modele opencode ✅

W kontenerze dostępne są wbudowane darmowe modele opencode (bez kluczy API):

| Model | Testowany |
|---|---|
| `opencode/big-pickle` | ✅ — przetestowany, działa headless |
| `opencode/deepseek-v4-flash-free` | ❌ |
| `opencode/mimo-v2.5-free` | ❌ |
| `opencode/nemotron-3-ultra-free` | ❌ |
| `opencode/north-mini-code-free` | ❌ |

Domyślny model: **`opencode/big-pickle`** — ustawiony w Containerfile (CMD), Makefile i docker-compose.

### Testy integracyjne

Plik: `tests/test_integration.sh` — **13/13 testów OK**

| # | Test | Status |
|---|---|---|
| 1 | opencode --version | ✅ |
| 2 | git --version | ✅ |
| 3 | python3 | ✅ |
| 4 | whoami → opencode | ✅ |
| 5 | Zapis do wolumenu | ✅ |
| 6 | --cap-drop=ALL (CapEff=0) | ✅ |
| 7 | Egress do api.opencode.ai | ✅ |
| 8 | Egress do example.com | ✅ |
| 9 | nmap -sT openai.com:443 | ✅ |
| 10 | curl page fetch | ✅ |
| 11 | wget --version | ✅ |
| 12 | no-new-privileges | ✅ |
| 13 | Brak nasłuchujących portów | ✅ |

---

## Do zrobienia

### SCOPE 4: CI/CD i publikacja ✅

| Zadanie | Opis | Status |
|---|---|---|
| Push na GitHub | Stworzenie repo `webbag/opencode` i push kodu | ✅ git remote origin skonfigurowane |
| Konfiguracja GHCR | `GITHUB_TOKEN` z `packages: write` | ✅ w `.github/workflows/build-and-publish.yml` |
| Build wieloarchitektoniczny | amd64 + arm64 przez QEMU | ✅ buildah-build z platforms |
| Publikacja na ghcr.io | `ghcr.io/webbag/opencode:latest` | ✅ push-to-registry po buildzie |
| Trivy scan | W CI po buildzie | ✅ aquasecurity/trivy-action + SARIF upload |
| Dependabot | Monitorowanie CVEs | ✅ `.github/dependabot.yml` (docker + actions) |

### Testy wymagające kluczy API 🟡

- `podman run -e OPENAI_API_KEY=sk-... opencode:latest` — tryb TUI
- `podman run -e OPENAI_API_KEY=sk-... opencode:latest run "polecenie"` — headless
- `podman run -e OPENCODE_SEARCH_API_KEY=... opencode:latest` — websearch
- Egress do OpenAI, Anthropic, Google, Mistral

### Testy bezpieczeństwa ✅

| Test | Status |
|---|---|
| Próba mountowania wewnątrz kontenera | ✅ `tests/test_security.sh` |
| Próba dostępu do /dev/sda* | ✅ |
| Próba lsmod | ✅ |
| Próba sudo (brak binary) | ✅ |
| Próba chown (brak CAP_CHOWN) | ✅ |
| Próba dostępu do /proc/1 | ✅ |
| Próba mknod | ✅ |
| Próba kexec | ✅ |
| Trivy scan | ✅ w CI |

Plik: `tests/test_security.sh` — 8 testów bezpieczeństwa.

### Usprawnienia (opcjonalne)

| Zadanie | Status |
|---|---|
| Multi-stage build dla zmniejszenia obrazu | ✅ zredukowane o ~30 MB |
| Testowanie z `podman unshare` zamiast `chmod 777` | ✅ w `test_integration.sh` |
| Healthcheck w obrazie | ✅ `HEALTHCHECK` w Containerfile |
| Automatyczny rebuild przy nowym release opencode (GitHub Releases trigger) | ❌ |
| Cotygodniowy scheduled rebuild | ✅ `.github/workflows/scheduled-rebuild.yml` |
| Dependabot dla docker i GitHub Actions | ✅ `.github/dependabot.yml` |
| Security test suite | ✅ `tests/test_security.sh` |
| Read-only rootfs (eksperymentalne) | ✅ `make run-ro` z `--tmpfs /tmp` |
