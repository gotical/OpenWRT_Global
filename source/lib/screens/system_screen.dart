import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../l10n/app_strings.dart';
import '../models/network_info.dart';
import '../models/wifi_info.dart';
import '../services/openwrt_service.dart';
import '../services/storage_service.dart';
import '../services/backup_service.dart';
import '../services/notification_service.dart';
import '../services/device_security.dart';
import '../services/secure_screen.dart';
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

  String _t(String source) => AppStrings.of(context).text(source);

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
    final ok = await _confirm(_t('Перезагрузить роутер?'), _t('Устройство будет перезагружено.'));
    if (ok != true) return;
    try {
      await widget.service.reboot();
      if (!mounted) return;
      _snack(_t('Команда перезагрузки отправлена'));
    } catch (e) {
      if (!mounted) return;
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _syncTime() async {
    _showProgress(_t('Синхронизация времени...'));
    try {
      final result = await widget.service.syncTime();
      if (!mounted) return;
      Navigator.pop(context);
      _snack(result);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _generateSshKey() async {
    _showProgress(_t('Генерация SSH-ключа...'));
    try {
      final keys = await widget.service.generateAndInstallKey();
      if (!mounted) return;
      Navigator.pop(context);
      final priv = keys['private'] ?? '';
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [const Icon(Icons.vpn_key, color: Colors.green), const SizedBox(width: 8), Text(_t('SSH-ключ создан'))]),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_t('Приватный ключ (сохраните его):'), style: const TextStyle(fontWeight: FontWeight.bold)),
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
              Text(_t('Теперь вы можете войти по ключу, скопируйте приватный ключ и добавьте роутер с типом "SSH-ключ".')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      _snack(_t('SSH-ключ установлен на роутер'));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _serviceAction(String name) async {
    final ok = await _confirm('${_t('Перезапустить')} $name?', _t('Служба будет перезапущена.'));
    if (ok != true) return;
    _showProgress('${_t('Перезапуск')} $name...');
    try {
      await widget.service.restartService(name);
      if (!mounted) return;
      Navigator.pop(context);
      _snack('$name ${_t('перезапущен')}');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _showLogs() async {
    showDialog(
      context: context,
      barrierDismissible: false,
       builder: (ctx) => AlertDialog(
         content: Row(children: [const CircularProgressIndicator(), const SizedBox(width: 16), Text(_t('Загрузка логов...'))]),
      ),
    );
    List<String> logs = [];
    try {
      logs = await widget.service.fetchLogs(lines: 80);
    } catch (e) {
      logs = ['${_t('Ошибка загрузки логов')}: $e'];
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
                  Text(_t('Системные логи'), style: Theme.of(ctx).textTheme.titleLarge),
                  Row(children: [
                    IconButton(
                      onPressed: () => _aiAnalyzeLogs(ctx, logs),
                       tooltip: _t('AI анализ'),
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
    String? key;
    String logText;
    try {
      await AiAnalysisService.init();
      key = await StorageService.loadApiKey(await StorageService.loadActiveAiProvider() ?? 'deepseek');
      logText = logs.take(60).join('\n');
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
      return;
    }
    if (key == null || key.isEmpty) {
      if (mounted) _snack('${_t('Настройте API-ключ в')} «${_t('AI-ассистент')}»');
      return;
    }
    if (!ctx.mounted) return;
    await showDialog(
      context: ctx,
      builder: (dctx) => const AlertDialog(
        content: SizedBox(height: 60, child: Row(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(width: 16), Text('AI...')])),
      ),
    );
    String? result;
    try {
      result = await AiAnalysisService.analyzeLog(logText);
    } catch (e) {
      if (ctx.mounted) Navigator.pop(ctx);
      if (mounted) _snack('${_t('Ошибка AI')}: $e');
      return;
    }
    if (!ctx.mounted) return;
    Navigator.pop(ctx);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(_t('AI анализ логов')),
        content: SingleChildScrollView(child: Text(result ?? _t('Нет ответа от AI'), style: const TextStyle(fontSize: 13))),
        actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: Text(_t('Закрыть')))],
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
             title: Text(_t('Выполнить команду')),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: ctrl,
                     decoration: InputDecoration(hintText: _t('Например: uci show network')),
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
               TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
              FilledButton(
                onPressed: running ? null : () async {
                  setSt(() { running = true; output = null; });
                  try {
                    final res = await widget.service.runCommand(ctrl.text.trim());
                    if (ctx.mounted) setSt(() { output = res; running = false; });
                  } catch (e) {
                    if (ctx.mounted) setSt(() { output = '${_t('Ошибка')}: $e'; running = false; });
                  }
                },
                 child: Text(_t('Выполнить')),
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
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Подтвердить'))),
          ],
        ),
      );

  Future<void> _checkFirmware() async {
    _showProgress(_t('Проверка обновлений...'));
    try {
      final result = await widget.service.checkFirmwareUpdate();
      if (!mounted) return;
      Navigator.pop(context);

      if (result == null || result.contains('Нет')) {
        _snack(_t('Обновлений не найдено'));
        return;
      }

      final resultText = result;
      final upgrading = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
           title: Text(_t('Доступно обновление')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(resultText.length > 100 ? '${resultText.substring(0, 100)}...' : resultText),
            const SizedBox(height: 16),
             Text(_t('Загрузить и установить обновление? Роутер будет перезагружен.'), style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
             FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Обновить'))),
          ],
        ),
      );

      if (upgrading == true) {
        _showUpgradeProgress();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _snack('${_t('Ошибка проверки')}: $e');
    }
  }

  void _showUpgradeProgress() {
    String status = _t('Готовимся...');
    StateSetter? setter;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          setter = setSt;
          return AlertDialog(
             title: Text(_t('Обновление прошивки')),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 16),
              Text(status),
            ]),
            actions: [
               if (status.contains(_t('перезагружается')) || status.contains(_t('ошибка')))
                 TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          );
        },
      ),
    );
    widget.service.upgradeFirmware((s) {
      status = switch (s) {
        'checking' => _t('Проверка auc...'),
        'installing_auc' => _t('Установка auc...'),
        'downloading' => _t('Загрузка прошивки...'),
        'rebooting' => _t('Роутер перезагружается...'),
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
           title: Text(_t('AI-ассистент')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
               Text(_t('Выберите провайдера AI для автооптимизации WiFi:')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: provider,
                   items: [
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
             TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Отмена'))),
            FilledButton(onPressed: () async {
              await StorageService.saveApiKey(provider, ctrl.text.trim());
              await StorageService.saveActiveAiProvider(provider);
              if (!mounted) return;
              Navigator.pop(ctx);
               _snack('${_t('Ключ')} $provider ${_t('сохранён')}');
             }, child: Text(_t('Сохранить'))),
          ],
        ),
      ),
    );
  }

  Future<void> _showAiAnalysis() async {
    await AiAnalysisService.init();
    if (await StorageService.loadApiKey(await StorageService.loadActiveAiProvider() ?? 'deepseek') == null) {
       _snack('${_t('Сначала настройте API-ключ в')} «${_t('AI-ассистент')}»');
      _setupAiKey();
      return;
    }
    _showProgress(_t('AI анализ...'));
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
           title: Row(children: [const Icon(Icons.smart_toy), const SizedBox(width: 8), Text(_t('AI рекомендации'))]),
           content: SingleChildScrollView(child: Text(result ?? _t('Нет ответа от AI'), style: const TextStyle(fontSize: 14))),
           actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть')))],
        ),
      );
    } catch (e) {
       if (mounted) { Navigator.pop(context); _snack('${_t('Ошибка')}: $e'); }
    }
  }

  Future<void> _showBackupDialog() async {
    final pwdCtrl = TextEditingController();
    final dataCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text(_t('Бэкап конфигурации')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
             Text(_t('Экспорт или импорт конфигураций роутеров с AES-256 шифрованием.')),
            const SizedBox(height: 12),
            TextField(
              controller: pwdCtrl,
              obscureText: true,
               decoration: InputDecoration(labelText: _t('Пароль шифрования')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dataCtrl,
              maxLines: 3,
               decoration: InputDecoration(labelText: _t('Данные (для импорта)')),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () async {
            if (pwdCtrl.text.isEmpty) return;
            final routers = await StorageService.loadRouters();
            // Экспортируем ВСЕ поля, включая секреты — они зашифрованы AES-256,
            // иначе бэкап нельзя было бы восстановить на другом устройстве.
            final data = routers.map((r) => {
              'name': r.name,
              'host': r.host,
              'port': r.port,
              'username': r.username,
              'password': r.password,
              'sshKey': r.sshKey,
              'useKey': r.useKey,
              'useHttps': r.useHttps,
              'fingerprint': r.fingerprint,
            }).toList();
            final encrypted = BackupService.exportToJson({'routers': data, 'version': '4.0.8'}, pwdCtrl.text);
            await showDialog(
              context: ctx,
              builder: (ctx) => AlertDialog(
                 title: Text(_t('QR-код резервной копии')),
                content: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                     Text(_t('Отсканируйте QR для импорта на другое устройство')),
                    const SizedBox(height: 12),
                    QrImageView(data: encrypted, size: 200),
                    const SizedBox(height: 12),
                    SelectableText(encrypted, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                  ]),
                ),
                actions: [
                  TextButton(onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: encrypted));
                     if (ctx.mounted) _snack(_t('Скопировано в буфер'));
                   }, child: Text(_t('Копировать'))),
                   TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
                ],
              ),
            );
           }, child: Text(_t('Экспорт QR'))),
          TextButton(onPressed: () async {
            if (pwdCtrl.text.isEmpty || dataCtrl.text.isEmpty) return;
            try {
              final decrypted = BackupService.importFromJson(dataCtrl.text, pwdCtrl.text);
              if (decrypted['routers'] is List) {
                 _snack('${_t('Импорт успешен')}: ${(decrypted['routers'] as List).length} ${_t('конфигураций')}');
              }
            } catch (e) {
               _snack(_t('Ошибка импорта: неверный пароль или данные'));
            }
           }, child: Text(_t('Импорт'))),
           TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
        ],
      ),
    );
  }

  Future<void> _setupNotifications() async {
    final enabled = await StorageService.isNotificationsEnabled();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text(_t('Уведомления')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
           Text(_t('Получать уведомления о состоянии роутера:')),
          const SizedBox(height: 12),
           Text(_t('• Высокая температура CPU')),
           Text(_t('• Высокая загрузка CPU / RAM')),
           Text(_t('• Потеря WAN подключения')),
           Text(_t('• Отключение VPN')),
           Text(_t('• Доступны обновления прошивки')),
          const SizedBox(height: 12),
          SwitchListTile(
             title: Text(_t('Включить уведомления')),
            value: enabled,
            onChanged: (v) async {
              await StorageService.setNotificationsEnabled(v);
              if (v) await NotificationService.init();
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ]),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
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
         title: Row(children: [const Icon(Icons.security), const SizedBox(width: 8), Text(_t('Безопасность'))]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
           _secRow(_t('Root доступ'), root),
          const SizedBox(height: 8),
           _secRow(_t('Эмулятор'), emu),
          const SizedBox(height: 8),
           _secRow(_t('Режим отладки'), debug),
          const SizedBox(height: 8),
          _secRow('HTTP Proxy', proxy),
        ]),
         actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть')))],
      ),
    );
  }

  Future<void> _showScreenshotSecurity() async {
    var enabled = await StorageService.loadSecureScreen();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.screenshot_monitor),
            const SizedBox(width: 8),
            Text(_t('Защита экрана')),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_t('Выключите защиту, чтобы можно было делать скриншоты.')),
              const SizedBox(height: 8),
              SwitchListTile(
                title: Text(enabled ? _t('Защита включена') : _t('Защита выключена')),
                subtitle: Text(enabled ? _t('Скриншоты запрещены') : _t('Скриншоты разрешены')),
                value: enabled,
                onChanged: (v) async {
                  setSt(() => enabled = v);
                  await StorageService.saveSecureScreen(v);
                  if (v) {
                    await SecureScreen.enable();
                  } else {
                    await SecureScreen.disable();
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
          ],
        ),
      ),
    );
  }

  Widget _secRow(String label, bool detected) {
    return Row(children: [
      Icon(detected ? Icons.warning_amber : Icons.check_circle, color: detected ? Colors.red : Colors.green, size: 20),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(fontSize: 16)),
      const Spacer(),
       Text(detected ? _t('ОБНАРУЖЕНО') : _t('Не обнаружено'), style: TextStyle(color: detected ? Colors.red : Colors.green, fontWeight: FontWeight.w600)),
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
             title: Text(_t('Настройка DNS')),
            content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Быстрый выбор DNS (пресеты РФ/СНГ и мировые).
                DropdownButtonFormField<String>(
                  initialValue: _dnsPresetSel,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _t('Быстрый выбор DNS'),
                    prefixIcon: const Icon(Icons.bolt),
                  ),
                  items: [
                    DropdownMenuItem(value: '', child: Text(_t('— свои (ввести вручную) —'))),
                    for (final p in OpenWrtService.dnsPresets)
                      DropdownMenuItem(value: p.name, child: Text(p.name)),
                  ],
                  onChanged: (v) {
                    setSt(() => _dnsPresetSel = v ?? '');
                    if (v != null && v.isNotEmpty) {
                      for (final p in OpenWrtService.dnsPresets) {
                        if (p.name == v) {
                          setSt(() {
                            dnsType = 'default';
                            dns1.text = p.ips.isNotEmpty ? p.ips[0] : '';
                            dns2.text = p.ips.length > 1 ? p.ips[1] : '';
                          });
                          break;
                        }
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                // Пресеты — сразу применить.
                if (_dnsPresetSel.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.check),
                      label: Text(_t('Применить пресет')),
                      onPressed: () async {
                        for (final p in OpenWrtService.dnsPresets) {
                          if (p.name == _dnsPresetSel) {
                            try {
                              await widget.service.setDns(p.ips);
                              if (mounted) {
                                _snack('${_t('DNS обновлён')}: ${p.name}', ok: true);
                                Navigator.pop(ctx);
                              }
                            } catch (e) {
                              if (mounted) _snack('${_t('Ошибка')}: $e');
                            }
                            return;
                          }
                        }
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: dnsType,
                  isExpanded: true,
                   decoration: InputDecoration(labelText: _t('Тип DNS')),
                 items: [
                     DropdownMenuItem(value: 'default', child: Text(_t('Обычный (UDP:53)'))),
                    DropdownMenuItem(value: 'dot', child: Text('DNS-over-TLS')),
                    DropdownMenuItem(value: 'doh', child: Text('DNS-over-HTTPS')),
                  ],
                  onChanged: (v) => setSt(() { dnsType = v ?? 'default'; dns1.clear(); dns2.clear(); }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: dns1,
                  decoration: InputDecoration(
                     labelText: dnsType == 'doh' ? 'DoH URL' : dnsType == 'dot' ? _t('DoT домен') : _t('Основной DNS'),
                    hintText: dnsType == 'doh' ? 'https://dns.adguard.com/dns-query' : dnsType == 'dot' ? 'dns.adguard.com' : '1.1.1.1',
                    prefixIcon: const Icon(Icons.dns),
                  ),
                ),
                if (dnsType == 'default') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: dns2,
                     decoration: InputDecoration(labelText: _t('Резервный DNS'), hintText: '8.8.8.8', prefixIcon: const Icon(Icons.dns_outlined)),
                  ),
                ],
                if (dnsType == 'dot') ...[
                  const SizedBox(height: 8),
                   Text(_t('Формат: домен без https://\nПорт 853 добавляется автоматически'), style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ],
                if (dnsType == 'doh') ...[
                  const SizedBox(height: 8),
                   Text(_t('Формат: https://dns.server/dns-query'), style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                ],
              ]),
            ),
            actions: [
               TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Отмена'))),
              FilledButton(onPressed: () async {
                Navigator.pop(ctx);
                final primary = dns1.text.trim();
                final secondary = dns2.text.trim();
                if (primary.isEmpty) return;
                final servers = <String>[primary];
                if (secondary.isNotEmpty && dnsType == 'default') servers.add(secondary);
                await widget.service.setDns(servers);
                 if (mounted) _snack('${_t('DNS обновлён')}: $primary');
               }, child: Text(_t('Сохранить'))),
            ],
          ),
        ),
      );
    } catch (e) {
       if (mounted) _snack('${_t('Ошибка DNS')}: $e');
    }
  }
  Future<void> _remoteAccessDialog() async {
     _showProgress(_t('Проверка...'));
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
           title: Text(_t('Удалённый доступ')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
               Row(children: [Text(_t('WAN IP:')), const SizedBox(width: 8), Expanded(child: SelectableText(wanIp, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700)))]),
              const SizedBox(height: 12),
              if (srcPort != null && srcPort.isNotEmpty && enabled) ...[
                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                     Text(_t('Доступ открыт'), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.green)),
                    const SizedBox(height: 4),
                    SelectableText('ssh root@$wanIp -p $srcPort', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                    const SizedBox(height: 8),
                     Text('${_t('В приложении: добавьте роутер')}\n${_t('с IP')} $wanIp ${_t('и портом')} $srcPort'),
                  ])),
                 OutlinedButton.icon(onPressed: () async { Navigator.pop(ctx); try { await widget.service.disableRemoteAccess(); if (mounted) _snack(_t('Удалённый доступ закрыт')); } catch (e) { if (mounted) _snack('${_t('Ошибка')}: $e'); } }, icon: const Icon(Icons.lock), label: Text(_t('Закрыть доступ'))),
              ] else ...[
                 Text(_t('Доступ закрыт. Открыть порт для SSH?'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                 Text(_t('Будет создан проброс порта 22022 → 22.\nИспользуйте сложный пароль root!'), style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                 FilledButton.icon(onPressed: () async { Navigator.pop(ctx); try { await widget.service.enableRemoteAccess(); if (mounted) _snack(_t('Доступ открыт на порт 22022')); } catch (e) { if (mounted) _snack('${_t('Ошибка')}: $e'); } }, icon: const Icon(Icons.lock_open), label: Text(_t('Открыть доступ (порт 22022)'))),
              ],
            ]),
          ),
           actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть')))],
        ),
      );
    } catch (e) { if (mounted) { Navigator.pop(context); _snack('$e'); } }
  }

  Future<void> _showPortForwards() async {
     _showProgress(_t('Загрузка...'));
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
                   Text('${_t('Проброс портов')} (${rules.length})', style: Theme.of(ctx).textTheme.titleLarge),
                  const Spacer(),
                   IconButton(onPressed: () { Navigator.pop(ctx); _addPortForward(); }, icon: const Icon(Icons.add_circle_outline), tooltip: _t('Добавить')),
                ],
              ),
            ),
            Expanded(
              child: rules.isEmpty
                   ? Center(child: Text(_t('Нет правил')))
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
                                   tooltip: enabled ? _t('Отключить') : _t('Включить'),
                                  onPressed: () async {
                                    try {
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
                                    } catch (e) {
                                      if (mounted) _snack('${_t('Ошибка')}: $e');
                                    }
                                  },
                                ),
                                 IconButton(icon: const Icon(Icons.edit, size: 20), tooltip: _t('Редактировать'),
                                  onPressed: () { Navigator.pop(ctx); _editPortForward(r); }),
                                 IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), tooltip: _t('Удалить'),
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: ctx,
                                      builder: (d) => AlertDialog(
                                         title: Text(_t('Удалить правило?')),
                                        content: Text('${r['name'] ?? r['section']}'),
                                        actions: [
                                           TextButton(onPressed: () => Navigator.pop(d, false), child: Text(_t('Отмена'))),
                                           FilledButton(onPressed: () => Navigator.pop(d, true), child: Text(_t('Удалить'))),
                                        ],
                                      ),
                                    );
                                    if (ok != true) return;
                                    try {
                                      await widget.service.deletePortForward(r['section']!);
                                      if (mounted) { Navigator.pop(ctx); _showPortForwards(); }
                                    } catch (e) {
                                      if (mounted) _snack('${_t('Ошибка')}: $e');
                                    }
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
    try {
      await widget.service.addPortForward(
        name: values['name']!,
        srcDport: values['dport']!,
        destIp: values['ip']!,
        destPort: values['dp']!,
        proto: values['proto']!,
      );
      if (mounted) _snack(_t('Правило добавлено'));
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _editPortForward(Map<String, String> rule) async {
    final values = await _portForwardDialog(rule);
    if (values == null) return;
    try {
      await widget.service.updatePortForward(
        section: rule['section']!,
        name: values['name']!,
        srcDport: values['dport']!,
        destIp: values['ip']!,
        destPort: values['dp']!,
        proto: values['proto']!,
        enabled: values['enabled'] == '1',
      );
      if (mounted) _snack(_t('Правило обновлено'));
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
    }
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
           title: Text(existing == null ? _t('Новое правило') : _t('Изменить правило')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
               TextField(controller: name, decoration: InputDecoration(labelText: _t('Название'))),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: proto,
                items: [
                  const DropdownMenuItem(value: 'tcp', child: Text('TCP')),
                  const DropdownMenuItem(value: 'udp', child: Text('UDP')),
                   DropdownMenuItem(value: 'tcp udp', child: Text(_t('Оба'))),
                ],
                onChanged: (v) => setSt(() => proto = v!),
              ),
               TextField(controller: port, decoration: InputDecoration(labelText: _t('Внешний порт (WAN)')), keyboardType: TextInputType.number),
               TextField(controller: ip, decoration: InputDecoration(labelText: _t('Локальный IP')), keyboardType: TextInputType.number),
               TextField(controller: dport, decoration: InputDecoration(labelText: _t('Локальный порт')), keyboardType: TextInputType.number),
              SwitchListTile(
                value: enabled,
                onChanged: (v) => setSt(() => enabled = v),
                 title: Text(_t('Правило включено')),
              ),
            ]),
          ),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
               child: Text(existing == null ? _t('Добавить') : _t('Сохранить')),
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
       title: const Text('Wake-on-LAN'), content: TextField(controller: ctrl, decoration: InputDecoration(labelText: _t('MAC-адрес'))), actions: [
       TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Отмена'))), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Разбудить'))),
    ]));
    if (ok == true && ctrl.text.isNotEmpty) {
      try {
        await widget.service.wakeOnLan(ctrl.text);
        if (mounted) _snack(_t('Magic packet отправлен'));
      } catch (e) {
        if (mounted) _snack('${_t('Ошибка')}: $e');
      }
    }
  }

  Future<void> _showWifiSchedule() async {
    List<WifiNetwork> nets;
    try {
      nets = await widget.service.fetchWifiNetworks();
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
      return;
    }
    if (nets.isEmpty) { _snack(_t('Wi-Fi сети не найдены')); return; }
    String? section;
    await showDialog(context: context, builder: (ctx) => AlertDialog(
       title: Text(_t('Выберите сеть')), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: nets.map((n) => ListTile(title: Text(n.ssid), onTap: () { section = n.section; Navigator.pop(ctx); })).toList())),
    ));
    if (section == null) return;
    final start = TimeOfDay(hour: 1, minute: 0), stop = TimeOfDay(hour: 7, minute: 0);
    final s = await showTimePicker(context: context, initialTime: start);
    if (s == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: stop);
    if (t == null || !mounted) return;
    try {
      await widget.service.scheduleWifi(section!, start: '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}', stop: '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
      if (mounted) _snack(_t('Расписание сохранено'));
    } catch (e) {
      if (mounted) _snack('${_t('Ошибка')}: $e');
    }
  }

  Future<void> _checkTemperature() async {
    _showProgress(_t('Проверка...'));
    try {
      final t = await widget.service.fetchTemperature();
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(context: context, builder: (ctx) => AlertDialog(title: Text(_t('Температура')), content: Text(t), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${_t('Ошибка')}: $e'); }
    }
  }

  Future<void> _showUsbDevices() async {
    _showProgress(_t('Сканирование...'));
    List<Map<String, String>> devs;
    try {
      devs = await widget.service.fetchUsbDevices();
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${_t('Ошибка')}: $e'); }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);

    // Используем модальный bottom sheet вместо showDialog. Это убирает
    // гонку навигации (push после pop dialog) и даёт больше места для
    // отображения крупных кнопок «Открыть» / «Подключить».
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (_, scrollCtrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                const Icon(Icons.usb),
                const SizedBox(width: 10),
                Text(_t('USB-устройства'),
                    style: Theme.of(bctx).textTheme.titleLarge),
                const Spacer(),
                Text('${devs.length}',
                    style: Theme.of(bctx).textTheme.bodySmall),
              ]),
            ),
            Expanded(
              child: devs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.usb_off, size: 56, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text(_t('USB-устройств не найдено')),
                            const SizedBox(height: 4),
                            Text(_t('Подключите флешку/диск к USB-порту роутера'),
                                style: Theme.of(bctx).textTheme.bodySmall,
                                textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      itemCount: devs.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UsbTile(
                          d: devs[i],
                          onBrowse: () {
                            Navigator.pop(bctx);
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => UsbBrowserScreen(
                                      service: widget.service,
                                      startPath: (devs[i]['mount'] ?? '') == '—'
                                          ? '/'
                                          : devs[i]['mount']!,
                                      devicePath: (devs[i]['dev'] ?? '').isEmpty
                                          ? null
                                          : devs[i]['dev'],
                                    )));
                          },
                          onMount: () async {
                            final dev = devs[i]['dev'] ?? '';
                            if (dev.isEmpty) return;
                            Navigator.pop(bctx);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                duration: const Duration(seconds: 2),
                                content:
                                    Text('${_t('Подключение')}: $dev')));
                            String? mount;
                            try {
                              mount = await widget.service
                                  .mountUsbDevice(dev);
                            } catch (e) {
                              if (mounted) _snack('${_t('Ошибка')}: $e');
                              return;
                            }
                            if (!mounted) return;
                            if (mount == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      duration: const Duration(seconds: 4),
                                      content: Text(_t(
                                          'Не удалось подключить: монтируйте раздел (например /dev/sda1), а не весь диск'))));
                              return;
                            }
                            Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => UsbBrowserScreen(
                                      service: widget.service,
                                      startPath: mount!,
                                      devicePath: dev,
                                    )));
                          },
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runNmapScan() async {
    _showProgress(_t('Сканирование сети (nmap)...'));
    try {
      final devs = await widget.service.runNmapScan();
      if (!mounted) return;
      Navigator.pop(context);
      showDialog(context: context, builder: (ctx) => AlertDialog(
         title: Text('${_t('Устройства')} (${devs.length})'), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: devs.length, itemBuilder: (_, i) => ListTile(title: Text(devs[i]['ip']!), subtitle: Text('${devs[i]['mac']} ${devs[i]['vendor']}')))),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ));
    } catch (e) { if (mounted) { Navigator.pop(context); _snack('nmap не установлен? $e'); } }
  }

  Future<void> _checkAdGuard() async {
    _showProgress(_t('Проверка AdGuard...'));
    Map<String, dynamic>? info;
    try {
      info = await widget.service.fetchAdGuardInfo();
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${_t('Ошибка')}: $e'); }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    var enabled = info?['protection_enabled'] == true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Row(children: [const Icon(Icons.security), const SizedBox(width: 8), const Text('AdGuard Home')]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info == null)
                Text(_t('Не запущен. Установите AdGuard Home.'))
              else ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_t('Защита')),
                  value: enabled,
                  onChanged: (v) async {
                    setSt(() => enabled = v);
                    try {
                      final ok = await widget.service.setAdGuardProtection(v);
                      if (!ok && ctx.mounted) setSt(() => enabled = !v);
                    } catch (e) {
                      if (ctx.mounted) setSt(() => enabled = !v);
                      if (mounted) _snack('${_t('Ошибка')}: $e');
                    }
                  },
                ),
                if (info['version'] != null)
                  _InfoRow(_t('Версия'), info['version']!.toString()),
                if (info['dns_queries'] != null)
                  _InfoRow(_t('Запросов DNS'), info['dns_queries'].toString()),
                if (info['blocked_queries'] != null)
                  _InfoRow(_t('Заблокировано'), info['blocked_queries'].toString()),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
          ],
        ),
      ),
    );
  }

  Future<void> _showDdnsStatus() async {
    _showProgress(_t('Проверка DDNS...'));
    List<Map<String, String>> list;
    try {
      list = await widget.service.fetchDdnsStatus();
    } catch (e) {
      if (mounted) { Navigator.pop(context); _snack('${_t('Ошибка')}: $e'); }
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Row(children: [const Icon(Icons.language), const SizedBox(width: 8), const Text('DDNS')]),
          content: SizedBox(
            width: double.maxFinite,
            child: list.isEmpty
                ? Text(_t('Не настроен'))
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: list.map((e) {
                        final on = e['enabled'] != '0';
                        return ListTile(
                          title: Text(e['name']!),
                          subtitle: Text('${e['domain']} • ${e['ip']}'),
                          trailing: Switch(
                            value: on,
                            onChanged: (v) async {
                              try {
                                await widget.service.setDdnsEnabled(e['section']!, v);
                                e['enabled'] = v ? '1' : '0';
                                if (ctx.mounted) setSt(() {});
                                _snack(v ? _t('DDNS включён') : _t('DDNS выключен'));
                              } catch (err) {
                                if (mounted) _snack('${_t('Ошибка')}: $err');
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
          ],
        ),
      ),
    );
  }

  Future<void> _offerReboot() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
         title: Text(_t('Перезагрузить роутер?')),
         content: Text(_t('Некоторые пакеты требуют перезагрузки для активации.')),
        actions: [
           TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Позже'))),
           FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_t('Перезагрузить'))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.service.reboot();
        if (mounted) _snack(_t('Команда перезагрузки отправлена'));
      } catch (e) {
        if (mounted) _snack('${_t('Ошибка')}: $e');
      }
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
           Padding(padding: const EdgeInsets.all(16), child: Text(_t('Зависимости'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.refresh),
             title: Text(_t('Проверить и установить')),
             subtitle: Text(_t('Проверить наличие пакетов на роутере')),
            onTap: () { Navigator.pop(ctx); _checkDependencies(); },
          ),
          ListTile(
            leading: Icon(alreadyChecked ? Icons.check_circle : Icons.cancel),
             title: Text(_t('Сбросить статус проверки')),
             subtitle: Text(alreadyChecked ? _t('Сейчас: не проверять автоматически') : _t('Сейчас: проверять при входе')),
            onTap: () async {
              if (alreadyChecked) {
                await StorageService.resetDepsChecked(host);
              } else {
                await StorageService.markDepsChecked(host);
              }
              Navigator.pop(ctx);
               _snack(alreadyChecked ? _t('Проверка будет показана при следующем входе') : _t('Автопроверка отключена'));
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _checkDependencies() async {
    _showProgress(_t('Проверка...'));
    try {
      final pkg = await widget.service.detectPackageManager();
      final deps = await widget.service.checkDependencies();
      if (!mounted) return;
      Navigator.pop(context);

      _showDepsListDialog(pkg, deps);
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
       _snack('${_t('Ошибка')}: $e');
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
               TextButton(onPressed: installing ? null : () => Navigator.pop(ctx), child: Text(_t('Закрыть'))),
              if (missingCount > 0)
                FilledButton(
                  onPressed: installing ? null : () async {
                    final toInstall = entries.where((e) => !e.value && !isStock(e.key) && e.key != 'wget/uclient').toList();
                    total = toInstall.length; done = 0;
                    setSt(() => installing = true);
                    for (final e in toInstall) {
                      if (!ctx.mounted) return;
                      final primary = OpenWrtService.packageForDependency[e.key];
                      if (primary == null) continue;
                       setSt(() { status[e.key] = 'downloading'; msg = '${_t('Загрузка')} $primary...'; });
                      try {
                        await widget.service.installPackages([primary]);
                         if (ctx.mounted) setSt(() { status[e.key] = 'done'; done++; msg = '${_t('Готово')} $primary'; });
                      } catch (_) {
                        try {
                          final alt = await widget.service.findAlternativePackage(e.key);
                          if (alt != null && alt != primary) {
                            await widget.service.installPackages([alt]);
                             if (ctx.mounted) setSt(() { status[e.key] = 'done'; done++; msg = '${_t('Готово')} $alt (${_t('альтернатива')})'; });
                          } else {
                            rethrow;
                          }
                        } catch (_) {
                           if (ctx.mounted) setSt(() { status[e.key] = 'error'; done++; msg = '${_t('Ошибка')} $primary'; });
                        }
                      }
                      await Future.delayed(const Duration(milliseconds: 400));
                    }
                     if (ctx.mounted) setSt(() { installing = false; msg = '${_t('Установлено')} $done/${total}'; });
                    await StorageService.markDepsChecked(widget.service.config.host);
                    await Future.delayed(const Duration(seconds: 1));
                    _offerReboot();
                  },
                   child: Text(_t('Установить всё')),
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

  String _dnsPresetSel = '';

  void _snack(String msg, {bool ok = false}) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: ok ? Colors.green.shade700 : null));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = AppStrings.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar.large(
               title: Text(s.system),
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
                         title: s.text('Проверить обновление прошивки'),
                        subtitle: 'Attended SysUpgrade (auc)',
                         warning: _depMissing('auc') ? s.text('auc не установлен') : null,
                        onTap: _checkFirmware,
                      ),
                    const SizedBox(height: 16),
                    _ActionCard(
                      icon: Icons.terminal,
                       title: s.text('Терминал'),
                       subtitle: s.text('Выполнить SSH-команду'),
                      onTap: _showTerminalCommand,
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.article,
                       title: s.text('Системные логи'),
                      subtitle: 'logread / dmesg',
                      onTap: _showLogs,
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.network_check,
                       title: s.text('Перезапустить сеть'),
                      subtitle: '/etc/init.d/network restart',
                      onTap: () => _serviceAction('network'),
                    ),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.shield,
                       title: s.text('Проверить зависимости'),
                       subtitle: s.text('Установить / сбросить недостающие пакеты'),
                      onTap: () => _showDepsMenu(),
                    ),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.public, title: s.text('Удалённый доступ'), subtitle: s.text('SSH снаружи — безопасный порт'), onTap: _remoteAccessDialog),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.power_settings_new, title: s.text('Перезагрузить'), subtitle: 'reboot', color: theme.colorScheme.error, onTap: _reboot),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.access_time, title: s.text('Синхронизация времени'), subtitle: 'NTP / sysntpd / date', onTap: _syncTime),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.vpn_key, title: s.text('Создать SSH-ключ'), subtitle: s.text('Генерация ED25519 для входа без пароля'), onTap: _generateSshKey),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.router, title: s.text('Проброс портов'), subtitle: 'Firewall redirects', onTap: _showPortForwards),
                    const SizedBox(height: 12),
                    if (_showCard('wol'))
                       _ActionCard(icon: Icons.power_settings_new, title: 'Wake-on-LAN', subtitle: s.text('Разбудить устройство по MAC'),
                         warning: _depMissing('wol') ? s.text('wol/etherwake не установлен') : null,
                        onTap: _showWolDialog),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.schedule, title: s.text('Расписание Wi-Fi'), subtitle: s.text('Авто вкл/выкл по времени'), onTap: _showWifiSchedule),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.thermostat, title: s.text('Температура CPU'), subtitle: s.text('Проверить нагрев роутера'), onTap: _checkTemperature),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.usb, title: s.text('USB-устройства'), subtitle: s.text('Диски, принтеры, модемы'), onTap: _showUsbDevices),
                    const SizedBox(height: 12),
                    if (_showCard('nmap'))
                       _ActionCard(icon: Icons.search, title: s.text('Сканер сети (nmap)'), subtitle: s.text('Найти все устройства в LAN'),
                         warning: _depMissing('nmap') ? s.text('nmap не установлен') : null,
                        onTap: _runNmapScan),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.security, title: 'AdGuard Home', subtitle: s.text('Статус блокировки рекламы'), onTap: _checkAdGuard),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.language, title: s.text('DDNS статус'), subtitle: s.text('Динамический DNS'), onTap: _showDdnsStatus),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.dns, title: 'DNS', subtitle: s.text('Настройка DNS-серверов'), onTap: _showDnsDialog),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.backup, title: s.text('Бэкап конфигурации'), subtitle: s.text('AES-256 экспорт/импорт'), onTap: _showBackupDialog),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.notifications, title: s.text('Уведомления'), subtitle: s.text('мониторинг роутера'), onTap: _setupNotifications),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.security, title: s.text('Безопасность устройства'), subtitle: s.text('Root/эмулятор/отладка'), onTap: _showSecurityStatus),
                    const SizedBox(height: 12),
                    _ActionCard(icon: Icons.screenshot_monitor, title: s.text('Защита экрана'), subtitle: s.text('Разрешить скриншоты'), onTap: _showScreenshotSecurity),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.smart_toy, title: s.text('AI-ассистент'), subtitle: 'OpenRouter / DeepSeek', onTap: _setupAiKey),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.analytics, title: s.text('AI анализ'), subtitle: s.text('Логи/безопасность/производительность'), onTap: _showAiAnalysis),
                    const SizedBox(height: 12),
                     _ActionCard(icon: Icons.info_outline, title: s.text('О приложении'), subtitle: s.text('РыбинскLAB • Усачёв Денис'),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen()))),
                    const SizedBox(height: 12),
                    _ActionCard(
                      icon: Icons.logout,
                       title: s.text('Выйти'),
                       subtitle: s.text('Вернуться к выбору роутера'),
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
             Text(AppStrings.of(context).text('Информация об устройстве'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
             _InfoRow(AppStrings.of(context).text('Модель'), boardInfo!['model']?.toString() ?? boardInfo!['board_name']?.toString() ?? '-'),
             _InfoRow(AppStrings.of(context).text('Система'), boardInfo!['system']?.toString() ?? '-'),
             _InfoRow(AppStrings.of(context).text('Хост'), boardInfo!['hostname']?.toString() ?? '-'),
             _InfoRow(AppStrings.of(context).text('Платформа'), target),
             _InfoRow(AppStrings.of(context).text('Ядро'), boardInfo!['kernel']?.toString() ?? '-'),
            const Divider(height: 24),
             _InfoRow(AppStrings.of(context).text('Дистрибутив'), release['distribution']?.toString() ?? '-'),
             _InfoRow(AppStrings.of(context).text('Версия'), release['version']?.toString() ?? '-'),
             _InfoRow(AppStrings.of(context).text('Ревизия'), release['revision']?.toString() ?? '-'),
             _InfoRow(AppStrings.of(context).text('Описание'), release['description']?.toString() ?? '-'),
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
               Text(AppStrings.of(context).text('Ошибка'), style: theme.textTheme.titleMedium),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
               FilledButton.tonal(onPressed: _load, child: Text(AppStrings.of(context).text('Повторить'))),
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
  final VoidCallback onBrowse; // когда уже подключено
  final VoidCallback? onMount; // подключить (размонтированный накопитель)

  const _UsbTile({required this.d, required this.onBrowse, this.onMount});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = d['type'] ?? '';
    final browsable = d['browsable'] == '1';
    final isStorage = type.contains('флешка') || type.contains('SSD') ||
        type.contains('HDD') || type.contains('накопитель') || type == 'раздел';
    final availKb = int.tryParse(d['avail'] ?? '');
    final usedKb = int.tryParse(d['used'] ?? '');
    final icon = type.contains('модем')
        ? Icons.network_cell
        : isStorage
            ? Icons.storage
            : Icons.usb;
    final parts = <String>[
      type,
      if (d['size'] != null && d['size']!.isNotEmpty && d['size'] != 'USB') d['size']!,
      if (availKb != null) '${AppStrings.of(context).text('свободно')} ${NetworkInterface.formatBytes(availKb * 1024)}',
      if (usedKb != null && usedKb > 0) '${AppStrings.of(context).text('занято')} ${NetworkInterface.formatBytes(usedKb * 1024)}',
      if (d['fstype'] != null && d['fstype']!.isNotEmpty) d['fstype']!,
      if (d['mount'] != null && d['mount'] != '—') d['mount']!,
      if (!browsable && isStorage && d['dev'] != null) AppStrings.of(context).text('не подключён'),
    ];
    final model = d['model'] ?? '';
    final showAction = browsable || (isStorage && d['dev'] != null);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          [if (d['label'] != null && d['label']!.isNotEmpty) d['label']!, d['name']!].join(' '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text([model, if (model.isNotEmpty) ' • ', parts.join(' • ')].join().isEmpty
            ? '—'
            : [if (model.isNotEmpty) model, parts.join(' • ')].join(' • ')),
        // Крупная кнопка-чип справа — сразу видно, что на устройство можно нажать
        // и понятно, что произойдёт («Открыть» vs «Подключить»). Раньше была
        // просто иконка — пользователи её не замечали.
        trailing: showAction
            ? Padding(
                padding: const EdgeInsets.only(left: 4),
                child: FilledButton.tonalIcon(
                  onPressed: browsable ? onBrowse : (onMount ?? onBrowse),
                  icon: Icon(browsable ? Icons.folder_open : Icons.link),
                  label: Text(browsable
                      ? AppStrings.of(context).text('Открыть')
                      : AppStrings.of(context).text('Подключить')),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                ),
              )
            : null,
        onTap: browsable
            ? onBrowse
            : isStorage
                ? (onMount ?? onBrowse)
                : null,
      ),
    );
  }
}
