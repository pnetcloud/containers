build:
	docker build $(foreach c,$(sort vendor),$(c)/)
