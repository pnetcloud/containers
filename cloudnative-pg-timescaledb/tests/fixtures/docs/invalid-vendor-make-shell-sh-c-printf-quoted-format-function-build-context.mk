CTX := $(shell sh -c "printf '%s\n' vendor")

build:
	docker build $(CTX)
