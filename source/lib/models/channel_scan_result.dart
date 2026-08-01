class ChannelScanResult {
  final int channel;
  final int frequency;
  final int width; // 20, 40, 80, 160 MHz
  final int centerChannel; // center channel for bonded channels
  final int signalStrength; // dBm
  final String ssid;
  final String bssid;
  final String source; // 'phone' or 'router'

  ChannelScanResult({
    required this.channel,
    required this.frequency,
    this.width = 20,
    required this.centerChannel,
    this.signalStrength = -100,
    this.ssid = '',
    this.bssid = '',
    required this.source,
  });

  int get endChannel {
    if (width <= 20) return channel;
    final halfChannels = (width ~/ 20) ~/ 2;
    if (channel <= 14) return channel + halfChannels * 4;
    return centerChannel + halfChannels * 4;
  }

  int get startChannel {
    if (width <= 20) return channel;
    final halfChannels = (width ~/ 20) ~/ 2;
    if (channel <= 14) return channel - halfChannels * 4;
    return centerChannel - halfChannels * 4;
  }

  List<int> get occupiedChannels {
    if (width <= 20) return [channel];
    final channels = <int>[];
    final step = channel <= 14 ? 1 : 4;
    if (channel <= 14) {
      final half = (width ~/ 20) ~/ 2;
      for (int c = channel - half; c <= channel + half; c++) {
        if (c >= 1 && c <= 14) channels.add(c);
      }
    } else {
      final half = (width ~/ 20) ~/ 2;
      final start = centerChannel - half * 4;
      for (int c = start; c <= centerChannel + half * 4; c += 4) {
        channels.add(c);
      }
    }
    return channels;
  }
}

class ChannelAnalysis {
  final String deviceName;
  final String band; // '2.4g', '5g', '6g'
  final int currentChannel;
  final String currentHtMode;
  final List<ChannelScanResult> phoneScans;
  final List<ChannelScanResult> routerScans;
  final Map<int, int> routerInterference; // channel -> network count
  final List<int> recommendedChannels;

  ChannelAnalysis({
    required this.deviceName,
    required this.band,
    this.currentChannel = 0,
    this.currentHtMode = 'HT20',
    this.phoneScans = const [],
    this.routerScans = const [],
    this.routerInterference = const {},
    this.recommendedChannels = const [],
  });

  List<int> get allChannels {
    if (band == '5g') return List.generate(25, (i) => 36 + i * 4).where((c) => c <= 165).toList();
    if (band == '6g') return List.generate(59, (i) => 1 + i * 4).where((c) => c <= 233).toList();
    return List.generate(13, (i) => i + 1);
  }

  Map<int, int> get combinedInterference {
    final result = <int, int>{};
    for (final ch in allChannels) {
      int count = routerInterference[ch] ?? 0;
      final phoneOnCh = phoneScans.where((s) => s.occupiedChannels.contains(ch)).length;
      count += phoneOnCh;
      result[ch] = count;
    }
    return result;
  }

  List<int> findBestChannels({int preferredWidth = 80}) {
    final combined = combinedInterference;
    final sorted = allChannels
        .map((ch) => MapEntry(ch, combined[ch] ?? 0))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return sorted.where((e) {
      final ch = e.key;
      if (band == '5g') {
        if (preferredWidth >= 80) {
          return ch % 8 == 4 || ch % 8 == 0;
        }
        if (preferredWidth >= 40) return ch % 4 == 0;
      }
      return true;
    }).map((e) => e.key).toList();
  }
}