# Ansible project — qulay buyruqlar.
# Hammasi loyiha ichidagi .venv va ./collections bilan ishlaydi (global tegmaydi).
#
# Birinchi marta:   make setup
# Ko'rish:          make help
# Ishga tushirish:  make bootstrap
#
# Rol testi (molecule, Docker kerak):
#   make molecule-setup            # bir marta — molecule o'rnatadi
#   make test ROLE=basic           # rolni toza konteynerda test qiladi
#   make test-converge ROLE=zsh    # qo'llab, konteynerni tirik qoldiradi (debug)
#
# Ixtiyoriy parametrlar:
#   make bootstrap LIMIT=ubuntu-18         # faqat bitta host
#   make basic TAGS=basic_timezone         # faqat bitta teg
#   make bootstrap ARGS="--check --diff"   # qo'shimcha bayroqlar

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
_limit     = $(if $(LIMIT),--limit $(LIMIT),)
_tags      = $(if $(TAGS),--tags $(TAGS),)
_opts      = $(_limit) $(_tags) $(ARGS)

.DEFAULT_GOAL := help
.PHONY: help setup deps ping syntax check bootstrap basic users ssh facts hosts clean \
        molecule-setup test test-converge test-verify test-login test-destroy

help: ## Shu yordam ro'yxatini ko'rsatadi
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

setup: ## venv yaratadi + ansible-core va collections o'rnatadi (birinchi marta)
	$(PY) -m venv $(VENV)
	$(BIN)/pip install -q --upgrade pip -r requirements.txt
	$(GALAXY) collection install -r requirements.yml -p ./collections
	@$(ANSIBLE) --version | head -1

deps: ## Collections'ni requirements.yml dan qayta o'rnatadi (--force)
	$(GALAXY) collection install -r requirements.yml -p ./collections --force

ping: ## Hostlarga ulanishni tekshiradi
	$(ANSIBLE) all -m ping $(_limit)

syntax: ## Playbook sintaksisini tekshiradi (serverga ulanmaydi)
	$(PLAYBOOK) playbooks/bootstrap.yml --syntax-check

check: ## Bootstrap'ni quruq ishga tushiradi (--check --diff, hech narsa o'zgartirmaydi)
	$(PLAYBOOK) playbooks/bootstrap.yml --check --diff $(_opts)

bootstrap: ## To'liq bootstrap (basic + users)
	$(PLAYBOOK) playbooks/bootstrap.yml $(_opts)

basic: ## Faqat basic rol (timezone + asosiy paketlar)
	$(PLAYBOOK) playbooks/basic.yml $(_opts)

users: ## Faqat users rol (foydalanuvchilar yaratish/disable)
	$(PLAYBOOK) playbooks/users.yml $(_opts)

ssh: ## Faqat ssh rol (AllowUsers — kim kira oladi)
	$(PLAYBOOK) playbooks/ssh.yml $(_opts)

# Molecule rol papkasidan ishga tushadi -> ildizdagi ansible.cfg topilmaydi.
# Shuning uchun collections yo'lini aniq beramiz (./collections deterministik).
test test-converge test-verify test-login test-destroy: export ANSIBLE_COLLECTIONS_PATH := $(CURDIR)/collections

molecule-setup: ## Molecule + docker driver + community.docker o'rnatadi (test uchun, bir marta)
	$(BIN)/pip install -q -r requirements-dev.txt
	$(GALAXY) collection install -r requirements-dev.yml -p ./collections
	@$(MOLECULE) --version | head -1

test: ## Rolni molecule bilan to'liq test qiladi — ROLE=basic|zsh|ssh|users (Docker kerak)
	cd roles/$(ROLE) && $(MOLECULE) test

test-converge: ## Rolni konteynerga qo'llaydi, konteynerni TIRIK qoldiradi (debug). ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) converge

test-verify: ## Faqat verify (tekshiruv) bosqichini qayta ishga tushiradi. ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) verify

test-login: ## Tirik test konteyneriga kiradi (converge'dan keyin). ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) login

test-destroy: ## Test konteynerlarini o'chiradi (tozalash). ROLE=...
	cd roles/$(ROLE) && $(MOLECULE) destroy

facts: ## Hostlardan ma'lumot (facts) yig'adi
	$(ANSIBLE) all -m setup $(_limit)

hosts: ## Inventory hostlarini ro'yxatlaydi
	$(ANSIBLE) all --list-hosts $(_limit)

clean: ## venv, collections, log va fact-keshni o'chiradi
	rm -rf $(VENV) ./collections log/*.log *.retry /tmp/ansible_facts
	@echo "Tozalandi. Qayta tiklash uchun: make setup"
