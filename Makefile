IMAGE_NAME ?= opencode
IMAGE_TAG ?= latest
CONTAINERFILE ?= Containerfile
PLATFORM ?= linux/amd64
MODEL ?= opencode/big-pickle

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
		$(IMAGE_NAME):$(IMAGE_TAG) \
		-m "$(MODEL)"

.PHONY: run-headless
run-headless:
	podman run --rm -it \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-e OPENAI_API_KEY \
		-v "$(PWD):/home/opencode/workdir:Z" \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		run -m "$(MODEL)" "$(CMD)"

.PHONY: shell
shell:
	podman run --rm -it \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-e OPENAI_API_KEY \
		-v "$(PWD):/home/opencode/workdir:Z" \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		-l

.PHONY: shell-root
shell-root:
	podman run --rm -it \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		-v "$(PWD):/home/opencode/workdir:Z" \
		--user root \
		--entrypoint /bin/bash \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		-l

.PHONY: run-ro
run-ro:
	podman run --rm -it \
		--cap-drop=ALL \
		--security-opt=no-new-privileges \
		--read-only-rootfs \
		--tmpfs /tmp \
		--tmpfs /home/opencode/.local \
		-e OPENAI_API_KEY \
		-v "$(PWD):/home/opencode/workdir:Z" \
		$(IMAGE_NAME):$(IMAGE_TAG) \
		-m "$(MODEL)"

# ============================================================
# Testy
# ============================================================

.PHONY: test
test: build
	./tests/test_integration.sh $(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: test-security
test-security: build
	./tests/test_security.sh $(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: test-quick
test-quick:
	podman run --rm --entrypoint /bin/bash $(IMAGE_NAME):$(IMAGE_TAG) -c "opencode --version && git --version && whoami"

.PHONY: test-ubi9
test-ubi9: build-ubi9
	./tests/test_integration.sh $(IMAGE_NAME):ubi9

.PHONY: test-security-ubi9
test-security-ubi9: build-ubi9
	./tests/test_security.sh $(IMAGE_NAME):ubi9

# ============================================================
# Informacje
# ============================================================

.PHONY: model
model:
	podman run --rm $(IMAGE_NAME):$(IMAGE_TAG) models

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
	@echo "  build-ubi9-no-cache    — zbuduj obraz na UBI 9 bez cache"
	@echo "  run                    — uruchom TUI (model: $(MODEL))"
	@echo "  run-headless           — uruchom headless (make run-headless CMD='polecenie')"
	@echo "  shell                  — wejdź do shella jako opencode"
	@echo "  shell-root             — wejdź do shella jako root"
	@echo "  run-ro                 — uruchom z --read-only-rootfs (eksperymentalne)"
	@echo "  test                   — testy integracyjne"
	@echo "  test-security          — testy bezpieczeństwa"
	@echo "  test-ubi9             — testy integracyjne na UBI 9"
	@echo "  test-security-ubi9    — testy bezpieczeństwa na UBI 9"
	@echo "  test-quick             — szybki test (wersja, git, whoami)"
	@echo "  model                  — sprawdź dostępne modele w obrazie"
	@echo "  size                   — sprawdź rozmiar obrazu"
	@echo "  history                — historia warstw obrazu"
