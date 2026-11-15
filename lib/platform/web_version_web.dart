import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../online/net.dart';
import 'web_version.dart';

WebVersionWatcher? createWebVersionWatcher(Net net) => _BrowserWatcher(net);

class _BrowserWatcher implements WebVersionWatcher {
  _BrowserWatcher(this._net);
  final Net _net;

  @override
  Future<Object?> deployedVersionJson() {
    // Relative to the page: /app/version.json on the site.
    final uri = Uri.base.resolve('version.json?t=${DateTime.now().millisecondsSinceEpoch}');
    return _net.getJson(uri);
  }

  @override
  void reload() {
    unawaited(_refreshWorkersThenReload());
  }

  Future<void> _refreshWorkersThenReload() async {
    try {
      final regs = (await web.window.navigator.serviceWorker.getRegistrations().toDart).toDart;
      for (final r in regs) {
        await r.update().toDart;
      }
    } catch (_) {
      // No service worker, or the browser refused: reload anyway.
    } finally {
      web.window.location.reload();
    }
  }
}
