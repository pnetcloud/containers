CTX := $(shell printf '%s\n' vendor)

build:
	docker build $(CTX)
