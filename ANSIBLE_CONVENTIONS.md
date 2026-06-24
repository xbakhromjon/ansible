# Ansible Playbook — Structure & Conventions

Bu hujjat shu repodagi Ansible loyihasining strukturasi va konventsiyalarini tasvirlaydi.
Yangi playbook yoki rol yozayotganda **shablon (template)** sifatida ishlating.

---

## 1. Repo strukturasi (yuqori daraja)

```
.
├── ansible.cfg              # Global Ansible sozlamalari
├── hosts.yml               # Asosiy (dev/lab) inventory
├── group_vars/all/         # Hamma hostlar uchun umumiy o'zgaruvchilar
│   ├── users.yml
│   ├── ssh.yml
│   ├── nginx.yml
│   └── ...
├── host_vars/              # Bitta hostga xos o'zgaruvchilar
├── files/                  # Global statik fayllar (SSH kalitlar va h.k.)
├── roles/                  # Qayta ishlatiladigan rollar (asosiy "kutubxona")
│   └── <role_name>/
├── playbooks/              # Ishga tushirish nuqtalari (har rol uchun + bootstrap)
└── projects/               # Rollarni real loyihalarga qo'llash
    └── <project>/<env>/    # masalan project-a/prod
        ├── hosts.yml       # shu muhitning inventory'si
        ├── group_vars/all/ # shu muhitning sozlamalari
        └── playbooks/      # shu muhitga deploy
```

**Asosiy g'oya — ikki qatlam:**
- **Ildiz (`roles/`, `playbooks/`)** = umumiy, qayta ishlatiladigan kutubxona; bu yerda rollar yoziladi va test qilinadi.
- **`projects/<project>/<env>/`** = o'sha rollarni konkret serverlarga, konkret sozlamalar bilan qo'llash. Ajratish ikki o'qda: **loyiha** × **muhit (dev/prod)**.

---

## 2. Rol strukturasi (standart papkalar)

Har rol kelishilgan nomdagi papkalardan iborat. Ansible ularni avtomatik o'qiydi.

```
roles/<role_name>/
├── tasks/
│   ├── main.yml         # KIRISH NUQTASI (avtomatik o'qiladi)
│   ├── install.yml      # mantiqiy bo'laklar — include_tasks bilan chaqiriladi
│   ├── config.yml
│   └── system.yml
├── handlers/
│   └── main.yml         # restart/reload — faqat notify bilan chaqiriladi
├── defaults/
│   └── main.yml         # ENG PAST prioritetli o'zgaruvchilar (override qilinadi)
├── vars/
│   ├── main.yml         # yuqori prioritetli, ichki qiymatlar
│   ├── Debian.yml       # OS-ga xos qiymatlar (include_vars bilan yuklanadi)
│   └── RedHat.yml
├── templates/
│   ├── <name>.conf.j2   # Jinja2 shablonlar (dinamik konfig)
│   └── includes/        # qayta ishlatiladigan shablon bo'laklari
├── files/               # statik fayllar (template emas, shunchaki ko'chiriladi)
├── meta/
│   └── main.yml         # metadata: muallif, platformalar, dependencies
└── molecule/
    └── default/
        ├── molecule.yml # test platformalari (docker)
        ├── converge.yml # rolni test vars bilan qo'llaydi
        ├── prepare.yml  # (ixtiyoriy) prerekvizitlar
        └── verify.yml   # natijani tekshiradi
```

### Papkalarning vazifasi va qoidalari

| Papka | Vazifa | Konventsiya |
|-------|--------|-------------|
| `tasks/main.yml` | Kirish nuqtasi | Faqat `include_tasks` bilan bo'laklarga ajrating |
| `defaults/main.yml` | Standart qiymatlar | Foydalanuvchi override qiladigan hamma narsa shu yerda |
| `vars/<OS>.yml` | OS farqlari | `include_vars: "{{ ansible_os_family }}.yml"` bilan yuklang |
| `handlers/main.yml` | Trigger amallar | Faqat `notify` orqali, run oxirida bir marta ishlaydi |
| `templates/*.j2` | Dinamik konfig | O'zgaruvchili fayllar (`{{ var }}`) |
| `files/` | Statik fayllar | O'zgarmaydigan kontent (kalitlar, skriptlar) |
| `meta/main.yml` | Metadata | `platforms`, `dependencies`, `min_ansible_version` |

---

## 3. `tasks/main.yml` shabloni

Modulli yondashuv: `main.yml` faqat boshqa fayllarni chaqiradi.

```yaml
---
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_os_family }}.yml"
  tags: [<role>, <role>_install, <role>_config]

- name: Install <role>
  ansible.builtin.include_tasks: install.yml
  tags: [<role>, <role>_install]

- name: Configure <role>
  ansible.builtin.include_tasks: config.yml
  tags: [<role>, <role>_config]
```

