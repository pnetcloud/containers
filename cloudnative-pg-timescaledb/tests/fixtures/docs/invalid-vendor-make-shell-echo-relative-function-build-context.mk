CTX := $(shell echo ./vendor)

build:
	docker build $(CTX)
