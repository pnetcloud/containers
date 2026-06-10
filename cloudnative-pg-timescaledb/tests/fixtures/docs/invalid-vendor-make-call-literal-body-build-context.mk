define buildctx
vendor
endef

build:
	docker build $(call buildctx,.)
