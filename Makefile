ifndef MAIN_MK_INCLUDED
MAIN_MK_INCLUDED := 1

HOST_BASE_DIR      := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
OCI_WORKING_DIR    := /a
MAIN_BASE_DIR      := $(shell grep -q -x '0::/' /proc/self/cgroup && echo "$(OCI_WORKING_DIR)" || echo "$(HOST_BASE_DIR)")

.ONESHELL:
SHELL := /bin/bash
.SHELLFLAGS: -x

ENV_FILE           ?= $(MAIN_BASE_DIR)/.env
ENV_TEMPLATE_FILE  ?= $(ENV_FILE).template
-include $(ENV_FILE)
.EXPORT_ALL_VARIABLES:

COMMON_DIR         ?= $(MAIN_BASE_DIR)/common
COMMON_SCRIPTS_DIR ?= $(COMMON_DIR)/scripts
COMMON_MAKE_SH     ?= $(COMMON_SCRIPTS_DIR)/make.sh

OCI                ?= podman
OCI_ENV_VARS       ?= $(shell grep -v '^#' $(ENV_FILE) | sed -e 's/^\(^[^=]*\)=.*/\1/' | tr '\n' ' ')
OCI_ENV_ARGS       ?= $(foreach _s,$(OCI_ENV_VARS),--secret $(_s),type=env) $(foreach _s,$(OCI_ENV_VARS),--secret TF_VAR_$(_s),type=env)
OCI_ENV_DEPS       ?= $(foreach _t,$(OCI_ENV_VARS),_env-$(_t))

OCI_ARGS           ?= --rm --cgroup-manager=cgroupfs
OCI_COMPOSE        ?= $(OCI)-compose
OCI_DEPS           ?= $(ENV_FILE) $(OCI_ENV_DEPS)
OCI_DIR            ?= $(COMMON_DIR)/oci
OCI_COMPOSE_YAML   ?= $(MAIN_BASE_DIR)/$(OCI_COMPOSE).yaml
OCI_COMPOSE_ARGS   ?= --file $(OCI_COMPOSE_YAML)
OCI_BUILD_DIR      ?= $(COMMON_DIR)/oci
OCI_BUILD_DEFS     ?= $(shell yq -r '.services | keys | join(" ")' $(OCI_COMPOSE_YAML))
OCI_BUILD_TARGETS  ?= $(foreach DEF,$(OCI_BUILD_DEFS),build_$(DEF))
OCI_BUILD_VERSION  ?= 0.0.1
OCI_BUILD_ARGS     ?= $(OCI_ARGS) $(foreach _t,$(OCI_ENV_VARS),--build-arg '$(_t)=$${$(_t)}')
OCI_BUILD_ARGS_END ?= 
OCI_BUILD_IMAGE    ?=
#xOCI_BUILD_TAG      ?= localhost/oci_$(OCI_BUILD_IMAGE):latest
OCI_BUILD          ?= $(OCI_COMPOSE) $(OCI_COMPOSE_ARGS) --podman-build-args="$(OCI_BUILD_ARGS) $(OCI_BUILD_ARGS_END)" build
OCI_RUN_ARGS       ?= $(OCI_ARGS) $(OCI_ENV_ARGS)
OCI_RUN            ?= $(OCI_COMPOSE) $(OCI_COMPOSE_ARGS) --podman-run-args="$(OCI_RUN_ARGS) $${OCI_RUN_EXTRA_ARGS}" run 
OCI_SHELLS         ?= devops-root-/bin/bash alpine-root-/bin/bash busybox-root-/bin/sh debian-root-/bin/bash imagebuilder_dm200-root-/bin/bash pandoc-root-/bin/sh superlinter-root-/bin/sh tf-root-/bin/bash
OCI_DEVOPS         ?= $(OCI_RUN) devops

TF_CMD             ?= tofu -chdir=$(TF_DIR)
TF_DIR             ?= .
TF_BASE_DIRS       ?= common/vm_images doms/lenostream doms/lenoline doms/citadell-pod0 doms/citadell
TF_BACKUP_FILE     ?= .tf_backup
TF_PLAN_FILE       ?= .tf_plan
TF_APPLY_ARGS      ?= -input=false \
                        -lock-timeout=15m \
                        -auto-approve \
                        -backup="$(TF_BACKUP_FILE)" \
                        $(TF_PLAN_FILE)
