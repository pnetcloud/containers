CTX := xendor

build:
	docker build $(patsubst x%,v%,$(CTX))
