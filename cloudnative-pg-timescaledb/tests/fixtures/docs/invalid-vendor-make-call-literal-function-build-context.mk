define buildctx
$(1)
endef

build:
	docker build $(call buildctx,vendor)