---

## 4. Kodlash konventsiyalari (MUHIM)

### 4.1 FQCN (to'liq modul nomlari)
Har doim to'liq nom ishlating: `ansible.builtin.apt`, `ansible.posix.selinux`,
`community.general.timezone` — qisqa `apt` emas.

### 4.2 Idempotentlik
Har task qayta-qayta ishlaganda xavfsiz bo'lsin:
- Avval holatni tekshiring, keyin o'zgartiring.
- Tekshiruv tasklarida: `changed_when: false`, kerak bo'lsa `failed_when: false`.

```yaml
- name: Check if nginx is already installed
  ansible.builtin.command: which nginx
  register: nginx_installed
  changed_when: false
  failed_when: false

- name: Install nginx package
  ansible.builtin.apt:
    name: "{{ nginx_pkg_name }}"
    state: present
  when: nginx_installed.rc != 0
```

### 4.3 OS farqlarini `when` + `vars/<OS>.yml` bilan hal qiling
Bitta rol Debian va RedHat'da ham ishlasin:

```yaml
- name: Install package (Debian)
  ansible.builtin.apt: { name: "{{ pkg_name }}", state: present }
  when: ansible_os_family == "Debian"

- name: Install package (RedHat)
  ansible.builtin.dnf: { name: "{{ pkg_name }}", state: present }
  when: ansible_os_family == "RedHat"
```

OS-ga bog'liq qiymatlar (paket nomi, servis nomi, foydalanuvchi) `vars/Debian.yml`
va `vars/RedHat.yml`da bo'lsin.

### 4.4 Teglar (tags)
Har task/include teg olsin. Konventsiya: rol nomi + sub-bo'lim nomi.

```yaml
tags: [nginx, nginx_config]
```

Bu tanlab ishga tushirish imkonini beradi:
`ansible-playbook ... --tags=nginx_config`

### 4.5 Handlerlar — o'zgarishda qayta yuklash
Konfig o'zgarganda servis faqat bir marta reload bo'lsin:

```yaml
# tasks/config.yml
- name: Deploy nginx config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
  notify: restart nginx

# handlers/main.yml
- name: restart nginx
  ansible.builtin.service:
    name: "{{ nginx_service_name }}"
    state: reloaded
```

### 4.6 O'zgaruvchilar nomlanishi
- Hamma o'zgaruvchi rol prefiksi bilan: `nginx_sites`, `nginx_allowlist_ips`.
- `defaults/`da bo'sh standartlar bering: `nginx_vhosts: []`.
- Murakkab obyektlar ro'yxati sifatida (`nginx_sites` — har site dict).

### 4.7 Validatsiya
Konfigni reload qilishdan oldin tekshiring (`nginx -t`, `haproxy -c`).

---

## 5. Playbook shabloni

Bitta rolni qo'llovchi oddiy playbook (`playbooks/<role>.yml`):

```yaml
---
- name: Apply <role> role
  hosts: all                # yoki maxsus guruh (webservers)
  become: true
  roles:
    - role: <role>
```

Ko'p rolli bootstrap playbook — **rollar tartibi mantiqan muhim**:

```yaml
---
- name: Bootstrap server — full DR playbook
  hosts: all
  become: true
  roles:
    - role: basic       # 1. timezone, paketlar
    - role: users       # 2. foydalanuvchilar
    - role: ssh         # 3. SSH (users'ga tayanadi!)
    - role: security
    - role: docker-install
    - role: devops_packages
    - role: zsh
```

> Tartib qoidasi: bog'liq rol o'zi tayanadigan roldan **keyin** turishi shart
> (masalan `ssh` `users`dan keyin, chunki AllowUsers foydalanuvchilarni talab qiladi).

---

## 6. Bajarilish tartibi (eslatma)

Bir play ichida qat'iy tartib:

```
hosts hal qilinadi
  → gather_facts (ansible_* o'zgaruvchilar)
  → pre_tasks
  → roles (ro'yxat tartibida, tepadan pastga)
  → tasks
  → handlers (notify qilinganlar, OXIRIDA bir marta)
  → post_tasks
```

- `tasks/main.yml` tepadan pastga ketma-ket.
- `include_tasks` chaqirilgan faylni **to'liq** tugatib, keyin keyingisiga o'tadi.
- `when` sharti bajarilmasa task **skip** bo'ladi (tartibni buzmaydi).
- `loop` bitta taskni har element uchun takrorlaydi.
- `strategy: linear` (default) — har task **hamma host**da tugaydi, keyin keyingi task.

---

## 7. Inventory konventsiyasi

