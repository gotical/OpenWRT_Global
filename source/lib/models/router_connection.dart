class RouterConnection {
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final String? sshKey;
  final bool useKey;
  final bool useHttps;
  final String? fingerprint;

  RouterConnection({
    required this.name,
    required this.host,
    this.port = 22,
    this.username = 'root',
    this.password = '',
    this.sshKey,
    this.useKey = false,
    this.useHttps = false,
    this.fingerprint,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        // Пароль и ssh-ключ НЕ сохраняются в открытом JSON —
        // секреты хранятся отдельно в Android Keystore (flutter_secure_storage).
        'useKey': useKey,
        'useHttps': useHttps,
        'fingerprint': fingerprint,
      };

  factory RouterConnection.fromJson(Map<String, dynamic> json) => RouterConnection(
        name: json['name'] ?? '',
        host: json['host'] ?? '',
        port: json['port'] ?? 22,
        username: json['username'] ?? 'root',
        // Секреты не храним в открытом JSON (они подтягиваются из Keystore в StorageService).
        password: '',
        sshKey: null,
        useKey: json['useKey'] == true,
        useHttps: json['useHttps'] ?? false,
        fingerprint: json['fingerprint']?.toString(),
      );
}
