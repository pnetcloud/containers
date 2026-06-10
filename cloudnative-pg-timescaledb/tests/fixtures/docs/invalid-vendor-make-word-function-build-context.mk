CTX := other vendor
build:
	docker build $(word 2,$(CTX))
