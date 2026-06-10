CTX := $(abspath ./vendor)

build:
	docker build $(CTX)
