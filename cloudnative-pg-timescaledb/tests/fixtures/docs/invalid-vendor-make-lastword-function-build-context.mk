CTX := other vendor
build:
	docker build $(lastword ${CTX})
