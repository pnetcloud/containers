CTX := $(shell printf vendor)

build:
	docker build $(CTX)
