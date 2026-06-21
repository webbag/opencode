IMAGE_NAME ?= opencode
IMAGE_TAG ?= latest
PLATFORM ?= linux/amd64

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
		-f Containerfile .

.PHONY: build-no-cache
build-no-cache:
	podman build --no-cache \
		--platform $(PLATFORM) \
		--build-arg OPENCODE_VERSION=latest \
		-t $(IMAGE_NAME):$(IMAGE_TAG) \
		-f Containerfile .

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
	@echo "  build           — zbuduj obraz (domyślnie: $(IMAGE_NAME):$(IMAGE_TAG))"
	@echo "  build-no-cache  — zbuduj bez cache"
	@echo "  run             — uruchom TUI"
	@echo "  run-headless    — uruchom headless (make run-headless CMD='twoja komenda')"
	@echo "  shell           — wejdź do shella jako opencode"
	@echo "  shell-root      — wejdź do shella jako root"
	@echo "  test            — testy integracyjne"
	@echo "  test-quick      — szybki test (wersja, git, whoami)"
	@echo "  size            — sprawdź rozmiar obrazu"
	@echo "  history         — historia warstw obrazu"
