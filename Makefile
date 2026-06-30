# Ansible project — convenience commands.
# Everything runs against the project-local .venv and ./collections (the global
# environment is never touched).
#
# First time:   make setup
# Overview:     make help
# Run:          make bootstrap
#
# Role testing (molecule, Docker required):
#   make molecule-setup            # one-time — installs molecule
#   make test ROLE=basic           # tests the role in a clean container
#   make test-converge ROLE=zsh    # applies the role, keeps the container alive (debug)
#
# Optional parameters:
#   make bootstrap LIMIT=ubuntu-18         # a single host only
#   make basic TAGS=basic_timezone         # a single tag only
#   make bootstrap ARGS="--check --diff"   # extra flags

PY        ?= python3.12
VENV      := .venv
BIN       := $(VENV)/bin
ANSIBLE   := $(BIN)/ansible
PLAYBOOK  := $(BIN)/ansible-playbook
GALAXY    := $(BIN)/ansible-galaxy
MOLECULE  := $(CURDIR)/$(BIN)/molecule

ROLE      ?= basic
LIMIT     ?=
TAGS      ?=
ARGS      ?=
MARGS     ?=
_limit     = $(if $(LIMIT),--limit $(LIMIT),)
_tags      = $(if $(TAGS),--tags $(TAGS),)
_opts      = $(_limit) $(_tags) $(ARGS)

.DEFAULT_GOAL := help
.PHONY: help setup deps ping syntax check bootstrap basic users ssh facts hosts clean \
        molecule-setup test test-create test-converge test-verify test-login test-destroy

help: ## Show this help listing
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## Create the venv + install ansible-core and collections (first time)
	$(PY) -m venv $(VENV)
	$(BIN)/pip install -q --upgrade pip -r requirements.txt
	$(GALAXY) collection install -r requirements.yml -p ./collections
	@$(ANSIBLE) --version | head -1

deps: ## Reinstall collections from requirements.yml (--force)
	$(GALAXY) collection install -r requirements.yml -p ./collections --force

ping: ## Check connectivity to the hosts
	$(ANSIBLE) all -m ping $(_limit)

syntax: ## Check playbook syntax (does not connect to any server)
	$(PLAYBOOK) playbooks/bootstrap.yml --syntax-check

check: ## Dry-run the bootstrap playbook (--check --diff, changes nothing)
	$(PLAYBOOK) playbooks/bootstrap.yml --check --diff $(_opts)

users: ## Run the users role only (create/disable users)
	$(PLAYBOOK) playbooks/users.yml $(_opts)

vault-edit: ## Edit the encrypted secrets file (group_vars/all/vault.yml)
	$(BIN)/ansible-vault edit group_vars/all/vault.yml

vault-view: ## View the encrypted secrets file (without editing)
	$(BIN)/ansible-vault view group_vars/all/vault.yml

# Molecule runs from the role directory -> the root ansible.cfg is not found.
# So we pass the collections path explicitly (./collections is deterministic).
test test-create test-converge test-verify test-login test-destroy: export ANSIBLE_COLLECTIONS_PATH := $(CURDIR)/collections
# Molecule invokes `ansible-playbook` via PATH. Without putting .venv/bin first,
# the global (brew) ansible-core is used -> fails on legacy hosts (Py3.6). So we
# force the venv's ansible-core 2.16 to be selected.
test test-create test-converge test-verify test-login test-destroy: export PATH := $(CURDIR)/$(BIN):$(PATH)

molecule-setup: ## Install molecule + docker driver + community.docker (for testing, one-time)
	$(BIN)/pip install -q -r requirements-dev.txt
	$(GALAXY) collection install -r requirements-dev.yml -p ./collections
	@$(MOLECULE) --version | head -1

test: ## Run the full molecule test for a role — ROLE=... [MARGS="--destroy=never"] (Docker required)
	cd roles/$(ROLE) && $(MOLECULE) test $(MARGS)

test-create: ## Create the test containers without running the role. ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) create

test-converge: ## Apply the role to the container and keep it ALIVE (debug). ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) converge $(MARGS)

test-verify: ## Re-run the verify (assertion) step only. ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) verify

test-login: ## Log into the live test container (after converge). ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) login

test-destroy: ## Destroy the test containers (cleanup). ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) destroy

facts: ## Gather facts from the hosts
	$(ANSIBLE) all -m setup $(_limit)

hosts: ## List the inventory hosts
	$(ANSIBLE) all --list-hosts $(_limit)

clean: ## Remove the venv, collections, logs, and the fact cache
	rm -rf $(VENV) ./collections log/*.log *.retry /tmp/ansible_facts
	@echo "Cleaned. To rebuild: make setup"
