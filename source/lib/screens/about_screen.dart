import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скопировано: $text')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar.large(title: const Text('О приложении')),
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
                    'Версия 4.0.1',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 32),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.business),
                        title: const Text('Разработчик'),
                        subtitle: const Text('РыбинскLAB'),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new),
                          onPressed: () => _openUrl('https://rybinsklab.ru'),
                        ),
                        onTap: () => _openUrl('https://rybinsklab.ru'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: const Text('Автор проекта'),
                        subtitle: const Text('Усачёв Денис'),
                        onTap: () => _copy(context, 'Усачёв Денис'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: const Text('Исходный код'),
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
                        Text('Возможности', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                          '• Дашборд с CPU/RAM/uptime и графиками\n'
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
                          '• Поддержка OpenWrt 24.10.3 / 24.10.8 / 25.12.5',
                          style: TextStyle(fontSize: 13),
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
                        Text('Благодарности', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        const Text(
                          'Начиная с версии 3.9.0 в приложении используется код, изученный '
                          'из проектов openwrt-router-control (github.com/Vihtoor/openwrt-router-control) '
                          'и StrykerOSS (github.com/zalexdev/strykerapp).',
                          style: TextStyle(fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Благодаря этому были улучшены:\n'
                          '• Анализатор каналов с учётом ширины (20/40/80/160 MHz)\n'
                          '• Измерение скорости (iperf3 + curl + wget)\n'
                          '• Терминал (Beta) — интерактивный SSH\n'
                          '• Включение/выключение VPN с взаимным исключением\n'
                          '• MAC Changer — смена MAC адреса\n'
                          '• WPS Audit — проверка уязвимостей\n'
                          '• OS Fingerprinting — определение устройств по портам\n'
                          '• Nmap Profiles — пресеты для сканирования',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => _openUrl('https://github.com/Vihtoor/openwrt-router-control'),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Исходный код openwrt-router-control'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => _openUrl('https://github.com/zalexdev/strykerapp'),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('Исходный код StrykerOSS'),
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