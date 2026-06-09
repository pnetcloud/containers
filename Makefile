SHELL := /usr/bin/env bash

PROJECT_DIR := cloudnative-pg-timescaledb
SCRIPT_DIR := $(PROJECT_DIR)/scripts

.PHONY: help update generate validate matrix bake-print catalog build smoke

help:
	@$(SCRIPT_DIR)/make-help.sh

update:
	@$(SCRIPT_DIR)/update.sh $(UPDATE_ARGS)

generate:
	@$(SCRIPT_DIR)/generate.sh $(GENERATE_ARGS)

validate:
	@$(SCRIPT_DIR)/validate.sh $(VALIDATE_ARGS)

matrix:
	@$(SCRIPT_DIR)/matrix.sh $(MATRIX_ARGS)

bake-print:
	@$(SCRIPT_DIR)/bake-print.sh $(BAKE_PRINT_ARGS)

catalog:
	@$(SCRIPT_DIR)/catalog.sh $(CATALOG_ARGS)

build:
	@$(SCRIPT_DIR)/build.sh "$(PG)" "$(DEBIAN)" $(BUILD_ARGS)

smoke:
	@CHECKS="$(CHECKS)" $(SCRIPT_DIR)/smoke.sh "$(PG)" "$(DEBIAN)" $(SMOKE_ARGS)
