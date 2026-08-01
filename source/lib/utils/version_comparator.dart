class VersionComparator {
  static int compare(String a, String b) {
    final partsA = _parse(a);
    final partsB = _parse(b);

    for (int i = 0; i < 3; i++) {
      final va = i < partsA.length ? partsA[i] : 0;
      final vb = i < partsB.length ? partsB[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }

    // Pre-release suffix
    final preA = _preReleaseWeight(a);
    final preB = _preReleaseWeight(b);
    return preA.compareTo(preB);
  }

  static List<int> _parse(String v) {
    final clean = v.split('-')[0].split('~')[0];
    return clean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
  }

  static int _preReleaseWeight(String v) {
    if (v.contains('-rc') || v.contains('-test')) return -1;
    if (v.contains('-snapshot')) return -2;
    return 0;
  }

  static bool isNewer(String current, String available) {
    return compare(available, current) > 0;
  }
}