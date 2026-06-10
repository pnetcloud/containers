SHELL := /usr/bin/env bash

override PROJECT_DIR := cloudnative-pg-timescaledb
override SCRIPT_DIR := $(PROJECT_DIR)/scripts
export DRY_RUN DATE STAGING_NAMESPACE
define newline


endef
reject_make_meta = $(if $(findstring $(newline),$(value $(1))),$(error Unsafe make variable $(1) contains newline; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring $$,$(value $(1))),$(error Unsafe make variable $(1) contains '$'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring `,$(value $(1))),$(error Unsafe make variable $(1) contains '`'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring ;,$(value $(1))),$(error Unsafe make variable $(1) contains ';'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring &,$(value $(1))),$(error Unsafe make variable $(1) contains '&'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring |,$(value $(1))),$(error Unsafe make variable $(1) contains '|'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring <,$(value $(1))),$(error Unsafe make variable $(1) contains '<'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring >,$(value $(1))),$(error Unsafe make variable $(1) contains '>'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring ",$(value $(1))),$(error Unsafe make variable $(1) contains double quote; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring ',$(value $(1))),$(error Unsafe make variable $(1) contains single quote; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring \,$(value $(1))),$(error Unsafe make variable $(1) contains backslash; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))
reject_make_scalar_meta = $(if $(findstring $(newline),$(value $(1))),$(error Unsafe make variable $(1) contains newline; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring $$,$(value $(1))),$(error Unsafe make variable $(1) contains '$'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring `,$(value $(1))),$(error Unsafe make variable $(1) contains '`'; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring ",$(value $(1))),$(error Unsafe make variable $(1) contains double quote; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))$(if $(findstring \,$(value $(1))),$(error Unsafe make variable $(1) contains backslash; call cloudnative-pg-timescaledb/scripts/* directly for complex shell syntax))

.PHONY: help update generate validate matrix bake-print catalog build smoke release-rehearsal

help:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(SCRIPT_DIR)/make-help.sh

update:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_meta,UPDATE_ARGS)args='$(value UPDATE_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable UPDATE_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; exec $(SCRIPT_DIR)/update.sh "$$@"

generate:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_meta,GENERATE_ARGS)args='$(value GENERATE_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable GENERATE_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; exec $(SCRIPT_DIR)/generate.sh "$$@"

validate:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_meta,VALIDATE_ARGS)args='$(value VALIDATE_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable VALIDATE_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; exec $(SCRIPT_DIR)/validate.sh "$$@"

matrix:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_meta,MATRIX_ARGS)args='$(value MATRIX_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable MATRIX_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; exec $(SCRIPT_DIR)/matrix.sh "$$@"

bake-print:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_meta,BAKE_PRINT_ARGS)args='$(value BAKE_PRINT_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable BAKE_PRINT_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; exec $(SCRIPT_DIR)/bake-print.sh "$$@"

catalog:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_meta,CATALOG_ARGS)args='$(value CATALOG_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable CATALOG_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; exec $(SCRIPT_DIR)/catalog.sh "$$@"

build:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_scalar_meta,PG)$(call reject_make_scalar_meta,DEBIAN)$(call reject_make_meta,BUILD_ARGS)args='$(value BUILD_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable BUILD_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; exec $(SCRIPT_DIR)/build.sh "$(value PG)" "$(value DEBIAN)" "$$@"

smoke:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_scalar_meta,CHECKS)$(call reject_make_scalar_meta,PG)$(call reject_make_scalar_meta,DEBIAN)$(call reject_make_meta,SMOKE_ARGS)args='$(value SMOKE_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable SMOKE_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; CHECKS="$(value CHECKS)" exec $(SCRIPT_DIR)/smoke.sh "$(value PG)" "$(value DEBIAN)" "$$@"

release-rehearsal:
	@$(call reject_make_meta,DATE)$(call reject_make_meta,DRY_RUN)$(call reject_make_meta,STAGING_NAMESPACE)$(call reject_make_meta,RELEASE_REHEARSAL_ARGS)args='$(value RELEASE_REHEARSAL_ARGS)'; case "$$args" in *$$'\n'*|*$$'\r'*) printf 'Unsafe make variable RELEASE_REHEARSAL_ARGS contains a newline\n' >&2; exit 2;; esac; set -- $$args; exec $(SCRIPT_DIR)/release-rehearsal.sh "$$@"
