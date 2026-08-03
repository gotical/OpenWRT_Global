class OpenWrtCapabilities {
  final String version;
  final String codename;
  final String target;
  final int majorVersion;
  final bool hasFirewall4;
  final bool hasNftables;
  final bool hasDsa;
  final bool hasRpcd;
  final bool hasUbus;
  final bool hasLuci;
  final bool hasIwinfo;
  final bool hasIw;

  OpenWrtCapabilities({
    this.version = '',
    this.codename = '',
    this.target = '',
    this.majorVersion = 0,
    this.hasFirewall4 = false,
    this.hasNftables = false,
    this.hasDsa = false,
    this.hasRpcd = false,
    this.hasUbus = false,
    this.hasLuci = false,
    this.hasIwinfo = false,
    this.hasIw = false,
  });

  bool get hasFirewall3 => !hasFirewall4;
  bool get hasIptables => !hasNftables;

  String get firewallTool => hasFirewall4 ? 'fw4' : 'fw3';
  String get iptablesCmd => hasNftables ? 'nft' : 'iptables';
  String get switchTool => hasDsa ? 'dsa' : 'swconfig';
  String get wifiTool => hasIwinfo ? 'iwinfo' : 'iw';

  bool get isOpenWrt19 => majorVersion == 19;
  bool get isOpenWrt21 => majorVersion == 21;
  bool get isOpenWrt22 => majorVersion == 22;
  bool get isOpenWrt23 => majorVersion == 23;
  bool get isOpenWrt24 => majorVersion >= 24;

  static OpenWrtCapabilities fromRelease(String raw) {
    final lines = raw.split('\n');
    String v = '', code = '', t = '';
    for (final line in lines) {
      final parts = line.split("=");
      if (parts.length < 2) continue;
      final key = parts[0].trim();
      final val = parts.sublist(1).join('=').trim().replaceAll("'", '');
      if (key == 'DISTRIB_RELEASE') v = val;
      if (key == 'DISTRIB_CODENAME') code = val;
      if (key == 'DISTRIB_TARGET') t = val;
    }
    final major = int.tryParse(v.split('.')[0]) ?? 0;
    return OpenWrtCapabilities(
      version: v,
      codename: code,
      target: t,
      majorVersion: major,
      hasFirewall4: major >= 23,
      hasNftables: major >= 22,
      hasDsa: major >= 21,
      hasRpcd: major >= 19,
      hasUbus: true,
      hasLuci: true,
      hasIwinfo: major < 22,
      hasIw: major >= 22,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'codename': codename,
        'target': target,
        'majorVersion': majorVersion,
        'hasFirewall4': hasFirewall4,
        'hasNftables': hasNftables,
        'hasDsa': hasDsa,
        'hasRpcd': hasRpcd,
        'hasUbus': hasUbus,
        'hasLuci': hasLuci,
        'hasIwinfo': hasIwinfo,
        'hasIw': hasIw,
      };
}