class PackageInfo {
  final String name;
  final String version;
  final String? size;
  final String? section;
  final String? description;
  final bool installed;

  PackageInfo({
    required this.name,
    required this.version,
    this.size,
    this.section,
    this.description,
    this.installed = false,
  });
}
