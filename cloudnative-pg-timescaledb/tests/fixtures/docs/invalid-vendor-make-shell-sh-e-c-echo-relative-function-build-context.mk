CTX := $(shell sh -e -c "echo ./vendor")

build:
	docker build $(CTX)
