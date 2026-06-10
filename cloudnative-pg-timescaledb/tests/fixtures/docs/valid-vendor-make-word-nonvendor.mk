CTX := . vendor
build:
	docker build $(word 1,$(CTX))
