// Versions and the download page's latest.json.

List<int> _parts(String v) {
  var s = v.trim();
  if (s.startsWith('v') || s.startsWith('V')) s = s.substring(1);
  final plus = s.indexOf('+');
  final main = plus < 0 ? s : s.substring(0, plus);
  final build = plus < 0 ? '0' : s.substring(plus + 1);
  int lead(String x) => int.tryParse(RegExp(r'^\d+').firstMatch(x.trim())?.group(0) ?? '') ?? 0;
  final p = main.split('.').map(lead).toList();
  while (p.length < 3) {
    p.add(0);
  }
  return [p[0], p[1], p[2], lead(build)];
}

/// Negative when [a] is older than [b], 0 when equal, positive when newer.
/// '1.10.0+1' > '1.9.0+9'; 'v1.0.0+2' > '1.0.0+1'; '1.0.0' == '1.0.0+0'.
int compareVersions(String a, String b) {
  final x = _parts(a), y = _parts(b);
  for (var i = 0; i < 4; i++) {
    final c = x[i].compareTo(y[i]);
    if (c != 0) return c;
  }
  return 0;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.build,
    this.date,
    this.whatsNew = const [],
    required this.downloadUrl,
    required this.pageUrl,
    this.sha256,
    this.size,
  });

  final String version;
  final int build;
  final String? date;
  final List<String> whatsNew;
  final String downloadUrl;
  final String pageUrl;
  final String? sha256;
  final int? size;

  bool isNewerThan(String version, int build) => compareVersions('${this.version}+${this.build}', '$version+$build') > 0;

  /// The entry for [platformKey] ('android' or 'windows'); null when missing.
  static ReleaseInfo? fromLatest(Object? latestJson, String platformKey) {
    if (latestJson is! Map) return null;
    final e = latestJson[platformKey];
    if (e is! Map) return null;
    final version = e['version'];
    if (version is! String || version.isEmpty) return null;
    final page = latestJson['page'] is String ? latestJson['page'] as String : 'https://pio.bongabong.gov.ph/download/';
    String? str(String k) => e[k] is String && (e[k] as String).isNotEmpty ? e[k] as String : null;
    final build = e['build'];
    final size = e['size'];
    return ReleaseInfo(
      version: version,
      build: build is int ? build : int.tryParse('$build') ?? 0,
      date: str('date'),
      whatsNew: [
        if (e['whats_new'] is List)
          for (final i in e['whats_new'] as List)
            if (i is String && i.trim().isNotEmpty) i,
      ],
      downloadUrl: str('download') ?? str('url') ?? page,
      pageUrl: page,
      sha256: str('sha256')?.toLowerCase(),
      size: size is int ? size : null,
    );
  }
}

/// Flutter web's version.json: {"version":"1.0.1","build_number":"2",...}.
/// True when the deployed site is newer than the running code.
bool isNewerDeployment(Object? versionJson, String version, int build) {
  if (versionJson is! Map) return false;
  final v = versionJson['version'];
  if (v is! String) return false;
  final b = int.tryParse('${versionJson['build_number']}') ?? 0;
  return compareVersions('$v+$b', '$version+$build') > 0;
}
