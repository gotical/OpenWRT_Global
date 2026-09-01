# OpenWRT Global — Manager

Мобильное приложение для управления роутерами OpenWRT через SSH.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/badge/release-v4.1.0-brightgreen)](https://github.com/gotical/OpenWRT_Global/releases/latest)
[![Android](https://img.shields.io/badge/Android-7.0%2B-green)](https://github.com/USAchevIP/OpenWRT_Global/releases/latest)

🌐 [rybinsklab.ru/openwrt](https://rybinsklab.ru/openwrt/) | 📱 [4PDA](https://4pda.to/forum/index.php?showtopic=911457&view=findpost&p=144455263)

---

## Русский

**OpenWRT Global — Manager** — бесплатное приложение с открытым исходным кодом для управления роутерами OpenWRT, ImmortalWrt, FriendlyWrt и LEDE через SSH.

Не требует установки LuCI или других веб-интерфейсов на роутер. Всё работает через стандартный SSH и ubus.

### Возможности

- **🌐 Интернет и WAN** — быстрая настройка российских провайдеров (Ростелеком, Билайн, Дом.ру, МТС, ТТК, МГТС, Yota, Атель), DHCP, PPPoE, WiFi as WAN, публичный IP
- **📡 WiFi** — управление радиомодулями 2.4/5/6 GHz, тепловая карта каналов, выбор ширины (HE20–HE160), WPA2/WPA3, гостевая сеть, расписание, сканер сетей
- **🤖 AI-оптимизация WiFi** — интеллектуальный анализ эфира через DeepSeek / OpenRouter, автовыбор канала и ширины
- **🔒 VPN** — WireGuard, AmneziaWG, OpenVPN, SSTP, PPTP, L2TP/IPsec, IKEv2/IPsec, импорт .conf/.ovpn, маршрутизация трафика
- **🛡 Безопасность** — файрвол, проброс портов, VLAN, блокировка клиентов, лимит скорости/трафика, статический IP, Wake-on-LAN
- **👥 Клиенты** — список DHCP-клиентов с идентификацией устройств по MAC, hostname и портам, иконки устройств, переименование, монитор соединений conntrack
- **🌐 DNS** — DNS, DNS-over-HTTPS (DoH), DNS-over-TLS (DoT), AdGuard Home, DDNS
- **🖥 Система** — дашборд (CPU/RAM графики), SSH-терминал, обновление прошивки, логи, бэкап/восстановление, температура CPU, USB-устройства
- **📦 Пакетный менеджер** — поддержка OPKG и APK, поиск и установка пакетов, мониторинг overlay
- **🌍 Сетевые инструменты** — Ping, SpeedTest, nmap, топология сети, сканирование портов
- **✅ Совместимость** — OpenWRT, ImmortalWrt, FriendlyWrt, LEDE версий 19.07–24.10

---

## English

**OpenWRT Global — Manager** is a free, open-source application for managing OpenWRT, ImmortalWrt, FriendlyWrt, and LEDE routers via SSH.

No LuCI or other web interfaces required on the router. Everything works through standard SSH and ubus.

### Features

- **🌐 Internet & WAN** — quick ISP setup, DHCP, PPPoE, WiFi as WAN, public IP
- **📡 WiFi** — 2.4/5/6 GHz radio management, channel heatmap, bandwidth selection (HE20–HE160), WPA2/WPA3, guest network, scheduler, network scanner
- **🤖 AI WiFi Optimization** — intelligent spectrum analysis via DeepSeek / OpenRouter, auto channel & bandwidth selection
- **🔒 VPN** — WireGuard, AmneziaWG, OpenVPN, SSTP, PPTP, L2TP/IPsec, IKEv2/IPsec, .conf/.ovpn import, traffic routing
- **🛡 Security** — firewall, port forwarding, VLAN, client blocking, speed/traffic limits, static IP, Wake-on-LAN
- **👥 Clients** — DHCP client list with device identification by MAC, hostname and ports, device icons, renaming, conntrack connection monitor
- **🌐 DNS** — DNS, DNS-over-HTTPS (DoH), DNS-over-TLS (DoT), AdGuard Home, DDNS
- **🖥 System** — dashboard (CPU/RAM charts), SSH terminal, firmware update, logs, backup/restore, CPU temperature, USB devices
- **📦 Package Manager** — OPKG & APK support, package search & install, overlay monitoring
- **🌍 Network Tools** — Ping, SpeedTest, nmap, network topology, port scanning
- **✅ Compatibility** — OpenWRT, ImmortalWrt, FriendlyWrt, LEDE versions 19.07–24.10

---

## Українська

**OpenWRT Global — Manager** — безкоштовний додаток з відкритим кодом для керування роутерами OpenWRT, ImmortalWrt, FriendlyWrt та LEDE через SSH.

Не потребує встановлення LuCI або інших веб-інтерфейсів на роутер. Усе працює через стандартний SSH та ubus.

### Можливості

- **🌐 Інтернет і WAN** — швидке налаштування провайдерів, DHCP, PPPoE, WiFi as WAN, публічна IP
- **📡 WiFi** — керування радіомодулями 2.4/5/6 GHz, теплова карта каналів, вибір ширини (HE20–HE160), WPA2/WPA3, гостьова мережа, розклад, сканер мереж
- **🤖 AI-оптимізація WiFi** — інтелектуальний аналіз ефіру через DeepSeek / OpenRouter, автовибір каналу та ширини
- **🔒 VPN** — WireGuard, AmneziaWG, OpenVPN, SSTP, PPTP, L2TP/IPsec, IKEv2/IPsec, імпорт .conf/.ovpn, маршрутизація трафіку
- **🛡 Безпека** — фаєрвол, проброс портів, VLAN, блокування клієнтів, ліміт швидкості/трафіку, статична IP, Wake-on-LAN
- **👥 Клієнти** — список DHCP-клієнтів з ідентифікацією пристроїв за MAC, hostname та портами, іконки пристроїв, перейменування, монітор з'єднань conntrack
- **🌐 DNS** — DNS, DNS-over-HTTPS (DoH), DNS-over-TLS (DoT), AdGuard Home, DDNS
- **🖥 Система** — дашборд (графіки CPU/RAM), SSH-термінал, оновлення прошивки, логи, бекап/відновлення, температура CPU, USB-пристрої
- **📦 Пакунковий менеджер** — OPKG та APK, пошук і встановлення пакунків, моніторинг overlay
- **🌍 Мережеві інструменти** — Ping, SpeedTest, nmap, топологія мережі, сканування портів
- **✅ Сумісність** — OpenWRT, ImmortalWrt, FriendlyWrt, LEDE версій 19.07–24.10

---

## Қазақша

**OpenWRT Global — Manager** — SSH арқылы OpenWRT, ImmortalWrt, FriendlyWrt және LEDE маршрутизаторларын басқаруға арналған ашық бастапқы коды бар тегін қосымша.

Маршрутизаторда LuCI немесе басқа веб-интерфейстерді орнату қажет емес. Барлығы стандартты SSH және ubus арқылы жұмыс істейді.

### Мүмкіндіктері

- **🌐 Интернет және WAN** — провайдерлерді жылдам баптау, DHCP, PPPoE, WiFi as WAN, жария IP
- **📡 WiFi** — 2.4/5/6 GHz радиомодульдерін басқару, каналдардың жылу картасы, енін таңдау (HE20–HE160), WPA2/WPA3, қонақ желісі, кесте, желі сканері
- **🤖 AI WiFi оңтайландыру** — DeepSeek / OpenRouter арқылы интеллектуалды эфир талдауы, канал мен енді автоматты таңдау
- **🔒 VPN** — WireGuard, AmneziaWG, OpenVPN, SSTP, PPTP, L2TP/IPsec, IKEv2/IPsec, .conf/.ovpn импорттау, трафикті бағыттау
- **🛡 Қауіпсіздік** — файрвол, порттарды бағыттау, VLAN, клиенттерді бұғаттау, жылдамдық/трафик шектеуі, статикалық IP, Wake-on-LAN
- **👥 Клиенттер** — MAC, hostname және порттар бойынша құрылғыларды анықтайтын DHCP-клиенттер тізімі, құрылғы белгішелері, атын өзгерту, conntrack қосылым мониторы
- **🌐 DNS** — DNS, DNS-over-HTTPS (DoH), DNS-over-TLS (DoT), AdGuard Home, DDNS
- **🖥 Жүйе** — бақылау тақтасы (CPU/RAM графиктері), SSH терминалы, микробағдарламаны жаңарту, логтар, резервтік көшірме/қалпына келтіру, CPU температурасы, USB құрылғылары
- **📦 Пакет менеджері** — OPKG және APK, пакеттерді іздеу және орнату, overlay бақылауы
- **🌍 Желі құралдары** — Ping, SpeedTest, nmap, желі топологиясы, порттарды сканерлеу
- **✅ Үйлесімділік** — OpenWRT, ImmortalWrt, FriendlyWrt, LEDE 19.07–24.10 нұсқалары

---

## Беларуская

**OpenWRT Global — Manager** — бясплатная праграма з адкрытым зыходным кодам для кіравання маршрутызатарамі OpenWRT, ImmortalWrt, FriendlyWrt і LEDE праз SSH.

Не патрабуе ўсталявання LuCI або іншага вэб-інтэрфейсу на маршрутызатары. Усё працуе праз стандартныя SSH і ubus.

### Магчымасці

- **🌐 Інтэрнэт і WAN** — DHCP, PPPoE, WiFi as WAN і публічны IP
- **📡 Wi-Fi** — кіраванне радыёмодулямі, каналамі, шырынёй, WPA2/WPA3 і гасцявой сеткай
- **🤖 AI-аптымізацыя Wi-Fi** — аналіз эфіру праз DeepSeek / OpenRouter
- **🔒 VPN** — WireGuard, AmneziaWG, OpenVPN, SSTP, PPTP, L2TP/IPsec і IKEv2/IPsec
- **🛡 Бяспека** — файрвол, перанакіраванне партоў, VLAN, блакіроўка кліентаў і Wake-on-LAN
- **👥 Кліенты** — DHCP-спіс, ідэнтыфікацыя прылад і маніторынг злучэнняў
- **🌐 DNS** — DNS, DoH, DoT, AdGuard Home і DDNS
- **🖥 Сістэма** — SSH-тэрмінал, абнаўленні, логі, рэзервовыя копіі і USB-прылады
- **📦 Пакетны менеджар** — OPKG і APK
- **✅ Сумяшчальнасць** — OpenWRT, ImmortalWrt, FriendlyWrt і LEDE версій 19.07–24.10

---
## Версия 4.1.0

- Полностью переделан модуль измерения скорости.
- Файловый диспетчер USB|SSD.
- Тестирование безопасности вашей WIFI точки.
- Синхронизация времени с вашего Android устройства на Роутер.

## Версия 4.0.3

- Добавлен выбор языка: русский, украинский, казахский и белорусский.
- Выбранный язык сохраняется между запусками приложения.
- Переведены все экраны, основные диалоги, кнопки, уведомления и статусы.
- Исправлены зависимости локализации Flutter и обновлена версия APK.

## Сборка / Build

```bash
cd source
flutter pub get
flutter build apk --release
```

## Ссылки / Links

| Ресурс | Ссылка |
|--------|--------|
| 🌐 Сайт приложения | [rybinsklab.ru/openwrt](https://rybinsklab.ru/openwrt/) |
| 📱 4PDA | [4pda.to/forum](https://4pda.to/forum/index.php?showtopic=911457&view=findpost&p=144455263) |
| 📦 GitHub Releases | [github.com/gotical/OpenWRT_Global/releases](https://github.com/gotical/OpenWRT_Global/releases) |

## Лицензия / License

[MIT](LICENSE) — разрешено использовать, модифицировать и распространять код при условии указания автора **Усачёв Денис (РыбинскLAB.ru)** и ссылки на репозиторий **https://github.com/USAchevIP/OpenWRT_Global**.
