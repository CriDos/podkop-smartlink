# podkop-smartlink v1.0.0

> Companion для [Podkop](https://github.com/itdoginfo/podkop): импорт VPN-подписок и sticky health-checked выбор сервера для selector-группы sing-box.

![Podkop SmartLink](assets/scr1.png)

## Требования

Установленный Podkop:

```sh
sh <(wget -O - https://raw.githubusercontent.com/itdoginfo/podkop/refs/heads/main/install.sh)
```

## Установка / Обновление

```sh
sh <(wget -O - https://raw.githubusercontent.com/CriDos/podkop-smartlink/refs/heads/main/_install.sh)
```

## Удаление

```sh
sh <(wget -O - https://raw.githubusercontent.com/CriDos/podkop-smartlink/refs/heads/main/_uninstall.sh)
```

Конфиг сохраняется. Полное удаление: `rm -f /etc/config/podkop-smartlink`

## Возможности

- Подписки и прямые ссылки (`vless://`, `ss://`, `trojan://`) в одном списке
- Sticky-выбор — текущий сервер не меняется, пока пинг в норме
- Автопереключение после N ошибок подряд (score-based с приоритетом источников)
- Статистика: доступность и стабильность по каждому серверу
- LuCI-интерфейс с drag-and-drop приоритета, ручным выбором сервера, i18n
- Проверка доступности через VPN-туннель до настраиваемого адреса

## Настройка

LuCI: **Services → Podkop SmartLink**

## CLI

```sh
podkop-smartlink get_status          # состояние (JSON)
podkop-smartlink get_sources         # источники (JSON)
podkop-smartlink ping_all            # пинг всех серверов
podkop-smartlink ping_source <idx>   # пинг одного источника
podkop-smartlink select_proxy <tag>  # ручной выбор сервера
podkop-smartlink refresh_now         # обновить подписки (фон)
podkop-smartlink reset_stats         # сброс статистики
podkop-smartlink get_info            # система (JSON)
podkop-smartlink show_version        # версия
```

## Расширение протоколов (опционально)

sing-box с расширенными протоколами (xhttp и др.):

```sh
sh <(wget -O - https://raw.githubusercontent.com/EikeiDev/OpenWRT-sing-box-extended/refs/heads/main/install.sh)
```