TF_IMPORT_ARGS     ?= -input=false \
                        -lock-timeout=15m
TF_PLAN_ARGS       ?= -input=false \
                        -lock-timeout=15m \
                        -detailed-exitcode \
                        -out="$(TF_PLAN_FILE)"

.DEFAULT_GOAL      := all
GOALS              ?= \
                      all \
                      build \
                      clean \
                      cache-clean \
                      distclean \
                      lint \
                      maintainer-clean \
                      oci-clean \
                      oci-secrets-clean \
                      pristine \
                      realclean \
                      shell \
                      tf \
                      tfinit \
                      tfplan \
                      tfapply \
                      usage
.PHONY: $(GOALS)

all: usage

build: $(OCI_BUILD_TARGETS)

clean:
	rm -f home.tar.gz common/ansible/archives/home.tar.gz doms/citadell-pod0/home.tar.gz

cache-clean:

distclean:

lint:
	$(OCI_RUN) \
	  -e CREATE_LOG_FILE=true \
	  -e DEFAULT_BRANCH=main \
	  -e LINTER_RULES_PATH=./common/oci/superlinter/rootfs/linters \
	  -e LOG_FILE=./output/super-linter.log \
	  -e LOG_LEVEL=DEBUG \
	  -e RUN_LOCAL=true \
	  -e SAVE_SUPER_LINTER_OUTPUT=true \
	  -e SAVE_SUPER_LINTER_SUMMARY=true \
	  -e SUPER_LINTER_OUTPUT_DIRECTORY_NAME=output \
	  superlinter
	  #-e VALIDATE_ALL_CODEBASE=false \

maintainer-clean:

oci-clean:
	$(OCI) system prune --all --force
	$(OCI) volume prune --force
	$(OCI) rmi $(OCI_IMAGE_DEVOPS)

oci-secrets: $(OCI_ENV_DEPS)

oci-secrets-clean:
	$(OCI) secret rm -a

pristine:

realclean:

shell: shell_devops-root-/bin/bash

vm_images:
	$(OCI_DEVOPS) $(MAKE) _vm_images
.PHONY: _vm_image

_vm_images:
	$(COMMON_MAKE_SH) MAKE_TARGET=incus_image_metadata_clean
	$(COMMON_MAKE_SH) MAKE_TARGET=incus_image_metadata
	#$(COMMON_MAKE_SH) MAKE_TARGET=incus_image_clean
	#$(COMMON_MAKE_SH) MAKE_TARGET=incus_image

.PHONY: _vm_images

tf: tfinit tfplan tfapply

#tfinit: tfinit-doms/citadell-pod0
#
#tfplan: tfplan-doms/citadell-pod0
#
#tfapply: tfapply-doms/citadell-pod0
#
#tfdestroy: tfdestroy-doms/citadell-pod0 
#
tfinit: tfinit-doms/lenoline

tfplan: tfplan-doms/lenoline

tfapply: tfapply-doms/lenoline

tfdestroy: tfdestroy-doms/lenoline

define TFAPPLY_DEF
tfapply-$(1):
	$(eval TF_DIR := $(1))
	$(OCI_DEVOPS) $(TF_CMD) apply $(TF_APPLY_ARGS)
.PHONY: tfapply-$(1)
endef
$(foreach _t,$(TF_BASE_DIRS),$(eval $(call TFAPPLY_DEF,$(_t))))

define TFDESTROY_DEF
tfdestroy-$(1):
	$(eval TF_DIR := $(1))
	$(OCI_DEVOPS) $(TF_CMD) plan -destroy $(TF_PLAN_ARGS)
	$(OCI_DEVOPS) $(TF_CMD) apply -destroy $(TF_APPLY_ARGS)
.PHONY: tfapply-$(1)
endef
$(foreach _t,$(TF_BASE_DIRS),$(eval $(call TFDESTROY_DEF,$(_t))))

define TFINIT_DEF
tfinit-$(1):
	$(eval TF_DIR := $(1))
	$(OCI_DEVOPS) $(TF_CMD) init
.PHONY: tfinit-$(1)
endef
$(foreach _t,$(TF_BASE_DIRS),$(eval $(call TFINIT_DEF,$(_t))))

