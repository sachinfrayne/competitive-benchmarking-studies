SHELL := /bin/bash

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)

STACK ?=

ifeq ($(strip $(STACK)),)
$(error STACK is required (e.g. STACK=elasticsearch or STACK=qdrant))
endif

STACK_DIR := $(REPO_ROOT)/engines/$(STACK)/

ifeq ($(wildcard $(STACK_DIR)engine.mk),)
$(error Unknown stack '$(STACK)': missing $(STACK_DIR)engine.mk)
endif

NAMESPACE ?= default

# Jingra config is engine-local
JINGRA_CONFIG ?= $(STACK_DIR)jingra.yml
JINGRA_SCHEMAS_DIR ?= $(STACK_DIR)schemas
JINGRA_QUERIES_DIR ?= $(STACK_DIR)queries

include $(STACK_DIR)engine.mk
include $(REPO_ROOT)/make/common.mk
