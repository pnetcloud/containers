CTX := vendor
build:
	docker build $(addsuffix -cache,$(CTX))