define TFPLAN_DEF
tfplan-$(1):
	$(eval TF_DIR := $(1))
	$(OCI_DEVOPS) $(TF_CMD) plan $(TF_PLAN_ARGS)
.PHONY: tfplan-$(1)
endef
$(foreach _t,$(TF_BASE_DIRS),$(eval $(call TFPLAN_DEF,$(_t))))

imagebuilder_dm200:
	$(eval IMAGEBUILD_ARGS_EXTRA += V=s)
	$(OCI_RUN) imagebuilder_dm200 \
	 make image \
	 PROFILE="netgear_dm200" \
	 PACKAGES="-dsl-vrx200-firmware-xdsl-a -dsl-vrx200-firmware-xdsl-b-patch" \
	 FILES="files" \
	 DISABLED_SERVICES="" \
	 $(IMAGEBUILD_ARGS_EXTRA)

imagebuilder_dm200_upgrade:
	ssh root@198.18.240.240 'tar c -C / -f - -X /.tar_exclude /' | gzip -c > /var/tmp/exetel_backup_$$(date +%Y%m%d).tar.gz
	scp -O common/oci/imagebuilder_dm200/bin/targets/lantiq/xrx200_legacy/openwrt-*-squashfs-sysupgrade.bin root@198.18.240.240:/tmp
	ssh root@198.18.240.240 'sysupgrade -i -v /tmp/openwrt-*-squashfs-sysupgrade.bin'

home.tar.gz:
	shopt -s extglob dotglob
	tar cfz home.tar.gz --exclude=home.tar.gz --exclude=doms/citadell-pod0/home.tar.gz --exclude-from=.gitignore --transform='s#^#ds/src/github.com/whateverany-com/home/#' !(home.tar.gz)
	shopt -u extglob dotglob
	ln -f home.tar.gz doms/citadell-pod0/home.tar.gz
	ln -f home.tar.gz common/ansible/archives/home.tar.gz

define SHELL_DEF
shell_$(1):
	$(OCI_RUN) --user $(word 2,$(subst -, ,$(1))) --entrypoint "" $(word 1,$(subst -, ,$(1))) $(word 3,$(subst -, ,$(1)))
.PHONY: shell_$(1)
endef
$(foreach _t,$(OCI_SHELLS),$(eval $(call SHELL_DEF,$(_t))))

define BUILD_DEF
build_$(1): OCI_BUILD_TAG = localhost/whateverany/$(1):$(OCI_BUILD_VERSION)
	$(eval OCI_BUILD_TAG = localhost/whateverany/$(1):$(OCI_BUILD_VERSION))

build_$(1):
	$(eval OCI_BUILD_IMAGE := $(1))
	$(eval OCI_BUILD_ARGS_END := --tag localhost/whateverany/$(1):$(OCI_BUILD_VERSION))
	$(eval xOCI_BUILD_ARGS_END := --no-cache)
	@cd $(OCI_BUILD_DIR) && $(OCI_BUILD) "$(1)"
	@$(OCI) images --filter "reference=$(OCI_BUILD_TAG)" --format "{{.Repository}}:{{.Tag}}" | grep -q "$(OCI_BUILD_TAG)" && echo $(OCI) rmi $(OCI_BUILD_TAG)
.PHONY: build_$(1)
endef
$(foreach _i,$(OCI_BUILD_DEFS),$(eval $(call BUILD_DEF,$(_i))))

$(ENV_FILE):
	@:
#	$(info INFO: _env)
	$(if $(wildcard $(ENV_FILE)),, $(info INFO: $(ENV_FILE) doesn't exist, copying $(ENV_FILE))$(file > $(ENV_FILE), $(file < $(ENV_TEMPLATE_FILE))))
.PHONY: $(ENV_FILE)

_env-%:
	@$(OCI) secret ls --filter Name="$(*)" --format '{{.Name}}' | grep -q "$(*)" || (echo -n "$($(*))" | $(OCI) secret create "$(*)" -) && (echo -n "$($(*))" | $(OCI) secret create "TF_VAR_$(*)" -)
.PHONY: _env-%

usage:
	@:
	$(info INFO: $(MAKE) $(GOALS))

endif # MAIN_MK_INCLUDED
