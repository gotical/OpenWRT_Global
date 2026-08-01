import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/router_connection.dart';
import '../services/storage_service.dart';
import '../services/openwrt_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  List<RouterConnection> routers = [];
  bool loading = true;
  late final AnimationController _anim;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(), _host = TextEditingController();
  final _port = TextEditingController(text: '22'), _user = TextEditingController(text: 'root');
  final _pass = TextEditingController(), _keyCtrl = TextEditingController();
  bool _obscure = true;
  bool _useKey = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _load();
  }

  @override
  void dispose() {
    _anim.dispose();
    _name.dispose(); _host.dispose(); _port.dispose(); _user.dispose(); _pass.dispose(); _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await StorageService.loadRouters();
    setState(() { routers = list; loading = false; });
    _anim.forward();
  }

  Future<void> _save(RouterConnection c) async {
    final idx = routers.indexWhere((r) => r.name == c.name && r.host == c.host);
    if (idx >= 0) routers[idx] = c; else routers.add(c);
    await StorageService.saveRouters(routers);
    await StorageService.saveSelectedIndex(idx >= 0 ? idx : routers.length - 1);
    setState(() {});
  }

  Future<void> _del(int i) async {
    routers.removeAt(i);
    await StorageService.saveRouters(routers);
    setState(() {});
  }

  void _open(RouterConnection c, [int? i]) async {
    await StorageService.saveSelectedIndex(i ?? routers.indexOf(c));
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(pageBuilder: (_, __, ___) => HomeScreen(config: c), transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c)),
    );
  }

  void _sheet([RouterConnection? cfg, int? idx]) {
    if (cfg != null) {
      _name.text = cfg.name; _host.text = cfg.host; _port.text = cfg.port.toString();
      _user.text = cfg.username; _pass.text = cfg.password;
      _keyCtrl.text = cfg.sshKey ?? ''; _useKey = cfg.useKey;
    } else {
      _name.clear(); _host.clear(); _port.text = '22'; _user.text = 'root'; _pass.clear(); _keyCtrl.clear(); _useKey = false;
    }
    _obscure = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 24, top: 24, left: 24, right: 24),
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.outlineVariant, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 20),
                Text(cfg == null ? 'Добавить роутер' : 'Изменить', style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Название', prefixIcon: Icon(Icons.label)), validator: (v) => v == null || v.isEmpty ? 'Обязательно' : null),
                const SizedBox(height: 12),
                TextFormField(controller: _host, decoration: const InputDecoration(labelText: 'IP-адрес или домен', prefixIcon: Icon(Icons.router)), validator: (v) => v == null || v.isEmpty ? 'Обязательно' : null),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(flex: 2, child: TextFormField(controller: _port, decoration: const InputDecoration(labelText: 'Порт', prefixIcon: Icon(Icons.dialpad)), keyboardType: TextInputType.number, validator: (v) => v == null || v.isEmpty ? 'Обязательно' : null)),
                  const SizedBox(width: 12),
                  Expanded(flex: 3, child: TextFormField(controller: _user, decoration: const InputDecoration(labelText: 'Пользователь', prefixIcon: Icon(Icons.person)), validator: (v) => v == null || v.isEmpty ? 'Обязательно' : null)),
                ]),
                const SizedBox(height: 12),
                // Переключатель: пароль / ключ
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(ctx).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      SwitchListTile(
                        value: _useKey,
                        onChanged: (v) => setSt(() => _useKey = v),
                        title: const Text('SSH-ключ', style: TextStyle(fontSize: 14)),
                        subtitle: Text(_useKey ? 'Войдите по ключу (PEM)' : 'Войдите по паролю', style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                        secondary: Icon(_useKey ? Icons.vpn_key : Icons.lock),
                      ),
                      if (!_useKey)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: TextFormField(
                            controller: _pass, obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Пароль',
                              prefixIcon: const Icon(Icons.lock, size: 20),
                              suffixIcon: IconButton(icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20), onPressed: () => setSt(() => _obscure = !_obscure)),
                              isDense: true,
                            ),
                            validator: (v) => _useKey ? null : (v == null || v.isEmpty ? 'Обязательно' : null),
                          ),
                        ),
                      if (_useKey)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            children: [
                              TextFormField(
                                controller: _keyCtrl, maxLines: 6,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                decoration: InputDecoration(
                                  labelText: 'Приватный ключ (PEM)',
                                  prefixIcon: const Padding(
                                    padding: EdgeInsets.only(bottom: 80),
                                    child: Icon(Icons.vpn_key, size: 20),
                                  ),
                                  isDense: true,
                                ),
                                validator: (v) => !_useKey ? null : (v == null || v.isEmpty ? 'Вставьте ключ' : null),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('Нажмите "Вставить" чтобы вставить ключ из буфера',
                                        style: TextStyle(fontSize: 11, color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                                  ),
                                  if (_host.text.isNotEmpty && _user.text.isNotEmpty)
                                    TextButton.icon(
                                      onPressed: () => _generateKey(ctx, setSt),
                                      icon: const Icon(Icons.auto_fix_high, size: 16),
                                      label: const Text('Создать ключ', style: TextStyle(fontSize: 12)),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(onPressed: () {
                  if (_form.currentState!.validate()) {
                    _save(RouterConnection(
                      name: _name.text.trim(),
                      host: _host.text.trim(),
                      port: int.tryParse(_port.text) ?? 22,
                      username: _user.text.trim(),
                      password: _pass.text,
                      sshKey: _useKey ? _keyCtrl.text.trim() : null,
                      useKey: _useKey,
                    ));
                    Navigator.pop(ctx);
                  }
                }, child: Text(cfg == null ? 'Добавить' : 'Сохранить')),
              ]),
            ),
          ),
        ),
      ),
);
  }

  Future<void> _generateKey(BuildContext ctx, StateSetter setSt) async {
    // Сначала подключаемся по паролю
    final config = RouterConnection(
      name: _name.text.trim(),
      host: _host.text.trim(),
      port: int.tryParse(_port.text) ?? 22,
      username: _user.text.trim(),
      password: _pass.text,
    );
    final service = OpenWrtService(config);
    setSt(() {});
    try {
      await service.connect();
      final keys = await service.generateAndInstallKey();
      await service.disconnect();
      _keyCtrl.text = keys['private'] ?? '';
      setSt(() {});
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('SSH-ключ создан и установлен на роутер!'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Ошибка: ${e.toString().replaceAll(config.password, '***')}'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 48, 28, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Hero(tag: 'app_icon', child: ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/icon/router_icon.png', width: 80, height: 80))),
                  const SizedBox(height: 24),
                  Text('OPENWRT', style: t.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1)),
                  Text('Global', style: t.textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w300, color: t.colorScheme.primary)),
                  const SizedBox(height: 12),
                  Text('Управляйте роутером', style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ]),
              ),
            ),
            if (loading)
              const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
            else if (routers.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.router_outlined, size: 96, color: t.colorScheme.outline.withValues(alpha: 0.4)),
                    const SizedBox(height: 20),
                    Text('Нет сохранённых роутеров', style: t.textTheme.titleMedium),
                    const SizedBox(height: 24),
                    FilledButton.tonalIcon(onPressed: () => _sheet(), icon: const Icon(Icons.add), label: const Text('Добавить роутер')),
                  ]),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final r = routers[i];
                      return FadeTransition(
                        opacity: _anim,
                        child: SlideTransition(
                          position: Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut)),
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 14),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => _open(r, i),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Row(children: [
                                  CircleAvatar(radius: 26, backgroundColor: t.colorScheme.primaryContainer, child: Icon(r.useKey ? Icons.vpn_key : Icons.router, color: t.colorScheme.onPrimaryContainer)),
                                  const SizedBox(width: 16),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(r.name, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text('${r.username}@${r.host}:${r.port}${r.useKey ? ' (ключ)' : ''}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                                  ])),
                                  IconButton(icon: const Icon(Icons.edit_outlined, size: 20), onPressed: () => _sheet(r, i)),
                                  IconButton(icon: Icon(Icons.delete_outline, size: 20, color: t.colorScheme.error), onPressed: () => _del(i)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: routers.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: routers.isEmpty ? null : FloatingActionButton.extended(onPressed: () => _sheet(), icon: const Icon(Icons.add), label: const Text('Добавить')),
    );
  }
}