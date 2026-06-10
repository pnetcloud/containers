LEFT := vendor
RIGHT := /src
CONTEXT := $(join $(LEFT),$(RIGHT))

build:
	docker build $(CONTEXT)
