CTX := $(realpath ../vendor)

build:
	docker build $(CTX)
