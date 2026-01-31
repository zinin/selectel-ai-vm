# Review Iteration 3 — 2026-01-31 16:22

## Источник

- Design: `docs/plans/2026-01-31-selectel-api-automation-design.md`
- Plan: `docs/plans/2026-01-31-selectel-api-automation-impl.md`
- Codex output: `/home/zinin/.claude/codex-interaction/2026-01-31-16-07-45-design-review-selectel-api-automation-iter-3/output.txt`

## Замечания

### [IMPL-1] Сбой из-за неопределённого `server_disk`

> В `gpu-start.yml` переменная `server` вычисляется как `server_disk if server_disk.server is defined else server_image`. Если запуск через образ, `server_disk` не определён, и playbook падает.

**Статус:** Новое
**Ответ:** Выставлять server внутри каждой ветки (Recommended)
**Действие:** Добавлен set_fact server сразу после создания сервера в обеих ветках

---

### [IMPL-2] Неверный параметр сети для `openstack.cloud.server`

> В `gpu-start.yml` и `setup-start.yml` используется `network:` вместо `networks:` (список).

**Статус:** Новое
**Ответ:** Заменить на networks: list (Recommended)
**Действие:** Заменено `network:` на `networks: - name:` во всех playbooks

---

### [ERR-1] Удаление VM по неуникальному имени

> `gpu-stop.yml` удаляет сервер по имени без проверки уникальности. При дубликатах имён риск удалить не ту VM.

**Статус:** Новое
**Ответ:** Требовать ровно одно совпадение (Recommended)
**Действие:** Добавлена валидация `servers | length > 1` с выводом списка

---

### [ERR-2] Нет проверки, что boot-диск свободен

> В `gpu-start.yml` при `--disk` не проверяется статус тома. Если том `in-use`, создание сервера упадёт.

**Статус:** Новое
**Ответ:** Проверять status == available (Recommended)
**Действие:** Добавлена проверка `status != 'available'` с понятным сообщением об ошибке

---

### [ERR-3] В `setup-start` нет очистки тома при сбое

> `setup-start.yml` создаёт том, но при падении на создании сервера том остаётся.

**Статус:** Новое
**Ответ:** Обернуть в block/rescue (Recommended)
**Действие:** Добавлен block/rescue с удалением тома в rescue-секции

---

### [EDGE-1] Хрупкая обработка аргументов и пробелов

> `selectel.sh` передаёт extra-vars как `-e "boot_image_name=$IMAGE_NAME"`, что ломается при пробелах в имени.

**Статус:** Новое
**Ответ:** Передавать через JSON (Recommended)
**Действие:** Все extra-vars теперь передаются через jq и JSON формат

---

### [SEC-1] Ошибки при добавлении правил SG скрываются

> В `network-setup.yml` для SSH/ICMP правил стоит `ignore_errors: true`. Это маскирует запреты политики.

**Статус:** Новое
**Ответ:** Убрать ignore_errors, обработать дубликаты (Recommended)
**Действие:** Заменено на `failed_when: ... and 'already exists' not in ...`

---

### [SEC-2] Нет проверки fingerprint существующего keypair

> При создании keypair не проверяется, совпадает ли fingerprint с существующим ключом.

**Статус:** Новое
**Ответ:** Сравнивать fingerprint (Recommended)
**Действие:** Добавлены шаги: получение keypair_info, сравнение fingerprint, fail при несовпадении

---

### [EDGE-2] Коллизия имени boot-тома

> Создание тома `{{ vm_name }}-boot` со `state: present` может переиспользовать существующий том.

**Статус:** Новое
**Ответ:** Проверять существование тома (Recommended)
**Действие:** Добавлена проверка volume_info и fail если том существует

---

### [ERR-4] Риск перезаписи образов и файлов

> `image-upload.yml` не проверяет наличие образа с тем же именем, `image-download.yml` перезаписывает файл.

**Статус:** Новое
**Ответ:** Проверять и требовать --force (Recommended)
**Действие:** Добавлен параметр force и проверки существования в обоих playbooks

---

### [DOC-1] Жёстко задано имя базового образа

> В `setup-start.yml` base image фиксирован как `"Ubuntu 24.04 LTS 64-bit"`. В Selectel имя может отличаться.

**Статус:** Новое
**Ответ:** Показывать список образов
**Действие:** При отсутствии base_image выводится список Ubuntu-образов и просьба указать явно

---

## Изменения в документах

| Файл | Изменение |
|------|-----------|
| `design.md` | Добавлены 12 новых требований в таблицу "Важные детали реализации" |
| `impl.md` (Task 1) | selectel.sh: все extra-vars через JSON, добавлен --force для image-* |
| `impl.md` (Task 7) | network-setup: failed_when вместо ignore_errors для SG rules |
| `impl.md` (Task 8) | gpu-start: проверка fingerprint, проверка статуса диска, проверка существования тома, set_fact server в ветках, networks: list |
| `impl.md` (Task 9) | gpu-stop: валидация уникальности VM |
| `impl.md` (Task 10) | setup-start: fingerprint, block/rescue, интерактивный выбор образа, проверка тома, networks: list |
| `impl.md` (Task 13) | image-download: --force для перезаписи файла |
| `impl.md` (Task 14) | image-upload: --force для перезаписи образа |
| `impl.md` (Summary) | Добавлена секция "Iteration 3" с 11 изменениями |

## Статистика

- Всего замечаний: 11
- Новых: 11
- Повторов (автоответ): 0
- Пользователь сказал "стоп": Нет
