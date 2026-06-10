CONTEXT := $(join vendor,/src)

build:
	docker build $(CONTEXT)
