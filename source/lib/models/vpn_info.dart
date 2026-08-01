class VpnInterface {
  final String name;
  final String type; // WireGuard, AmneziaWG, OpenVPN
  final bool up;
  final String? peer;
  final String? endpoint;
  final String? transfer;
  final DateTime? latestHandshake;
  final String? device; // сетевой интерфейс
  final bool enabled; // в конфиге

  VpnInterface({
    required this.name,
    required this.type,
    required this.up,
    this.peer,
    this.endpoint,
    this.transfer,
    this.latestHandshake,
    this.device,
    this.enabled = true,
  });
}
