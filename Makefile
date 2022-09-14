# Development management facilities
#
# This file specifies useful routines to streamline development management.
# See https://www.gnu.org/software/make/.


# Consume environment variables
ifneq (,$(wildcard .env))
	include .env
endif

# Tool configuration
SHELL := /bin/bash
GNUMAKEFLAGS += --no-print-directory

# Path record
ROOT_DIR ?= $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SOURCE_DIR ?= $(ROOT_DIR)/src
SERVICE_DIR ?= $(SOURCE_DIR)/$(SERVICE)

# Target files
ENV_FILE ?= .env
EPHEMERAL_ARCHIVES ?=

# Executables definition
GIT ?= git
DOCKER ?= docker

# Behavior configuration
SERVICE ?= service
PORT ?= 8000
SERVICE_URL ?= http://localhost:$(PORT)

IMAGE_ID ?= $(SERVICE).img
BUILD_CMD ?= make init && make setup
RUN_CMD ?= make run


%: # Treat unrecognized targets
	@ printf "\033[31;1mUnrecognized routine: '$(*)'\033[0m\n"
	$(MAKE) help

help:: ## Show this help
	@ printf "\033[33;1mGNU-Make available routines:\n"
	egrep -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[37;1m%-20s\033[0m %s\n", $$1, $$2}'

init:: veryclean ## Configure development environment
	test -r $(ENV_FILE) || cp $(ENV_FILE).example $(ENV_FILE)
	test -r '.gitmodules' && $(GIT) submodule update --init --recursive

up:: build execute ## Build and execute service

build:: clean ## Build service running environment
	$(DOCKER) run \
		--name $(IMAGE_ID) \
		--workdir /$(SERVICE) \
		--volume $(SERVICE_DIR):/$(SERVICE) \
 		--env-file $(ENV_FILE) \
		python:3.10 \
		bash -c $(BUILD_CMD)
	$(DOCKER) commit \
		--author $(shell $(GIT) config --get user.email) \
		--change 'CMD $(RUN_CMD)' \
		$(IMAGE_ID) \
		$(IMAGE_ID)

execute:: setup run ## Setup and run service

setup:: finish clean ## Prepare to run service

run:: ## Launch application locally
	$(DOCKER) start $(SERVICE) || \
	$(DOCKER) run \
		--name $(SERVICE) \
		--hostname $(SERVICE) \
		--publish $(PORT):$(PORT) \
		--workdir /$(SERVICE) \
		--volume $(SERVICE_DIR):/$(SERVICE) \
 		--env-file $(ENV_FILE) \
		--health-cmd 'curl $(SERVICE_URL) || exit 1' \
		--detach \
		$(IMAGE_ID) \
		$(RUN_CMD)

bash:: ## Connect to service terminal
	$(DOCKER) exec \
		--env-file $(ENV_FILE) \
		--interactive \
		--tty \
		$(SERVICE) \
		bash

finish:: ## Stop service execution
	-$(DOCKER) exec $(SERVICE) bash -c 'make finish'
	$(DOCKER) stop $(SERVICE)

status:: ## Present service running status
	@$(DOCKER) logs --tail 10 $(SERVICE)
	echo
	$(DOCKER) ps \
		--filter name=$(SERVICE) \
		--format 'table {{.ID}}\t{{.Names}}\t{{.Ports}}\t{{.Networks}}\t{{.State}}\t{{.Status}}\t{{.Command}}' \
		--all
	echo
	$(DOCKER) stats --no-stream $(SERVICE)

ping:: ## Verify service reachability
	curl -v $(SERVICE_URL)

open:: ## Browse service
	xdg-open $(SERVICE_URL)

#test:: ## Verify application's behavior requirements completeness

#publish:: build ## Upload application container to registry

#deploy:: build ## Deploy application

clean:: ## Delete project ephemeral archives
	-rm -fr $(EPHEMERAL_ARCHIVES)
	$(DOCKER) container rm --force $(IMAGE_ID) $(SERVICE)


veryclean:: finish clean ## Delete all generated files
	-$(DOCKER) image rm $(IMAGE_ID)


.EXPORT_ALL_VARIABLES:
.ONESHELL:
.PHONY: help init up build execute setup run bash finish status ping open clean veryclean
