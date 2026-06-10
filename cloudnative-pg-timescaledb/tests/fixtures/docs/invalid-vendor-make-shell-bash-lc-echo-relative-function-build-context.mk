CTX := $(shell bash -lc "echo ./vendor")

build:
	docker build $(CTX)
