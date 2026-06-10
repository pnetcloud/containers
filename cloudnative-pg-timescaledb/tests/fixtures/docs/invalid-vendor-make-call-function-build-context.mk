define buildctx
$(1)
endef

CTX := vendor
build:
	docker build $(call buildctx,$(CTX))
