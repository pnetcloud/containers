buildctx = $(1)/
CTX := vendor

build:
	docker build ${call buildctx,${CTX}}
