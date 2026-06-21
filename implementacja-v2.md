# opencode-image — Plan implementacji v2 (SDLC)

## 1. Wymagania (Requirements)

**Cel:** Obraz kontenera do izolowanego uruchamiania OpenCode CLI na Ubuntu 24.04 z Podmanem.

**Kluczowe wymagania:**

- OpenCode działa z zewnętrznymi modelami językowymi (**Anthropic, OpenAI, Google AI**) — wymagany **dostęp do internetu** (egress)
- Izolacja procesów i systemu plików
- Reproducowalny build (wersjonowanie pakietów)
- Git + SSH + Python dostępne w kontenerze
- Domyślnie **brak ograniczeń sieci** (user może dodać `--network=none` jeśli nie potrzebuje LLM)

## 2. Architektura (Design)

```
[Host Ubuntu 24.04]
    |
    | Podman (rootless) --userns=keep-id
    v
[debian:bookworm-slim — opencode + narzędzia]
    |
    | -v $PWD:/workspace
    | -v ~/.gitconfig:/home/opencode/.gitconfig:ro
    | -v ~/.ssh:/home/opencode/.ssh:ro
    | -e ANTHROPIC_API_KEY=...   (API keys do LLM)
    v
[ /workspace (projekt) ←→ Internet (LLM API) ]
```

**Model bezpieczeństwa:**
- no-new-privileges
- drop ALL capabilities
- --pids-limit=512, --memory=8g, --cpus=4
- **Sieć: mostkowana (domyślnie) — wymagana dla LLM**

## 3. Implementacja (Development)

### 3.1 Containerfile (multi-stage)

- **Stage 1 (builder):** `node:bookworm-slim` → `npm install -g opencode-ai@${VERSION}`
- **Stage 2 (final):** `debian:bookworm-slim` → Python, git, curl, ca-certificates + kopiuje binary opencode
- User `opencode`, WORKDIR `/workspace`, CMD `["opencode"]`

### 3.2 Build

```bash
podman build -t opencode:bookworm .
```

### 3.3 Uruchomienie (zalecane)

```bash
podman run -it --rm \
  --userns=keep-id \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  --pids-limit=512 \
  --memory=8g \
  --cpus=4 \
  -e ANTHROPIC_API_KEY \
  -e OPENAI_API_KEY \
  -e GOOGLE_API_KEY \
  -v $PWD:/workspace \
  -v ~/.gitconfig:/home/opencode/.gitconfig:ro \
  -v ~/.ssh:/home/opencode/.ssh:ro \
  opencode:bookworm
```

## 4. Testowanie (Testing)

- **Funkcjonalne:** `opencode --version`, `git version`, `python3 --version`
- **Bezpieczeństwo:** capsh, próba mount, próba ptrace, PID 1
- **Sieciowe:** `curl https://api.anthropic.com` (krótki timeout)
- **Integracyjne:** uruchomienie opencode z promptem i sprawdzenie odpowiedzi LLM

## 5. Wdrożenie (Deployment)

- Obraz tagowany: `opencode:bookworm-v${OPENCODE_VERSION}` (immutable)
- Skanowanie: Trivy / Grype przed push
- CI: prosty pipeline build + scan

## 6. Utrzymanie (Maintenance)

- Aktualizacja wersji opencode-ai w argumencie build
- Monitorowanie luk w debian:bookworm-slim
- Opcjonalne rozszerzenia: Seccomp profile, gVisor, Podman secrets

## Kluczowe zmiany względem v1

| Aspekt | v1 | v2 |
|--------|----|----|
| Szczegółowość | Bardzo szczegółowy | Ogólny (SDLC) |
| Sieć | Opcjonalna (`--network=none`) | **Wymagana** (LLM API) |
| API keys | Wzmianka w hardening | Eksplicytne `-e` w run |
| Struktura | Funkcjonalna | SDLC (6 faz) |
