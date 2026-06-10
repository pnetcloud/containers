CTX := x
build:
	docker build $(subst x,vendor,$(CTX))
