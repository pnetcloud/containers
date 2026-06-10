CTX != sh -c "echo vendor"

build:
	docker build $(CTX)
