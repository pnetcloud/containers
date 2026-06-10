CTX := vendor
build:
	docker build $(foreach c,$(CTX),.)
