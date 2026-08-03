import 'package:flutter/widgets.dart';

class AppStrings {
  final Locale locale;

  const AppStrings(this.locale);

  static AppStrings of(BuildContext context) =>
      AppStrings(Localizations.localeOf(context));

  static const supportedLocales = [
    Locale('ru'),
    Locale('uk'),
    Locale('kk'),
    Locale('be'),
  ];

  static const languageNames = {
    'ru': 'Русский',
    'uk': 'Українська',
    'kk': 'Қазақша',
    'be': 'Беларуская',
  };

  String get language => _text('language');
  String get about => _text('about');
  String get overview => _text('overview');
  String get network => _text('network');
  String get wifi => _text('wifi');
  String get vpn => _text('vpn');
  String get clients => _text('clients');
  String get packages => _text('packages');
  String get system => _text('system');
  String get addRouter => _text('add_router');
  String get save => _text('save');
  String get cancel => _text('cancel');
  String get close => _text('close');
  String get name => _text('name');
  String get host => _text('host');
  String get port => _text('port');
  String get username => _text('username');
  String get password => _text('password');
  String get sshKey => _text('ssh_key');
  String get login => _text('login');
  String get noRouters => _text('no_routers');
  String get developer => _text('developer');
  String get sourceCode => _text('source_code');
  String get features => _text('features');
  String get acknowledgements => _text('acknowledgements');
  String get version => _text('version');

  String _text(String key) {
    final language = locale.languageCode;
    return _translations[language]?[key] ?? _translations['ru']![key] ?? key;
  }

  static const Map<String, Map<String, String>> _translations = {
    'ru': {
      'language': 'Язык', 'about': 'О приложении', 'overview': 'Обзор',
      'network': 'Сеть', 'wifi': 'Wi-Fi', 'vpn': 'VPN', 'clients': 'Клиенты',
      'packages': 'Пакеты', 'system': 'Система', 'add_router': 'Добавить роутер',
      'save': 'Сохранить', 'cancel': 'Отмена', 'close': 'Закрыть',
      'name': 'Название', 'host': 'Хост или IP', 'port': 'Порт',
      'username': 'Пользователь', 'password': 'Пароль', 'ssh_key': 'SSH-ключ',
      'login': 'Войти', 'no_routers': 'Роутеры ещё не добавлены',
      'developer': 'Разработчик', 'source_code': 'Исходный код',
      'features': 'Возможности', 'acknowledgements': 'Благодарности',
      'version': 'Версия',
    },
    'uk': {
      'language': 'Мова', 'about': 'Про застосунок', 'overview': 'Огляд',
      'network': 'Мережа', 'wifi': 'Wi-Fi', 'vpn': 'VPN', 'clients': 'Клієнти',
      'packages': 'Пакети', 'system': 'Система', 'add_router': 'Додати роутер',
      'save': 'Зберегти', 'cancel': 'Скасувати', 'close': 'Закрити',
      'name': 'Назва', 'host': 'Хост або IP', 'port': 'Порт',
      'username': 'Користувач', 'password': 'Пароль', 'ssh_key': 'SSH-ключ',
      'login': 'Увійти', 'no_routers': 'Роутери ще не додані',
      'developer': 'Розробник', 'source_code': 'Вихідний код',
      'features': 'Можливості', 'acknowledgements': 'Подяки', 'version': 'Версія',
    },
    'kk': {
      'language': 'Тіл', 'about': 'Қолданба туралы', 'overview': 'Шолу',
      'network': 'Желі', 'wifi': 'Wi-Fi', 'vpn': 'VPN', 'clients': 'Клиенттер',
      'packages': 'Пакеттер', 'system': 'Жүйе', 'add_router': 'Роутер қосу',
      'save': 'Сақтау', 'cancel': 'Бас тарту', 'close': 'Жабу',
      'name': 'Атауы', 'host': 'Хост немесе IP', 'port': 'Порт',
      'username': 'Пайдаланушы', 'password': 'Құпиясөз', 'ssh_key': 'SSH-кілт',
      'login': 'Кіру', 'no_routers': 'Роутерлер әлі қосылмаған',
      'developer': 'Әзірлеуші', 'source_code': 'Бастапқы код',
      'features': 'Мүмкіндіктер', 'acknowledgements': 'Алғыс', 'version': 'Нұсқа',
    },
    'be': {
      'language': 'Мова', 'about': 'Пра праграму', 'overview': 'Агляд',
      'network': 'Сетка', 'wifi': 'Wi-Fi', 'vpn': 'VPN', 'clients': 'Кліенты',
      'packages': 'Пакеты', 'system': 'Сістэма', 'add_router': 'Дадаць роутар',
      'save': 'Захаваць', 'cancel': 'Скасаваць', 'close': 'Закрыць',
      'name': 'Назва', 'host': 'Хост або IP', 'port': 'Порт',
      'username': 'Карыстальнік', 'password': 'Пароль', 'ssh_key': 'SSH-ключ',
      'login': 'Увайсці', 'no_routers': 'Роутары яшчэ не дададзены',
      'developer': 'Распрацоўшчык', 'source_code': 'Зыходны код',
      'features': 'Магчымасці', 'acknowledgements': 'Падзякі', 'version': 'Версія',
    },
  };
}
