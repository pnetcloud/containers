CTX := .
build:
	docker build $(foreach c,$(CTX),vendor)
