func = buildctx
buildctx = $(1)/

build:
	docker build $(call $(func),vendor)
