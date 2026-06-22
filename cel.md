Wciel się w rolę eksperta DevOps i specjalisty ds. bezpieczeństwa. Przygotuj szczegółowy plan implementacji (w formacie Markdown) dla konteneryzacji narzędzia OpenCode CLI na rootless Podman.

Środowisko: Ubuntu 24.04, Podman rootless bez `--userns=keep-id` — mapowanie UID przez domyślny mechanizm user namespace. W obrazie: opencode CLI, git, Python 3, nano, nmap, iputils-ping, iproute2, curl, wget, dnsutils. Bez sudo, bez setcap dla ping.

Bezpieczeństwo: `--cap-drop=ALL`, `--security-opt=no-new-privileges`, użytkownik `opencode` (UID 1000). Żadnych zbędnych capability — narzędzia diagnostyczne działają w ograniczonym zakresie (nmap -sT, nping --tcp). Montowanie ~/.ssh i ~/.gitconfig — w przyszłości.

Sieć: pełny egress do API (OpenAI, Anthropic, Google, Mistral, OpenCode Zen) oraz do dowolnych stron (websearch/webfetch opencode). Brak ingress, brak nasłuchujących portów.

CI/CD: GitHub Actions → ghcr.io, multi-arch (amd64 + arm64), multi-stage build, HEALTHCHECK. Scan Trivy tylko w dokumentacji — nie został zaimplementowany (Code Scanning nieaktywne w repo).

Licencja obrazu: Apache-2.0.

Plan podziel na 4 etapy SCOPE (Scenariusz, Cel, Ograniczenia, Procedura weryfikacji, Eskalacja) + Fazę 0 przygotowawczą. Dołącz appendiksy: Containerfile, GitHub Actions, Makefile, docker-compose.yml, struktura repozytorium, użycie. Każdy SCOPE ma mieć uwagi techniczne z uzasadnieniem decyzji.
