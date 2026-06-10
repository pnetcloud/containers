define buildctx
vendor/$(1)
endef

build:
	docker build $(call buildctx,.)
