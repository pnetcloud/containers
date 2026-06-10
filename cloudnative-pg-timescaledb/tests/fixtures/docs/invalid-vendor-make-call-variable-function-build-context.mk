buildctx = $(1)/$(2)
CTX := vendor

build:
	docker build $(call buildctx,$(CTX),.)
