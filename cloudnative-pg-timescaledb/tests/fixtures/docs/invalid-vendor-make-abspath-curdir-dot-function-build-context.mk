CTX := $(abspath $(CURDIR)/./vendor)

build:
	docker build $(CTX)
