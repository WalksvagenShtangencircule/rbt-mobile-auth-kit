# RBT Mobile Call Auth Kit

Набор для быстрого повторного внедрения доработок авторизации по звонку на серверах SmartYard/RBT.

## Что делает скрипт

- включает `outgoingCall` в `server/config/config.json`
- выставляет `confirm_number` для мобильного приложения
- обновляет `server/backends/isdn/custom/custom.php`:
  - нормализация номера
  - `checkIncoming()` через Redis-ключи `isdn_incoming_*`
- ставит Lua-хук `asterisk/custom/mobile_auth.lua`:
  - перехват DID номера авторизации
  - запись факта звонка в Redis (TTL 600 сек)
  - мгновенный сброс вызова
- включает `mobile_auth` в `asterisk/config.lua`
- добавляет `#include trunks/*.conf` в `asterisk/pjsip.conf`
- генерирует trunk-конфиг в `asterisk/trunks/<trunk-name>.conf`
- перезагружает Asterisk и php-fpm (если не указан `--skip-reload`)

## Запуск

```bash
cd rbt-mobile-auth-kit
sudo bash install.sh \
  --sip-host sip.ваш-провайдер.example \
  --sip-user ВАШ_SIP_ЛОГИН \
  --sip-password 'ВАШ_ПАРОЛЬ' \
  --did 4950000000 \
  --confirm-number +74950000000 \
  --transport tcp \
  --trunk-name my_auth_trunk
```

**Не коммитьте** реальные пароли и номера в репозиторий: передавайте их только в командной строке на сервере или через переменные окружения (см. документацию провайдера).

Минимум обязательных параметров:

- `--sip-host`
- `--sip-user`
- `--sip-password`
- `--did`

## Полезные опции

- `--sip-port 5060`
- `--transport tcp|udp` (по умолчанию `tcp`)
- `--trunk-name auth_call` (по умолчанию `auth_call`)
- `--skip-reload` (если хотите перезагрузить сервисы позже вручную)

## Что сохраняется в бэкап

Перед изменениями скрипт сохраняет копии в:

`/opt/rbt/local-backups/mobile-auth-YYYYmmdd-HHMMSS`

## Проверка после установки

```bash
sudo asterisk -rx 'pjsip show registrations'
sudo asterisk -rx 'pjsip show endpoint my_auth_trunk'
```

Проверка логики звонка:

1. В приложении выбрать вход по звонку.
2. Позвонить на номер из `confirm_number`.
3. Звонок должен сразу сброситься.
4. `checkPhone` должен вернуть успешную авторизацию.

## Заливка в ваш GitHub

Репозиторий уже инициализирован в этом каталоге (ветка `main`). Дальше:

1. На GitHub: **New repository** — имя, например `rbt-mobile-auth-kit`, **без** README (чтобы не было конфликта).
2. На сервере:

```bash
cd /home/tech/rbt-mobile-auth-kit
git remote add origin https://github.com/ВАШ_ЛОГИН/rbt-mobile-auth-kit.git
# или по SSH:
# git remote add origin git@github.com:ВАШ_ЛОГИН/rbt-mobile-auth-kit.git

git push -u origin main
```

Если GitHub спросит пароль для HTTPS — используйте **Personal Access Token**, не пароль от аккаунта.

После пуша другие сервера могут ставить так:

```bash
git clone https://github.com/ВАШ_ЛОГИН/rbt-mobile-auth-kit.git
cd rbt-mobile-auth-kit
sudo bash install.sh --sip-host ... --sip-user ... --sip-password ... --did ...
```

