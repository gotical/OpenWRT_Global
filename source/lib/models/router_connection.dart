class RouterConnection {
  final String name;
  final String host;
  final int port;
  final String username;
  final String password;
  final String? sshKey;
  final bool useKey;
  final bool useHttps;

  RouterConnection({
    required this.name,
    required this.host,
    this.port = 22,
    this.username = 'root',
    this.password = '',
    this.sshKey,
    this.useKey = false,
    this.useHttps = false,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'sshKey': sshKey,
        'useKey': useKey,
        'useHttps': useHttps,
      };

  factory RouterConnection.fromJson(Map<String, dynamic> json) => RouterConnection(
        name: json['name'] ?? '',
        host: json['host'] ?? '',
        port: json['port'] ?? 22,
        username: json['username'] ?? 'root',
        password: json['password'] ?? '',
        sshKey: json['sshKey']?.toString(),
        useKey: json['useKey'] == true,
        useHttps: json['useHttps'] ?? false,
      );
}