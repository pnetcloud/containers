CTX := vendor
build:
	docker build $(subst vendor,vendor,$(CTX))
