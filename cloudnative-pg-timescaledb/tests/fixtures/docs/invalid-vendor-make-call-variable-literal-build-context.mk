buildctx = $(1)/$(2)

build:
	docker build $(call buildctx,vendor,.)
