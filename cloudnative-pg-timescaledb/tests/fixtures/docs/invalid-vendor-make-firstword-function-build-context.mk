CTX := vendor other
build:
	docker build $(firstword $(CTX))
