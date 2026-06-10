CTX := $(shell sh -c "printf %s vendor")

build:
	docker build $(CTX)
