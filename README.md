# ClearXRay

Минимальный и воспроизводимый `Xray REALITY`, который был получен после лабораторного разбора нерабочей конфигурации.

## Главный Лабораторный Вывод

> **Проблему ломал `flow=xtls-rprx-vision`.**
>
> Это подтверждено A/B-тестом:
>
> - `443`: рабочий baseline без `flow` -> работает
> - `9443`: тот же самый конфиг, тот же самый сервер, тот же самый `UUID`, тот же самый `pbk`, тот же самый `shortId`, тот же самый `SNI`, но добавлен только `flow=xtls-rprx-vision` -> таймаут

Это не общая теория "про весь интернет". Это практический вывод по конкретному серверу, конкретному клиенту и конкретной рабочей конфигурации.

## Что делает этот репозиторий

- фиксирует техническую причину поломки;
- сохраняет минимальный рабочий baseline;
- даёт один установочный скрипт в стиле `V2RayTun`;
- очищает сервер перед установкой;
- ставит `Xray REALITY` без `Vision`;
- выдаёт готовую `vless://`-ссылку для вставки в клиент.

## Установка одной командой

На чистом или грязном Ubuntu VPS:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nesfe/ClearXRay/main/install.sh)
```

Скрипт:

- чистит старый мусор;
- удаляет Docker / Amnezia / Outline;
- ставит `Xray`;
- генерирует новый `UUID`, keypair и `shortId`;
- пишет минимальный рабочий `REALITY`-конфиг;
- проверяет конфиг;
- настраивает `ufw`;
- запускает сервис;
- выдаёт готовую клиентскую ссылку.

## Рабочий Формат Профиля

```text
vless://UUID@SERVER_IP:443?encryption=none&type=tcp&security=reality&sni=www.mix.com&fp=chrome&pbk=PASSWORD&sid=SHORTID#clearxray-www.mix.com
```

Критичные свойства:

- `type=tcp`
- без `flow=xtls-rprx-vision`
- один inbound
- один порт
- один `serverName`
- один и тот же hostname в `target` и `serverNames`

## Структура Репозитория

- `install.sh`
  Один полный установщик для запуска через `curl | bash`
- `docs/ROOT_CAUSE.md`
  Подробный техразбор причины поломки
- `docs/HANDSHAKE_EXPLAINED.md`
  Техническое объяснение `REALITY`-handshake без упрощений
- `scripts/install-minimal-reality.sh`
  Локальная версия установщика
- `scripts/generate-client-link.sh`
  Генерация клиентской ссылки
- `scripts/self-test-reality.sh`
  Локальный self-test через временный SOCKS inbound

## Какие файлы создаются на сервере

После установки:

- `/root/clearxray.env`
- `/root/clearxray-link.txt`
- `/usr/local/etc/xray/config.json`

## Что зафиксировано как baseline

Рабочий baseline:

- `VLESS + REALITY`
- `network=raw`
- без `Vision`
- `www.mix.com`
- новый `UUID`
- новый keypair
- новый `shortId`

Нерабочая ветка:

- `VLESS + REALITY + flow=xtls-rprx-vision`

Если задача — получить рабочий VPN, а не экспериментировать с несовместимостью, брать нужно именно baseline без `Vision`.