```yaml
all:
  children:
    webservers:
      hosts:
        ubuntu_2404:
          ansible_host: 10.151.72.228
          ansible_user: ubuntu
          ansible_become: true
          ansible_ssh_private_key_file: ~/.ssh/id_ed25519
          ansible_python_interpreter: /usr/bin/python3
          ssh_extra_allow_users: [ubuntu]
```

- Hostlar mantiqiy guruhlarga (`webservers`, `ubuntu`, `rocky`) bo'linadi.
- Har host o'z `ansible_python_interpreter`ini ko'rsatadi (eski OS muammosi uchun).
- Maxfiy ma'lumotlar (parol) **Ansible Vault** bilan shifrlanishi kerak —
  inventory'da ochiq `ansible_password` yozmang.

---

## 8. Eski OS uchun Python prepare patterni

Ubuntu 18.04 / RHEL-Rocky 8'da default Python = 3.6, lekin ansible-core 2.17+
modullari Python 3.7+ talab qiladi. Yechim — boshqa hamma playdan **oldin**
`raw` modul (Python talab qilmaydigan yagona modul) bilan yangi Python o'rnatish:

```yaml
- name: Prepare — ensure an ansible-compatible Python (>= 3.7)
  hosts: all
  gather_facts: false      # facts ham Python talab qiladi — o'chiramiz
  become: true
  tasks:
    - name: Ensure Python >= 3.7 (raw, no Python required)
      ansible.builtin.raw: |
        set -e
        if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,7) else 1)'; then
          exit 0
        fi
        if command -v apt-get; then            # Ubuntu: yonma-yon o'rnatish
          command -v python3.8 && exit 0
          apt-get update -qq && apt-get install -y python3.8
        elif command -v dnf; then              # RHEL: system python3'ni almashtirish
          command -v python3.9 || dnf install -y python3.9
          alternatives --set python3 /usr/bin/python3.9
        fi
        echo PREPARE_INSTALLED_PYTHON
      register: prepare_python
      changed_when: "'PREPARE_INSTALLED_PYTHON' in prepare_python.stdout"
```

Boshqa playbookdan import qiling:

```yaml
- import_playbook: prepare.yml
- name: Real ish
  hosts: all
  roles: [users, ssh]
```

---

## 9. Molecule test konventsiyasi

Har rolda `molecule/default/` bo'lsin:

```yaml
# molecule.yml
driver:
  name: docker
platforms:
  - name: ubuntu-2404
    image: geerlingguy/docker-ubuntu2404-ansible:latest
    pre_build_image: true
  - name: rocky-10
    image: geerlingguy/docker-rockylinux10-ansible:latest
    pre_build_image: true
provisioner:
  name: ansible
verifier:
  name: ansible
```

- `converge.yml` — rolni test o'zgaruvchilari bilan qo'llaydi.
- `verify.yml` — natijani tekshiradi (`nginx -t`, fayl mavjudligi, servis holati).
- `prepare.yml` — (ixtiyoriy) prerekvizitlar (Docker, openssh-server).

Ishga tushirish:

```bash
cd roles/<role>
molecule test       # to'liq lifecycle (create → converge → verify → destroy)
molecule converge   # faqat qo'llash (tez iteratsiya)
molecule verify     # faqat tekshirish
```

---

## 10. ansible.cfg konventsiyasi

```ini
[defaults]
inventory = ./hosts.yml
host_key_checking = False
roles_path = ./roles
log_path = log/ansible.log
interpreter_python = /usr/bin/python3
gathering = smart
fact_caching = jsonfile           # facts'ni keshlash (tezlik)
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400
strategy = linear
pipelining = True                 # SSH chaqiruvlarini kamaytiradi (tezlik)

[privilege_escalation]
become = True
become_method = sudo
become_user = root

[ssh_connection]
ssh_args = -o ControlMaster=auto -o ControlPersist=60s
```

---

## Yangi rol yozish uchun cheklist

- [ ] `roles/<name>/` papkalarini yarating (tasks, defaults, handlers, templates, meta, molecule)
- [ ] `tasks/main.yml` — `include_tasks` bilan bo'laklarga ajrating
- [ ] OS farqlari → `vars/Debian.yml`, `vars/RedHat.yml` + `when`
- [ ] Override qilinadigan hamma narsa → `defaults/main.yml` (rol prefiksi bilan)
- [ ] FQCN ishlating, idempotent yozing (`changed_when`, `when`)
- [ ] Har taskka teg bering: `[<role>, <role>_<section>]`
- [ ] Konfig o'zgarsa → `notify` + handler (reload)
- [ ] Reload'dan oldin validatsiya (`-t`, `-c`)
- [ ] `playbooks/<name>.yml` ishga tushirish nuqtasini yarating
- [ ] `molecule/default/` test yozing (converge + verify)
- [ ] Bootstrap'ga qo'shsangiz — to'g'ri tartibda joylang
```