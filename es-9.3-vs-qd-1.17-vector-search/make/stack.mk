SHELL := /bin/bash

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

STACK ?=

ifeq ($(strip $(STACK)),)
$(error STACK is required (e.g. STACK=elasticsearch or STACK=qdrant))
endif

ifeq ($(filter $(STACK),elasticsearch qdrant),)
$(error Unknown STACK '$(STACK)' (expected 'elasticsearch' or 'qdrant'))
endif

STACK_DIR := $(REPO_ROOT)/engines/$(STACK)/
ENGINE_ENV := $(REPO_ROOT)/infra/variables/$(STACK).env

-include $(ENGINE_ENV)

NAMESPACE ?= default

# Jingra config is engine-local
JINGRA_CONFIG ?= $(STACK_DIR)jingra.yml
JINGRA_SCHEMAS_DIR ?= $(STACK_DIR)schemas
JINGRA_QUERIES_DIR ?= $(STACK_DIR)queries

include $(REPO_ROOT)/make/$(STACK).mk
include $(REPO_ROOT)/make/common.mk
