buildctx = $(1)-cache
CTX := vendor

build:
	docker build $(call buildctx,$(CTX))
