CTX := vendor
build:
	docker build $(addprefix ./,$(CTX))
