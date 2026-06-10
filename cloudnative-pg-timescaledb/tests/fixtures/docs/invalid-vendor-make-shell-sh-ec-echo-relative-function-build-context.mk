CTX := $(shell sh -ec "echo ./vendor")

build:
	docker build $(CTX)
