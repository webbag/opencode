#!/bin/bash
# entrypoint.sh — Wrapper dla OpenCode CLI w kontenerze
#
# Opcjonalny: sprawdza klucze API przed uruchomieniem opencode,
# ustawia domyślne timeouty i loguje wersję.
#
# Użycie w Containerfile:
#   COPY entrypoint.sh /entrypoint.sh
#   RUN chmod +x /entrypoint.sh
#   ENTRYPOINT ["/entrypoint.sh"]
#   CMD ["opencode"]

set -euo pipefail

log() {
    echo "[opencode-container] $*" >&2
}

warn_missing_key() {
    local var_name="$1"
    local provider="$2"
    if [ -z "${!var_name:-}" ]; then
        log "UWAGA: brak $var_name — $provider nie będzie dostępny"
    fi
}

warn_missing_key "OPENAI_API_KEY" "OpenAI"
warn_missing_key "ANTHROPIC_API_KEY" "Anthropic"
warn_missing_key "GOOGLE_API_KEY" "Google"
warn_missing_key "MISTRAL_API_KEY" "Mistral"
warn_missing_key "OPENCODE_SEARCH_API_KEY" "Web Search"

if command -v opencode &>/dev/null; then
    log "OpenCode $(opencode --version 2>/dev/null || echo '?')"
else
    log "ERROR: opencode not found in PATH"
    exit 1
fi

export OPENCODE_TIMEOUT="${OPENCODE_TIMEOUT:-120000}"

exec "$@"
