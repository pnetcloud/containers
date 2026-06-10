CTX := $(shell pwd)/./vendor

build:
	docker build $(CTX)
