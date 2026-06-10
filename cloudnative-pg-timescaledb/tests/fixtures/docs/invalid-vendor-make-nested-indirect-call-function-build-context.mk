f1 = f2
f2 = buildctx
buildctx = $(1)/

build:
	docker build $(call $($(f1)),vendor)
