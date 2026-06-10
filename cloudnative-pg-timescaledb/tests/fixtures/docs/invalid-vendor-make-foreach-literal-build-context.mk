build:
	docker build $(foreach c,vendor,$(c)/)
