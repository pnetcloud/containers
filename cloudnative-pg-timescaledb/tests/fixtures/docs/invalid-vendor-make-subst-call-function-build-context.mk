func = buildctx
buildctx = $(1)/

build:
	docker build $(call $(subst x,x,$(func)),vendor)
