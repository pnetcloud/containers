CTX := $(shell sh -c "echo ./vendor")

build:
	docker build $(CTX)
