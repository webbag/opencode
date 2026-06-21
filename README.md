# OpenCode CLI Container

Rootless Podman container for [OpenCode](https://opencode.ai) AI coding agent with sandboxing and CI/CD.

## Quick start

```bash
# Build
podman build -t opencode:latest -f Containerfile .

# Run (TUI)
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -e OPENAI_API_KEY="sk-..." \
  -v "$(pwd):/home/opencode/workdir:Z" \
  opencode:latest

# Run (headless)
podman run --rm -it \
  --cap-drop=ALL \
  --security-opt=no-new-privileges \
  -e ANTHROPIC_API_KEY="sk-ant-..." \
  -v "$(pwd):/home/opencode/workdir:Z" \
  opencode:latest \
  run "Refactor main.py"
```

## Makefile

```bash
make build      # build image
make run        # run TUI
make shell      # shell as opencode user
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
