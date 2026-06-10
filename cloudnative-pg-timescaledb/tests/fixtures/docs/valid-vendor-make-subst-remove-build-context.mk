CTX := vendor
build:
	docker build $(subst vendor,.,$(CTX))
