CTX := $(shell printf %s vendor)

build:
	docker build $(CTX)
