LEFT := $(subst x,vendor,x)
RIGHT := /src
CONTEXT := $(join $(LEFT),$(RIGHT))

build:
	docker build $(CONTEXT)
