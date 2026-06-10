CTX := .
build:
	docker build $(addsuffix /vendor,$(CTX))
