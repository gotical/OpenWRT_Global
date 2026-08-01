class WifiDevice {
  final String name;
  final bool up;
  final String? mac;
  final String? channel;
  final String? band;
  final int? txPower;
  final String? hwMode;
  final String? htMode;

  WifiDevice({
    required this.name,
    required this.up,
    this.mac,
    this.channel,
    this.band,
    this.txPower,
    this.hwMode,
    this.htMode,
  });
}

class WifiNetwork {
  final String section;
  final String ssid;
  final String device;
  final bool disabled;
  final String? encryption;
  final String? mode;

  WifiNetwork({
    required this.section,
    required this.ssid,
    required this.device,
    required this.disabled,
    this.encryption,
    this.mode,
  });
}

class WifiStation {
  final String mac;
  final String? signal;
  final String? noise;
  final double? rxRate;
  final double? txRate;
  final bool authorized;

  WifiStation({
    required this.mac,
    this.signal,
    this.noise,
    this.rxRate,
    this.txRate,
    this.authorized = false,
  });
}
