CTX := vendor
build:
	docker build $(addsuffix /,$(CTX))
