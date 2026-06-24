# AGENTS.md — opencode-image

Obraz kontenera OpenCode CLI dla rootless Podman. **To nie jest projekt z kodem źródłowym** — całość to Containerfile + testy + CI/CD.

## Główne pliki

| Plik | Rola |
|---|---|
| `Containerfile` | Multi-stage build: Ubuntu 24.04 (apt) |
| `Containerfile.ubi9` | Multi-stage build: Red Hat UBI 9 (microdnf) |
| `Makefile` | Nakładka na `podman` — używaj jej zamiast raw commands |
| `docker-compose.yml` | Dla `podman-compose up` |
| `tests/test_integration.sh` | 13 testów (wersja, git, python, capabilities, sieć, nmap) |
| `tests/test_security.sh` | 8 testów bezpieczeństwa (mount, chown, mknod, sudo, /proc) |

## Komendy

```bash
make build                    # podman build --platform auto (Ubuntu)
make build-ubi9              # podman build na Red Hat UBI 9
make run                      # TUI z --cap-drop=ALL (Ubuntu)
make run-headless CMD='...'   # headless mode
make test                     # build + test_integration.sh (Ubuntu)
make test-ubi9               # build + test_integration.sh na UBI 9
make test-security            # build + test_security.sh (Ubuntu)
make test-security-ubi9      # build + test_security.sh na UBI 9
make test-quick               # szybki test bez builda (wersja, git, whoami)
make model                    # lista modeli w obrazie
make size                     # rozmiar obrazu
```

## Architektura

- **Silnik kontenerów**: Podman (NIE Docker). CI używa `buildah-build` z `redhat-actions`.
- **Obraz**: `ghcr.io/webbag/opencode` (linux/amd64 + linux/arm64) — dwa warianty:
  - `latest` / `v*` — Ubuntu 24.04
  - `ubi9` / `v*-ubi9` — Red Hat UBI 9
- **Entrypoint**: `opencode`, default `CMD ["-m", "opencode/big-pickle"]`
- **Różnice Ubuntu vs UBI9**: `apt-get` → `microdnf`, `iputils-ping` → `iputils`, `iproute2` → `iproute`, `dnsutils` → `bind-utils`, `netcat-openbsd` → `nmap-ncat`
- **Użytkownik**: `opencode` (UID/GID 1000) — bez sudo, bez setcap
- **Kolejność warstw w Containerfile** (ważna): apt → opencode CLI → user opencode → ENV → USER → HEALTHCHECK → ENTRYPOINT
- **Klucze API**: przekazywane przez `-e` w runtime, NIGDY nie buildowane w obraz

## Ograniczenia bezpieczeństwa (wszystkie runtime)

- `--cap-drop=ALL` — brak capability
- `--security-opt=no-new-privileges`
- Rootless Podman bez `--userns=keep-id`
- ping nie działa (brak CAP_NET_RAW); alternatywa: `nping --tcp -p 80 <host>`
- nmap tylko w trybie TCP (`-sT`)

## CI/CD

| Workflow | Trigger | Akcja |
|---|---|---|
| `build-and-publish.yml` | push main, tag v*, PR | Build + push do ghcr.io (PR: tylko build) |
| `scheduled-rebuild.yml` | poniedziałek 6:00 UTC, workflow_dispatch | Rebuild bez cache + push |
| `dependabot.yml` | weekly | Aktualizacje Docker + GitHub Actions |

## Darmowe modele (bez kluczy API)

`opencode/big-pickle` (domyślny), `opencode/deepseek-v4-flash-free`, `opencode/mimo-v2.5-free`, `opencode/nemotron-3-ultra-free`, `opencode/north-mini-code-free`.

## Testy

- `make test` — wymaga zbudowanego obrazu (robi `make build` automatycznie). Testy 7 i 9 dopuszczają FAIL (zależne od sieci/zewnętrznych serwisów).
- `make test-security` — sprawdza izolację kontenera. Test S4 (brak sudo) celowo odwrócony.
- Przy dodawaniu testu, dodaj go do obu suite'ów jeśli dotyczy bezpieczeństwa.
