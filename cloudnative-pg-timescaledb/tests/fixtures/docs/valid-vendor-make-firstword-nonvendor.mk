CTX := . vendor
build:
	docker build $(firstword $(CTX))
