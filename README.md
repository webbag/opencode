# OpenCode CLI Container

Rootless Podman container for [OpenCode](https://opencode.ai) AI coding agent with sandboxing and CI/CD.

## Quick start

```bash
# Build
podman build -t opencode:latest -f Containerfile .

# Run TUI with free model (big-pickle)
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -v "$(pwd):/home/opencode/workdir:Z" \
  opencode:latest

# Run headless with free model
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -v "$(pwd):/home/opencode/workdir:Z" \
  opencode:latest \
  run -m opencode/big-pickle "Your command here"
```

## Free models (no API key required)

| Model | Description |
|---|---|
| `opencode/big-pickle` | Default model |
| `opencode/deepseek-v4-flash-free` | DeepSeek v4 Flash |
| `opencode/mimo-v2.5-free` | Mimo v2.5 |
| `opencode/nemotron-3-ultra-free` | Nemotron 3 Ultra |
| `opencode/north-mini-code-free` | North Mini Code |

```bash
# List available models
make model
# or
podman run --rm opencode:latest models
```

## Makefile

```bash
make build      # build image
make run        # run TUI (model: opencode/big-pickle)
make run-headless CMD='refactor main.py'  # run headless
make shell      # shell as opencode user
make model      # list available models
make test       # integration tests
```

## Security

- `--cap-drop=ALL` — no Linux capabilities
- `--security-opt=no-new-privileges` — prevents privilege escalation
- Rootless Podman — user namespace isolation
- No `sudo` in image — reduced attack surface
- API keys passed via `-e` at runtime, never built into image

## Image

Published at `ghcr.io/webbag/opencode` (linux/amd64, linux/arm64).
