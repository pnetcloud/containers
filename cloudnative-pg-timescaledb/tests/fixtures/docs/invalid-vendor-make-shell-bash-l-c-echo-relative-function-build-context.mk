CTX := $(shell bash -l -c "echo ./vendor")

build:
	docker build $(CTX)
