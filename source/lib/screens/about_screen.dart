import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../main.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
     ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${AppStrings.of(context).text('Скопировано:')} $text')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AppStrings.of(context);
    final currentLanguage = Localizations.localeOf(context).languageCode;
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar.large(title: Text(strings.about)),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Center(
                  child: Hero(
                    tag: 'app_icon',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'assets/icon/router_icon.png',
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text(
                    'OPENWRT - Global',
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                   child: Text(
                     '${strings.version} 4.0.8',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                 ),
                 const SizedBox(height: 32),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.language),
                    title: Text(strings.language),
                    trailing: DropdownButton<String>(
                      value: currentLanguage,
                      underline: const SizedBox.shrink(),
                      items: AppStrings.languageNames.entries
                          .map((entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ))
                          .toList(),
                      onChanged: (code) {
                        if (code != null) {
                          OpenWrtManagerApp.of(context)?.setLocale(Locale(code));
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.palette_outlined),
                    title: Text(strings.text('Тема')),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SegmentedButton<ThemeMode>(
                        segments: [
                          ButtonSegment(value: ThemeMode.system, label: Text(strings.text('Системная')), icon: const Icon(Icons.brightness_auto, size: 16)),
                          ButtonSegment(value: ThemeMode.light, label: Text(strings.text('Светлая')), icon: const Icon(Icons.light_mode, size: 16)),
                          ButtonSegment(value: ThemeMode.dark, label: Text(strings.text('Тёмная')), icon: const Icon(Icons.dark_mode, size: 16)),
                        ],
                        selected: {OpenWrtManagerApp.of(context)?.currentThemeMode ?? ThemeMode.system},
                        onSelectionChanged: (sel) {
                          OpenWrtManagerApp.of(context)?.setThemeMode(sel.first);
                        },
                        showSelectedIcon: false,
                      ),
                    ),
                    isThreeLine: true,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.business),
                         title: Text(strings.developer),
                          subtitle: Text(strings.text('РыбинскLAB')),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _openUrl('https://rybinsklab.ru'),
                        ),
                        onTap: () => _openUrl('https://rybinsklab.ru'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.person),
                         title: Text(strings.text('Автор проекта')),
                          subtitle: Text(strings.text('Усачёв Денис')),
                        onTap: () => _copy(context, 'Усачёв Денис'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.link),
                         title: Text(strings.sourceCode),
                        subtitle: const Text('github.com/USAchevIP/OpenWRT_Global'),
                        trailing: const Icon(Icons.open_in_new),
                        onTap: () => _openUrl('https://github.com/USAchevIP/OpenWRT_Global'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Text(strings.features, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                         Text(
                           strings.text('• Дашборд с CPU/RAM/uptime и графиками\n'
                          '• Мониторинг клиентов с трафиком, блокировка, лимиты\n'
                          '• Управление Wi-Fi: каналы, ширина, карта помех, AI-оптимизация\n'
                          '• Анализатор каналов (роутер + телефон с учётом ширины)\n'
                          '• Speedtest (iperf3 / curl / wget) с автоопределением\n'
                          '• Терминал (Beta) — интерактивный SSH shell\n'
                          '• MAC Changer — смена MAC адреса интерфейсов\n'
                          '• WPS Audit — проверка уязвимостей WPS\n'
                          '• WireGuard / AmneziaWG / OpenVPN с импортом .conf\n'
                          '• VPN с взаимным исключением и проверкой IP\n'
                          '• DNS: обычный, DoT, DoH\n'
                          '• Обновление прошивки OpenWRT через auc\n'
                          '• Топология сети, статические IP, ограничения скорости\n'
                          '• Проверка зависимостей с автоустановкой\n'
                           '• Поддержка OpenWrt 24.10.3 / 24.10.8 / 25.12.5'),
                           style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber, color: theme.colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            strings.text('Важно: из-за изменений шифрования и защиты настроек SSH, после обновления до этой версии возможно потребуется удалить и заново добавить роутер в приложении.'),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         Text(strings.acknowledgements, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                         Text(
                           strings.text('Начиная с версии 3.9.0 в приложении используется код, изученный '
                          'из проектов openwrt-router-control (github.com/Vihtoor/openwrt-router-control) '
                           'и StrykerOSS (github.com/zalexdev/strykerapp).'),
                           style: const TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                         Text(
                           strings.text('Благодаря этому были улучшены:\n'
                          '• Анализатор каналов с учётом ширины (20/40/80/160 MHz)\n'
                          '• Измерение скорости (iperf3 + curl + wget)\n'
                          '• Терминал (Beta) — интерактивный SSH\n'
                          '• Включение/выключение VPN с взаимным исключением\n'
                          '• MAC Changer — смена MAC адреса\n'
                          '• WPS Audit — проверка уязвимостей\n'
                          '• OS Fingerprinting — определение устройств по портам\n'
                           '• Nmap Profiles — пресеты для сканирования'),
                           style: const TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _openUrl('https://github.com/Vihtoor/openwrt-router-control'),
                          icon: const Icon(Icons.open_in_new, size: 18),
                           label: Text(strings.text('Источник кода openwrt-router-control')),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openUrl('https://github.com/zalexdev/strykerapp'),
                          icon: const Icon(Icons.open_in_new, size: 18),
                           label: Text(strings.text('Исходный код StrykerOSS')),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    '© 2026 РыбинскLAB\nУсачёв Денис',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
