# ClearXRay

Минимальный, воспроизводимый деплой `Xray REALITY`, который соответствует рабочему состоянию сервера после ремонта.

Цель этого репозитория:

- зафиксировать, что именно ломалось;
- отделить доказанные факты от гипотез;
- сохранить минимальную рабочую конфигурацию;
- дать автодеплой без лишних опций, которые мешают диагностике.

## Что находится в репозитории

- `docs/ROOT_CAUSE.md`
  Подробный технический разбор: что было доказано, что осталось гипотезой, чем отличался нерабочий конфиг от рабочего.
- `docs/HANDSHAKE_EXPLAINED.md`
  Техническое объяснение `REALITY`-handshake без упрощений и без "детских" аналогий.
- `scripts/install-minimal-reality.sh`
  Автоматическая установка минимального рабочего `Xray REALITY` на Ubuntu.
- `scripts/generate-client-link.sh`
  Генерация клиентской `vless://`-ссылки из сохранённых параметров.
- `scripts/self-test-reality.sh`
  Локальный self-test через временный SOCKS-inbound.

## Рабочий профиль

Именно такой формат профиля в итоге заработал:

```text
vless://UUID@SERVER_IP:443?encryption=none&type=tcp&security=reality&sni=www.mix.com&fp=chrome&pbk=PASSWORD&sid=SHORTID#minimal-www-mix
```

Критичные свойства рабочего варианта:

- `type=tcp`
- без `flow=xtls-rprx-vision`
- один inbound
- один порт
- один `serverName`
- один и тот же hostname в `target` и `serverNames`

## Деплой

На чистом Ubuntu VPS:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/nesfe/ClearXRay/main/scripts/install-minimal-reality.sh)
```

Если репозиторий пока только локальный:

```bash
scp -r ClearXRay root@ВАШ_СЕРВЕР:/root/
ssh root@ВАШ_СЕРВЕР
bash /root/ClearXRay/scripts/install-minimal-reality.sh
```

## Какие файлы создаются на сервере

После установки:

- `/root/clearxray.env`
- `/root/clearxray-link.txt`
- `/usr/local/etc/xray/config.json`

## Почему конфиг здесь минимальный

Смысл не в "максимуме возможностей", а в минимуме переменных.

Если `REALITY` перестаёт работать, в первую очередь мешают:

- несколько inbound'ов во время отладки;
- `flow=xtls-rprx-vision`;
- повторное использование старых credential-наборов;
- одновременная смена SNI, портов, ключей и клиентов.

Поэтому в этом репозитории зафиксирован не "универсальный монстр-конфиг", а рабочий baseline.

