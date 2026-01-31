# Review Iteration 4 — 2026-01-31 16:35

## Источник

- Design: `docs/plans/2026-01-31-selectel-api-automation-design.md`
- Plan: `docs/plans/2026-01-31-selectel-api-automation-impl.md`
- Codex output: `/home/zinin/.claude/codex-interaction/2026-01-31-16-27-33-design-review-selectel-api-automation-iter-4/output.txt`

## Замечания

### [IMPL-1] Несовместимый формат fingerprint ключа (SHA256 vs MD5)

> Сравнение fingerprint может всегда падать, если облако возвращает MD5 (типично для OpenStack/Nova), а `ssh-keygen -l` по умолчанию выдаёт SHA256.

**Severity:** High
**Статус:** Новое
**Ответ:** Использовать ssh-keygen -E md5 (Recommended)
**Действие:** Изменён ssh-keygen на `-E md5` с удалением префикса `MD5:` в gpu-start и setup-start

---

### [IMPL-2] setup-start нельзя использовать через selectel.sh

> В `setup-start` нет способа передать базовый образ через CLI/`.env`, а playbook при пустом `base_image` просто падает.

**Severity:** Medium
**Статус:** Новое
**Ответ:** Добавить --image и BASE_IMAGE_NAME (Recommended)
**Действие:** Добавлен BASE_IMAGE_NAME в .env.example, --image в selectel.sh для setup-start

---

### [OPS-1] Не указан обязательный зависимый инструмент jq

> `selectel.sh` строит JSON через `jq`, но в зависимостях jq не указан и нет проверки его наличия.

**Severity:** Medium
**Статус:** Новое
**Ответ:** Добавить jq в prerequisites (Recommended)
**Действие:** jq добавлен в apt install в design.md, добавлена проверка в selectel.sh

---

### [ERR-1] image-upload с --force может гоняться с удалением

> При `--force` старый образ удаляется и сразу создаётся новый. Удаление асинхронное, возможна гонка.

**Severity:** Medium
**Статус:** Новое
**Ответ:** Дождаться удаления (Recommended)
**Действие:** Добавлено ожидание удаления образа (until images | length == 0) перед загрузкой

---

### [ERR-2] image-download не проверяет status == active

> Скачивание запускается без проверки статуса. При queued/saving CLI может упасть или записать битый файл.

**Severity:** Medium
**Статус:** Новое
**Ответ:** Добавить проверку status: active (Recommended)
**Действие:** Добавлено ожидание status: active с retries/delay перед скачиванием

---

### [ERR-3] volume_info без details: true может не возвращать attachments

> В disk-delete и image-create-from-disk используется volume_info без details: true, но затем читается attachments.

**Severity:** Medium
**Статус:** Новое
**Ответ:** Добавить details: true (Recommended)
**Действие:** Добавлен details: true в volume_info для disk-delete и image-create-from-disk

---

### [SEC-1] SSH открыт на 0.0.0.0/0 без параметризации

> В network-setup правило SSH открыто на весь интернет без опции сузить доступ.

**Severity:** Medium
**Статус:** Новое
**Ответ:** Оставить как есть — пользователь решил разрешить подключение всем
**Действие:** Без изменений

---

## Изменения в документах

| Файл | Изменение |
|------|-----------|
| `design.md` | Добавлено 6 новых требований, jq в зависимости |
| `impl.md` (Task 1) | BASE_IMAGE_NAME в .env, проверка jq, --image для setup-start |
| `impl.md` (Task 8) | ssh-keygen -E md5 для fingerprint |
| `impl.md` (Task 10) | ssh-keygen -E md5 для fingerprint |
| `impl.md` (Task 11) | details: true в volume_info |
| `impl.md` (Task 12) | details: true в volume_info |
| `impl.md` (Task 13) | Ожидание status: active перед скачиванием |
| `impl.md` (Task 14) | Ожидание удаления образа перед загрузкой нового |
| `impl.md` (Summary) | Добавлена секция "Iteration 4" с 7 изменениями |

## Статистика

- Всего замечаний: 7
- Новых: 7
- Повторов (автоответ): 0
- Пользователь сказал "стоп": Нет
