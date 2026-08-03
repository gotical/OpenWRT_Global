import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/network_info.dart';
import '../services/openwrt_service.dart';
import '../services/storage_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/device_security.dart';
import '../services/ai_analysis_service.dart';
import 'about_screen.dart';
import 'login_screen.dart';
import 'usb_browser_screen.dart';

class SystemScreen extends StatefulWidget {
  final OpenWrtService service;

  const SystemScreen({super.key, required this.service});

  @override
  State<SystemScreen> createState() => _SystemScreenState();
}

class _SystemScreenState extends State<SystemScreen> {
  Map<String, dynamic>? boardInfo;
  bool loading = true;
  String? error;
  bool hideNonFunctional = false;

  bool _depMissing(String dep) {
    final st = OpenWrtService.lastDepsStatus;
    return st.isNotEmpty && (st[dep] ?? true) == false;
  }

  bool _showCard(String dep) => !hideNonFunctional || !_depMissing(dep);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    hideNonFunctional = await StorageService.isHideNonFunctionalSections();
    try {
      if (!widget.service.isConnected) await widget.service.connect();
      Map<String, dynamic>? data;
      try {
        data = await widget.service.fetchBoardInfo();
      } catch (_) {
        data = null;
      }
      if (!mounted) return;
      setState(() {
        boardInfo = data;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> _reboot() async {
    final ok = await _confirm('Перезагрузить роутер?', 'Устройство будет перезагружено.');
    if (ok != true) return;
    try {
      await widget.service.reboot();
      if (!mounted) return;
      _snack('Команда перезагрузки отправлена');
    } catch (e) {
      if (!mounted) return;
      _snack('Ошибка: $e');
    }
  }

  Future<void> _syncTime() async {
    _showProgress('Синхронизация времени...');
    try {
      final result = await widget.service.syncTime();
      if (!mounted) return;
      Navigator.pop(context);
      _snack(result);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Ошибка: $e');
    }
  }

  Future<void> _generateSshKey() async {
    _showProgress('Генерация SSH-ключа...');
    try {
      final keys = await widget.service.generateAndInstallKey();
      if (!mounted) return;
      Navigator.pop(context);
      final priv = keys['private'] ?? '';
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [Icon(Icons.vpn_key, color: Colors.green), SizedBox(width: 8), Text('SSH-ключ создан')]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Приватный ключ (сохраните его):', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(priv, style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
              ),
              const SizedBox(height: 12),
              const Text('Теперь вы можете войти по ключу, скопируйте приватный ключ и добавьте роутер с типом "SSH-ключ".'),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      _snack('SSH-ключ установлен на роутер');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Ошибка: $e');
    }
  }

  Future<void> _serviceAction(String name) async {
    final ok = await _confirm('Перезапустить $name?', 'Служба будет перезапущена.');
    if (ok != true) return;
    _showProgress('Перезапуск $name...');
    try {
      await widget.service.restartService(name);
      if (!mounted) return;
      Navigator.pop(context);
      _snack('$name перезапущен');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Ошибка: $e');
    }
  }

  Future<void> _showLogs() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Загрузка логов...')]),
      ),
    );
    List<String> logs = [];
    try {
      logs = await widget.service.fetchLogs(lines: 80);
    } catch (e) {
      logs = ['Ошибка загрузки логов: $e'];
    }
    if (!mounted) return;
    Navigator.pop(context);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.85,
        initialChildSize: 0.7,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Системные логи', style: Theme.of(ctx).textTheme.titleLarge),
                  Row(children: [
                    IconButton(
                      onPressed: () => _aiAnalyzeLogs(ctx, logs),
                      tooltip: 'AI анализ',
                      icon: const Icon(Icons.smart_toy),
                    ),
                    IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                  ]),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: sc,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: logs.length,
                itemBuilder: (_, i) => SelectableText(
                  logs[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _aiAnalyzeLogs(BuildContext ctx, List<String> logs) async {
    await AiAnalysisService.init();
    final key = await StorageService.loadApiKey(await StorageService.loadActiveAiProvider() ?? 'deepseek');
    if (key == null || key.isEmpty) {
      _snack('Настройте API-ключ в «AI-ассистент»');
      return;
    }
    final logText = logs.take(60).join('\n');
    await showDialog(
      context: ctx,
      builder: (dctx) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('AI анализ логов...')]),
      ),
    );
    final result = await AiAnalysisService.analyzeLog(logText);
    if (!mounted) return;
    Navigator.pop(ctx);
    await showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('AI анализ логов'),
        content: SingleChildScrollView(child: Text(result ?? 'Нет ответа от AI', style: const TextStyle(fontSize: 13))),
        actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Закрыть'))],
      ),
    );
  }

  Future<void> _showTerminalCommand() async {
    final ctrl = TextEditingController();
    String? output;
    bool running = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: const Text('Выполнить команду'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(hintText: 'Например: uci show network'),
                  ),
                  if (output != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(output!, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      ),
                    ),
                  ],
                  if (running) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
              FilledButton(
                onPressed: running ? null : () async {
                  setSt(() { running = true; output = null; });
                  try {
                    final res = await widget.service.runCommand(ctrl.text.trim());
                    setSt(() { output = res; running = false; });
                  } catch (e) {
                    setSt(() { output = 'Ошибка: $e'; running = false; });
                  }
                },
                child: const Text('Выполнить'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<bool?> _confirm(String title, String content) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Подтвердить')),
          ],
        ),
      );

  Future<void> _checkFirmware() async {
    _showProgress('Проверка обновлений...');
    try {
      final result = await widget.service.checkFirmwareUpdate();
      if (!mounted) return;
      Navigator.pop(context);

      if (result == null || result.contains('Нет')) {
        _snack('Обновлений не найдено');
        return;
      }

      final resultText = result;
      final upgrading = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Доступно обновление'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(resultText.length > 100 ? '${resultText.substring(0, 100)}...' : resultText),
            const SizedBox(height: 16),
            const Text('Загрузить и установить обновление? Роутер будет перезагружен.', style: TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Обновить')),
          ],
        ),
      );

      if (upgrading == true) {
        _showUpgradeProgress();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Ошибка проверки: $e');
    }
  }

  void _showUpgradeProgress() {
    String status = 'Готовимся...';
    StateSetter? setter;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          setter = setSt;
          return AlertDialog(
            title: const Text('Обновление прошивки'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(status),
            ]),
            actions: [
              if (status.contains('перезагружается') || status.contains('ошибк'))
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          );
        },
      ),
    );
    widget.service.upgradeFirmware((s) {
      status = switch (s) {
        'checking' => 'Проверка auc...',
        'installing_auc' => 'Установка auc...',
        'downloading' => 'Загрузка прошивки...',
        'rebooting' => 'Роутер перезагружается...',
        _ => s,
      };
      setter?.call(() {});
    });
  }

  Future<void> _setupAiKey() async {
    final currentProvider = await StorageService.loadActiveAiProvider() ?? 'deepseek';
    final ctrl = TextEditingController();
    final existing = currentProvider == 'deepseek'
        ? (await StorageService.loadApiKey('deepseek') ?? '')
        : (await StorageService.loadApiKey('openrouter') ?? '');
    ctrl.text = existing;

    String provider = currentProvider;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: const Text('AI-ассистент'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Выберите провайдера AI для автооптимизации WiFi:'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: provider,
                items: const [
                  DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek')),
                  DropdownMenuItem(value: 'openrouter', child: Text('OpenRouter')),
                ],
                onChanged: (v) async {
                  setSt(() => provider = v!);
                  ctrl.text = await StorageService.loadApiKey(v!) ?? '';
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  labelText: provider == 'openrouter' ? 'OpenRouter API Key' : 'DeepSeek API Key',
                  hintText: provider == 'deepseek' ? 'sk-...' : 'sk-or-v1-...',
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            FilledButton(onPressed: () async {
              await StorageService.saveApiKey(provider, ctrl.text.trim());
              await StorageService.saveActiveAiProvider(provider);
              if (!mounted) return;
              Navigator.pop(ctx);
              _snack('Ключ $provider сохранён');
            }, child: const Text('Сохранить')),
          ],
        ),
      ),
    );
  }

  Future<void> _showAiAnalysis() async {
    await AiAnalysisService.init();
    if (await StorageService.loadApiKey(await StorageService.loadActiveAiProvider() ?? 'deepseek') == null) {
      _snack('Сначала настройте API-ключ в «AI-ассистент»');
      _setupAiKey();
      return;
    }
    _showProgress('AI анализ...');
    try {
      final sysInfo = await widget.service.fetchSystemInfo();
      final caps = await widget.service.detectCapabilities();
      final aiContext = 'OpenWrt ${caps.version}, ${caps.target}\n'
          'RAM: ${sysInfo.memoryUsed}/${sysInfo.memoryTotal} MB\n'
          'CPU load: ${sysInfo.cpuLoad}\n'
          'Uptime: ${sysInfo.uptime}';
      final result = await AiAnalysisService.getRecommendations(aiContext);
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(children: [Icon(Icons.smart_toy), SizedBox(width: 8), Text('AI рекомендации')]),
          content: SingleChildScrollView(child: Text(result ?? 'Нет ответа от AI', style: const TextStyle(fontSize: 14))),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
        ),
      );
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('Ошибка: $e'); }
    }
  }

  Future<void> _showBackupDialog() async {
    final pwdCtrl = TextEditingController();
    final dataCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Бэкап конфигурации'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Экспорт или импорт конфигураций роутеров с AES-256 шифрованием.'),
            const SizedBox(height: 12),
            TextField(
              controller: pwdCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль шифрования'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dataCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Данные (для импорта)'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () async {
            if (pwdCtrl.text.isEmpty) return;
            final routers = await StorageService.loadRouters();
            final data = routers.map((r) => r.toJson()).toList();
            final encrypted = BackupService.exportToJson({'routers': data, 'version': '4.0.1'}, pwdCtrl.text);
            await showDialog(
              context: ctx,
              builder: (ctx) => AlertDialog(
                title: const Text('QR-код резервной копии'),
                content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text('Отсканируйте QR для импорта на другое устройство'),
                    const SizedBox(height: 12),
                    QrImageView(data: encrypted, size: 200),
                    const SizedBox(height: 12),
                    SelectableText(encrypted, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: encrypted));
                    if (ctx.mounted) _snack('Скопировано в буфер');
                  }, child: const Text('Копировать')),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
                ],
              ),
            );
          }, child: const Text('Экспорт QR')),
          TextButton(onPressed: () async {
            if (pwdCtrl.text.isEmpty || dataCtrl.text.isEmpty) return;
            try {
              final decrypted = BackupService.importFromJson(dataCtrl.text, pwdCtrl.text);
              if (decrypted['routers'] is List) {
                _snack('Импорт успешен: ${(decrypted['routers'] as List).length} конфигураций');
              }
            } catch (e) {
              _snack('Ошибка импорта: неверный пароль или данные');
            }
          }, child: const Text('Импорт')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _setupNotifications() async {
    final enabled = await StorageService.isNotificationsEnabled();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Уведомления'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Получать уведомления о состоянии роутера:'),
          const SizedBox(height: 12),
          const Text('• Высокая температура CPU'),
          const Text('• Высокая загрузка CPU / RAM'),
          const Text('• Потеря WAN подключения'),
          const Text('• Отключение VPN'),
          const Text('• Доступны обновления прошивки'),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text('Включить уведомления'),
            value: enabled,
            onChanged: (v) async {
              await StorageService.setNotificationsEnabled(v);
              if (v) await NotificationService.init();
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
        ],
      ),
    );
  }

  Future<void> _showSecurityStatus() async {
    final root = await DeviceSecurity.isRooted();
    final emu = await DeviceSecurity.isEmulator();
    final debug = await DeviceSecurity.isDebug();
    final proxy = await DeviceSecurity.isProxySet();
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [Icon(Icons.security), SizedBox(width: 8), Text('Безопасность')]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _secRow('Root доступ', root),
          const SizedBox(height: 8),
          _secRow('Эмулятор', emu),
          const SizedBox(height: 8),
          _secRow('Режим отладки', debug),
          const SizedBox(height: 8),
          _secRow('HTTP Proxy', proxy),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
      ),
    );
  }

  Widget _secRow(String label, bool detected) {
    return Row(children: [
      Icon(detected ? Icons.warning_amber : Icons.check_circle, color: detected ? Colors.red : Colors.green, size: 20),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(fontSize: 16)),
      const Spacer(),
      Text(detected ? 'ОБНАРУЖЕНО' : 'Не обнаружено', style: TextStyle(color: detected ? Colors.red : Colors.green, fontWeight: FontWeight.w600)),
    ]);
  }

  Future<void> _showDnsDialog() async {
    try {
      final currentDnsRaw = await widget.service.fetchDnsSettings();
      if (!mounted) return;
      final dns1 = TextEditingController(), dns2 = TextEditingController();
      String dnsType = 'default';

      final currentServers = <String>[];
      final re = RegExp(r"server='([^']+)'");
      for (final m in re.allMatches(currentDnsRaw)) { currentServers.add(m.group(1)!); }
      if (currentServers.isNotEmpty) dns1.text = currentServers[0];
      if (currentServers.length > 1) dns2.text = currentServers[1];

      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            title: const Text('Настройка DNS'),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                  initialValue: dnsType,
                  decoration: const InputDecoration(labelText: 'Тип DNS'),
                  items: const [
                    DropdownMenuItem(value: 'default', child: Text('Обычный (UDP:53)')),
                    DropdownMenuItem(value: 'dot', child: Text('DNS-over-TLS')),
                    DropdownMenuItem(value: 'doh', child: Text('DNS-over-HTTPS')),
                  ],
                  onChanged: (v) => setSt(() { dnsType = v ?? 'default'; dns1.clear(); dns2.clear(); }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dns1,
                  decoration: InputDecoration(
                    labelText: dnsType == 'doh' ? 'DoH URL' : dnsType == 'dot' ? 'DoT домен' : 'Основной DNS',
                    hintText: dnsType == 'doh' ? 'https://dns.adguard.com/dns-query' : dnsType == 'dot' ? 'dns.adguard.com' : '1.1.1.1',
                    prefixIcon: const Icon(Icons.dns),
                  ),
                ),
                if (dnsType == 'default') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: dns2,
                    decoration: const InputDecoration(labelText: 'Резервный DNS', hintText: '8.8.8.8', prefixIcon: Icon(Icons.dns_outlined)),
                  ),
                ],
                if (dnsType == 'dot') ...[
                  const SizedBox(height: 8),
                  Text('Формат: домен без https://\nПорт 853 добавляется автоматически', style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ],
                if (dnsType == 'doh') ...[
                  const SizedBox(height: 8),
                  Text('Формат: https://dns.server/dns-query', style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ],
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
              FilledButton(onPressed: () async {
                Navigator.pop(ctx);
                final primary = dns1.text.trim();
                final secondary = dns2.text.trim();
                if (primary.isEmpty) return;
                final servers = <String>[primary];
                if (secondary.isNotEmpty && dnsType == 'default') servers.add(secondary);
                await widget.service.setDns(servers);
                if (mounted) _snack('DNS обновлён: $primary');
              }, child: const Text('Сохранить')),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) _snack('Ошибка DNS: $e');
    }
  }
  Future<void> _remoteAccessDialog() async {
    _showProgress('Проверка...');
    try {
      final status = await widget.service.remoteAccessStatus();
      if (!mounted) return;
      Navigator.pop(context);
      final wanIp = status['wan_ip'] ?? '?';
      final srcPort = status['src_port'];
      final enabled = status['enabled'] != '0';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Удалённый доступ'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [const Text('WAN IP:'), const SizedBox(width: 8), SelectableText(wanIp, style: const TextStyle(fontWeight: FontWeight.w700))]),
              const SizedBox(height: 12),
              if (srcPort != null && srcPort.isNotEmpty && enabled) ...[
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Доступ открыт', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.green)),
                    const SizedBox(height: 4),
                    SelectableText('ssh root@$wanIp -p $srcPort', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                    const SizedBox(height: 8),
                    Text('В приложении: добавьте роутер\nс IP $wanIp и портом $srcPort'),
                  ])),
                OutlinedButton.icon(onPressed: () async { Navigator.pop(ctx); await widget.service.disableRemoteAccess(); if (mounted) _snack('Удалённый доступ закрыт'); }, icon: const Icon(Icons.lock), label: const Text('Закрыть доступ')),
              ] else ...[
                const Text('Доступ закрыт. Открыть порт для SSH?', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Будет создан проброс порта 22022 → 22.\nИспользуйте сложный пароль root!', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                FilledButton.icon(onPressed: () async { Navigator.pop(ctx); await widget.service.enableRemoteAccess(); if (mounted) _snack('Доступ открыт на порт 22022'); }, icon: const Icon(Icons.lock_open), label: const Text('Открыть доступ (порт 22022)')),
              ],
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
        ),
      );
    } catch (e) { if (mounted) { Navigator.pop(context); _snack('$e'); } }
  }

  Future<void> _showPortForwards() async {
    _showProgress('Загрузка...');
    List<Map<String, String>> rules = [];
    String? err;
    try {
      rules = await widget.service.fetchPortForwards();
    } catch (e) {
      err = '$e';
    }
    if (!mounted) return;
    Navigator.pop(context);
    if (err != null) { _snack('$err'); return; }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        maxChildSize: 0.9,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        builder: (_, sc) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              child: Row(
                children: [
                  const Icon(Icons.router, size: 20),
                  const SizedBox(width: 8),
                  Text('Проброс портов (${rules.length})', style: Theme.of(ctx).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(onPressed: () { Navigator.pop(ctx); _addPortForward(); }, icon: const Icon(Icons.add_circle_outline), tooltip: 'Добавить'),
                ],
              ),
            ),
            Expanded(
              child: rules.isEmpty
                  ? const Center(child: Text('Нет правил'))
                  : ListView.builder(
                      controller: sc,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: rules.length,
                      itemBuilder: (_, i) {
                        final r = rules[i];
                        final enabled = (r['enabled'] ?? '1') != '0';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                enabled ? Icons.check_circle : Icons.cancel,
                                color: enabled ? Colors.green : Theme.of(ctx).colorScheme.outline,
                              ),
                              title: Text(r['name'] ?? '-',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: enabled ? null : Theme.of(ctx).colorScheme.onSurfaceVariant,
                                  decoration: enabled ? null : TextDecoration.lineThrough,
                                )),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('WAN:${r['dport']} → ${r['ip']}:${r['dp']} (${r['proto']})'),
                                  Text('target: ${r['target']} • src: ${r['src']}', style: Theme.of(ctx).textTheme.bodySmall),
                                ],
                              ),
                              trailing: Wrap(spacing: 0, children: [
                                IconButton(
                                  icon: Icon(enabled ? Icons.toggle_on : Icons.toggle_off, color: enabled ? Colors.green : Colors.grey),
                                  tooltip: enabled ? 'Отключить' : 'Включить',
                                  onPressed: () async {
                                    await widget.service.updatePortForward(
                                      section: r['section']!,
                                      name: r['name'] ?? '-',
                                      srcDport: r['dport'] ?? '-',
                                      destIp: r['ip'] ?? '-',
                                      destPort: r['dp'] ?? '-',
                                      proto: r['proto'] ?? 'tcp',
                                      enabled: !enabled,
                                    );
                                    if (mounted) { Navigator.pop(ctx); _showPortForwards(); }
                                  },
                                ),
                                IconButton(icon: const Icon(Icons.edit, size: 20), tooltip: 'Редактировать',
                                  onPressed: () { Navigator.pop(ctx); _editPortForward(r); }),
                                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), tooltip: 'Удалить',
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: ctx,
                                      builder: (d) => AlertDialog(
                                        title: const Text('Удалить правило?'),
                                        content: Text('${r['name'] ?? r['section']}'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Отмена')),
                                          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Удалить')),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    await widget.service.deletePortForward(r['section']!);
                                    if (mounted) { Navigator.pop(ctx); _showPortForwards(); }
                                  }),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPortForward() async {
    final values = await _portForwardDialog(null);
    if (values == null) return;
    await widget.service.addPortForward(
      name: values['name']!,
      srcDport: values['dport']!,
      destIp: values['ip']!,
      destPort: values['dp']!,
      proto: values['proto']!,
    );
    if (mounted) _snack('Правило добавлено');
  }

  Future<void> _editPortForward(Map<String, String> rule) async {
    final values = await _portForwardDialog(rule);
    if (values == null) return;
    await widget.service.updatePortForward(
      section: rule['section']!,
      name: values['name']!,
      srcDport: values['dport']!,
      destIp: values['ip']!,
      destPort: values['dp']!,
      proto: values['proto']!,
      enabled: values['enabled'] == '1',
    );
    if (mounted) _snack('Правило обновлено');
  }

  Future<Map<String, String>?> _portForwardDialog(Map<String, String>? existing) async {
    final name = TextEditingController(text: existing?['name'] == '-' ? '' : (existing?['name'] ?? ''));
    final port = TextEditingController(text: existing?['dport'] == '-' ? '' : (existing?['dport'] ?? ''));
    final ip = TextEditingController(text: existing?['ip'] == '-' ? '' : (existing?['ip'] ?? ''));
    final dport = TextEditingController(text: existing?['dp'] == '-' ? '' : (existing?['dp'] ?? ''));
    String proto = existing?['proto'] ?? 'tcp';
    bool enabled = (existing?['enabled'] ?? '1') != '0';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text(existing == null ? 'Новое правило' : 'Изменить правило'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: proto,
                items: const [
                  DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                  DropdownMenuItem(value: 'udp', child: Text('UDP')),
                  DropdownMenuItem(value: 'tcp udp', child: Text('Оба')),
                ],
                onChanged: (v) => setSt(() => proto = v!),
              ),
              TextField(controller: port, decoration: const InputDecoration(labelText: 'Внешний порт (WAN)'), keyboardType: TextInputType.number),
              TextField(controller: ip, decoration: const InputDecoration(labelText: 'Локальный IP'), keyboardType: TextInputType.number),
              TextField(controller: dport, decoration: const InputDecoration(labelText: 'Локальный порт'), keyboardType: TextInputType.number),
              SwitchListTile(
                value: enabled,
                onChanged: (v) => setSt(() => enabled = v),
                title: const Text('Правило включено'),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(existing == null ? 'Добавить' : 'Сохранить'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return null;
    return {
      'name': name.text.trim().isEmpty ? 'redirect_${DateTime.now().millisecondsSinceEpoch}' : name.text.trim(),
      'proto': proto,
      'dport': port.text.trim(),
      'ip': ip.text.trim(),
      'dp': dport.text.trim(),
      'enabled': enabled ? '1' : '0',
    };
  }

  Future<void> _showWolDialog() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Wake-on-LAN'), content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'MAC-адрес')), actions: [
      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Разбудить')),
    ]));
    if (ok == true && ctrl.text.isNotEmpty) {
      await widget.service.wakeOnLan(ctrl.text);
      if (mounted) _snack('Magic packet отправлен');
    }
  }

  Future<void> _showWifiSchedule() async {
    final nets = await widget.service.fetchWifiNetworks();
    if (nets.isEmpty) { _snack('Wi-Fi сети не найдены'); return; }
    String? section;
    await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Выберите сеть'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: nets.map((n) => ListTile(title: Text(n.ssid), onTap: () { section = n.section; Navigator.pop(ctx); })).toList())),
    ));
    if (section == null) return;
    final start = TimeOfDay(hour: 1, minute: 0), stop = TimeOfDay(hour: 7, minute: 0);
    final s = await showTimePicker(context: context, initialTime: start);
    if (s == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: stop);
    if (t == null || !mounted) return;
    await widget.service.scheduleWifi(section!, start: '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}', stop: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
    if (mounted) _snack('Расписание сохранено');
  }

  Future<void> _checkTemperature() async {
    _showProgress('Проверка...');
    final t = await widget.service.fetchTemperature();
    if (!mounted) return;
    Navigator.pop(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Температура'), content: Text(t), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
  }

  Future<void> _showUsbDevices() async {
    _showProgress('Сканирование...');
    final devs = await widget.service.fetchUsbDevices();
    if (!mounted) return;
    Navigator.pop(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('USB-устройства'),
      content: SizedBox(width: double.maxFinite, child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: devs.isEmpty
          ? [const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('USB-устройств не найдено'))]
          : devs.map((d) => _UsbTile(d: d, onBrowse: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => UsbBrowserScreen(
                service: widget.service,
                startPath: d['mount']!,
              )));
            })).toList()),
      )),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  Future<void> _runNmapScan() async {
    _showProgress('Сканирование сети (nmap)...');
    try {
      final devs = await widget.service.runNmapScan();
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: Text('Устройства (${devs.length})'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: devs.length, itemBuilder: (_, i) => ListTile(title: Text(devs[i]['ip']!), subtitle: Text('${devs[i]['mac']} ${devs[i]['vendor']}')))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ));
    } catch (e) { if (mounted) { Navigator.pop(context); _snack('nmap не установлен? $e'); } }
  }

  Future<void> _checkAdGuard() async {
    _showProgress('Проверка AdGuard...');
    final status = await widget.service.fetchAdGuardStatus();
    if (!mounted) return;
    Navigator.pop(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('AdGuard Home'), content: Text(status == 'NOT_RUNNING' ? 'Не запущен. Установите AdGuard Home.' : status == 'true' ? 'Блокировка включена' : 'Блокировка выключена'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  Future<void> _showDdnsStatus() async {
    _showProgress('Проверка DDNS...');
    final status = await widget.service.fetchDdnsStatus();
    if (!mounted) return;
    Navigator.pop(context);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('DDNS'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: status.isEmpty ? [const Text('Не настроен')] : status.map((s) => ListTile(title: Text(s['name']!), subtitle: Text(s['domain']!))).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ));
  }

  Future<void> _offerReboot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Перезагрузить роутер?'),
        content: const Text('Некоторые пакеты требуют перезагрузки для активации.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Позже')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Перезагрузить')),
        ],
      ),
    );
    if (ok == true) {
      await widget.service.reboot();
      if (mounted) _snack('Команда перезагрузки отправлена');
    }
  }

  Future<void> _showDepsMenu() async {
    final host = widget.service.config.host;
    final alreadyChecked = await StorageService.wasDepsChecked(host);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Зависимости', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Проверить и установить'),
            subtitle: const Text('Проверить наличие пакетов на роутере'),
            onTap: () { Navigator.pop(ctx); _checkDependencies(); },
          ),
          ListTile(
            leading: Icon(alreadyChecked ? Icons.check_circle : Icons.cancel),
            title: const Text('Сбросить статус проверки'),
            subtitle: Text(alreadyChecked ? 'Сейчас: не проверять автоматически' : 'Сейчас: проверять при входе'),
            onTap: () async {
              if (alreadyChecked) {
                await StorageService.resetDepsChecked(host);
              } else {
                await StorageService.markDepsChecked(host);
              }
              Navigator.pop(ctx);
              _snack(alreadyChecked ? 'Проверка будет показана при следующем входе' : 'Автопроверка отключена');
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _checkDependencies() async {
    _showProgress('Проверка...');
    try {
      final pkg = await widget.service.detectPackageManager();
      final deps = await widget.service.checkDependencies();
      if (!mounted) return;
      Navigator.pop(context);

      _showDepsListDialog(pkg, deps);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('Ошибка: $e');
    }
  }

  void _showDepsListDialog(String pkg, Map<String, bool> deps) {
    final isStock = (String k) => k == 'ubus' || k == 'uci' || k == 'jsonfilter' || k == 'dnsmasq';
    final entries = deps.entries.where((e) => !isStock(e.key)).toList();
    final missingCount = entries.where((e) => !e.value).length;
    final status = <String, String>{};
    var installing = false;
    String? msg;
    int done = 0, total = 0;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          return AlertDialog(
            title: Row(children: [const Icon(Icons.checklist), const SizedBox(width: 8), Text('$pkg — ${entries.where((e) => e.value).length}/${entries.length}')]),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ...entries.map((e) {
                  final ok = status[e.key] == 'done' || (status[e.key] != 'error' && e.value);
                  final failed = status[e.key] == 'error';
                  final loading = status[e.key] == 'downloading';
                  final pn = OpenWrtService.packageForDependency[e.key];
                  final alts = OpenWrtService.packageAlternatives[e.key];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      if (loading)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        Icon(ok && !failed ? Icons.check_circle : Icons.cancel, size: 20, color: ok && !failed ? Colors.green : Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.key, style: const TextStyle(fontSize: 14)),
                            if (!e.value && pn != null)
                              Text(
                                alts != null ? '$pn (${alts.join(', ')})' : pn,
                                style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                              ),
                          ],
                        ),
                      ),
                    ]),
                  );
                }),
                if (installing) ...[const SizedBox(height: 12), LinearProgressIndicator(value: total > 0 ? done / total : null)],
                if (msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg!)),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
              if (missingCount > 0)
                FilledButton(
                  onPressed: installing ? null : () async {
                    final toInstall = entries.where((e) => !e.value && !isStock(e.key) && e.key != 'wget/uclient').toList();
                    total = toInstall.length; done = 0;
                    setSt(() => installing = true);
                    for (final e in toInstall) {
                      final primary = OpenWrtService.packageForDependency[e.key];
                      if (primary == null) continue;
                      setSt(() { status[e.key] = 'downloading'; msg = 'Загрузка $primary...'; });
                      try {
                        await widget.service.installPackages([primary]);
                        setSt(() { status[e.key] = 'done'; done++; msg = 'Готово $primary'; });
                      } catch (_) {
                        try {
                          final alt = await widget.service.findAlternativePackage(e.key);
                          if (alt != null && alt != primary) {
                            await widget.service.installPackages([alt]);
                            setSt(() { status[e.key] = 'done'; done++; msg = 'Готово $alt (альтернатива)'; });
                          } else {
                            rethrow;
                          }
                        } catch (_) {
                          setSt(() { status[e.key] = 'error'; done++; msg = 'Ошибка $primary'; });
                        }
                      }
                      await Future.delayed(const Duration(milliseconds: 400));
                    }
                    setSt(() { installing = false; msg = 'Установлено $done/${total}'; });
                    await StorageService.markDepsChecked(widget.service.config.host);
                    await Future.delayed(const Duration(seconds: 1));
                    _offerReboot();
                  },
                  child: const Text('Установить всё'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _showProgress(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Expanded(child: Text(message))]),
      ),
    );
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar.large(
              title: const Text('Система'),
              actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
            ),
            if (loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (error != null)
              _buildError(theme)
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (boardInfo != null) _buildInfoCard(theme),
                    if (_showCard('auc'))
                      _ActionCard(
                        icon: Icons.system_update,
                        title: 'Проверить обновление прошивки',
                        subtitle: 'Attended SysUpgrade (auc)',
                        warning: _depMissing('auc') ? 'auc не установлен' : null,
                        onTap: _checkFirmware,
                      ),
                    const SizedBox(height: 16),
                    _ActionCard(
                      icon: Icons.terminal,
                      title: 'Терминал',
                      subtitle: 'Выполнить SSH-команду',
                      onTap: _showTerminalCommand,
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.article,
                      title: 'Системные логи',
                      subtitle: 'logread / dmesg',
                      onTap: _showLogs,
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.network_check,
                      title: 'Перезапустить сеть',
                      subtitle: '/etc/init.d/network restart',
                      onTap: () => _serviceAction('network'),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.shield,
                      title: 'Проверить зависимости',
                      subtitle: 'Установить / сбросить недостающие пакеты',
                      onTap: () => _showDepsMenu(),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.public, title: 'Удалённый доступ', subtitle: 'SSH снаружи — безопасный порт', onTap: _remoteAccessDialog),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.power_settings_new, title: 'Перезагрузить', subtitle: 'reboot', color: theme.colorScheme.error, onTap: _reboot),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.access_time, title: 'Синхронизация времени', subtitle: 'NTP / sysntpd / date', onTap: _syncTime),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.vpn_key, title: 'Создать SSH-ключ', subtitle: 'Генерация ED25519 для входа без пароля', onTap: _generateSshKey),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.router, title: 'Проброс портов', subtitle: 'Firewall redirects', onTap: _showPortForwards),
                    const SizedBox(height: 12),
                    if (_showCard('wol'))
                      _ActionCard(icon: Icons.power_settings_new, title: 'Wake-on-LAN', subtitle: 'Разбудить устройство по MAC',
                        warning: _depMissing('wol') ? 'wol/etherwake не установлен' : null,
                        onTap: _showWolDialog),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.schedule, title: 'Расписание Wi-Fi', subtitle: 'Авто вкл/выкл по времени', onTap: _showWifiSchedule),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.thermostat, title: 'Температура CPU', subtitle: 'Проверить нагрев роутера', onTap: _checkTemperature),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.usb, title: 'USB-устройства', subtitle: 'Диски, принтеры, модемы', onTap: _showUsbDevices),
                    const SizedBox(height: 12),
                    if (_showCard('nmap'))
                      _ActionCard(icon: Icons.search, title: 'Сканер сети (nmap)', subtitle: 'Найти все устройства в LAN',
                        warning: _depMissing('nmap') ? 'nmap не установлен' : null,
                        onTap: _runNmapScan),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.security, title: 'AdGuard Home', subtitle: 'Статус блокировки рекламы', onTap: _checkAdGuard),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.language, title: 'DDNS статус', subtitle: 'Динамический DNS', onTap: _showDdnsStatus),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.dns, title: 'DNS', subtitle: 'Настройка DNS-серверов', onTap: _showDnsDialog),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.backup, title: 'Бэкап конфигурации', subtitle: 'AES-256 экспорт/импорт', onTap: _showBackupDialog),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.notifications, title: 'Уведомления', subtitle: 'мониторинг роутера', onTap: _setupNotifications),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.security, title: 'Безопасность устройства', subtitle: 'Root/эмулятор/отладка', onTap: _showSecurityStatus),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.smart_toy, title: 'AI-ассистент', subtitle: 'OpenRouter / DeepSeek', onTap: _setupAiKey),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.analytics, title: 'AI анализ', subtitle: 'Логи/безопасность/производительность', onTap: _showAiAnalysis),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.info_outline, title: 'О приложении', subtitle: 'РыбинскLAB • Усачёв Денис',
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()))),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.logout,
                      title: 'Выйти',
                      subtitle: 'Вернуться к выбору роутера',
                      onTap: () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute(builder: (_) => const LoginScreen()),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    final release = boardInfo!['release'] is Map ? boardInfo!['release'] as Map<String, dynamic> : {};
    final target = release['target']?.toString() ?? boardInfo!['board_name']?.toString() ?? '-';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Информация об устройстве', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _InfoRow('Модель', boardInfo!['model']?.toString() ?? boardInfo!['board_name']?.toString() ?? '-'),
            _InfoRow('Система', boardInfo!['system']?.toString() ?? '-'),
            _InfoRow('Хост', boardInfo!['hostname']?.toString() ?? '-'),
            _InfoRow('Платформа', target),
            _InfoRow('Ядро', boardInfo!['kernel']?.toString() ?? '-'),
            const Divider(height: 24),
            _InfoRow('Дистрибутив', release['distribution']?.toString() ?? '-'),
            _InfoRow('Версия', release['version']?.toString() ?? '-'),
            _InfoRow('Ревизия', release['revision']?.toString() ?? '-'),
            _InfoRow('Описание', release['description']?.toString() ?? '-'),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return SliverFillRemaining(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text('Ошибка', style: theme.textTheme.titleMedium),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonal(onPressed: _load, child: const Text('Повторить')),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? color;
  final String? warning;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.color,
    this.warning,
  });  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warn = warning != null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: Icon(icon, color: warn ? Colors.amber.shade800 : (color ?? theme.colorScheme.primary)),
        title: Text(title),
        subtitle: Text(warn ? '${subtitle} — ${warning}' : subtitle),
        trailing: warn
            ? Icon(Icons.warning_amber_rounded, color: Colors.amber.shade800)
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _UsbTile extends StatelessWidget {
  final Map<String, String> d;
  final VoidCallback onBrowse;

  const _UsbTile({required this.d, required this.onBrowse});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = d['type'] ?? '';
    final browsable = d['browsable'] == '1';
    final availKb = int.tryParse(d['avail'] ?? '');
    final usedKb = int.tryParse(d['used'] ?? '');
    final icon = type.contains('модем')
        ? Icons.network_cell
        : type.contains('флешка') || type.contains('SSD') || type.contains('HDD')
            ? Icons.storage
            : Icons.usb;
    final parts = <String>[
      type,
      if (d['size'] != null && d['size']!.isNotEmpty && d['size'] != 'USB') d['size']!,
      if (availKb != null) 'свободно ${NetworkInterface.formatBytes(availKb * 1024)}',
      if (usedKb != null && usedKb > 0) 'занято ${NetworkInterface.formatBytes(usedKb * 1024)}',
      if (d['fstype'] != null && d['fstype']!.isNotEmpty) d['fstype']!,
      if (d['mount'] != null && d['mount'] != '—') d['mount']!,
    ];
    final model = d['model'] ?? '';
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(
        [if (d['label'] != null && d['label']!.isNotEmpty) d['label']!, d['name']!].join(' '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text([model, if (model.isNotEmpty) ' • ', parts.join(' • ')].join().isEmpty
          ? '—'
          : [if (model.isNotEmpty) model, parts.join(' • ')].join(' • ')),
      trailing: browsable
          ? Icon(Icons.folder_open, color: theme.colorScheme.primary)
          : null,
      onTap: browsable ? onBrowse : null,
    );
  }
}
