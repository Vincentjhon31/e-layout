/// Progress of one "Save photos" run.
class ExportJob {
  ExportJob(this.total);

  final int total;

  /// Photos finished (saved or failed).
  int done = 0;

  /// 1-based number of the photo being saved.
  int current = 0;
  String currentName = '';
  bool cancelRequested = false;
  int saved = 0;
  int bytes = 0;
  final List<String> failed = [];

  double get fraction => total == 0 ? 0 : done / total;
}

/// app.js plural(): "1 photo", "12 photos".
String plural(int n, String one, String many) => '$n ${n == 1 ? one : many}';

/// app.js formatBytes().
String formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024, mb = 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
  return '${(bytes / mb).toStringAsFixed(1)} MB';
}

/// Names in the order a person expects: "IMG 2" before "IMG 10", case ignored.
int naturalCompare(String a, String b) {
  final ra = RegExp(r'\d+|\D+').allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final rb = RegExp(r'\d+|\D+').allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final x = ra[i], y = rb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = nx != null && ny != null ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}

/// "a.jpg, b.jpg and 2 more" for the final line.
String failedList(List<String> failed) {
  final shown = failed.take(3).join(', ');
  return failed.length > 3 ? '$shown and ${failed.length - 3} more' : shown;
}
