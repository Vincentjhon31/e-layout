import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../ui/app_theme.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/page_header.dart';

/// One licence shown in the list: a name, its licence in a few words, and the asset with the full text.
class LicenceEntry {
  const LicenceEntry(this.name, this.licence, this.asset);
  final String name;
  final String licence;
  final String asset;
}

/// What e-Layout's photo editing is built on.
const kEditingLicences = [
  LicenceEntry(
    'LightCraft',
    'MIT OR Apache-2.0',
    'assets/licenses/lightcraft.txt',
  ),
  LicenceEntry(
    'Adobe DNG SDK',
    'DNG SDK License Agreement',
    'assets/licenses/adobe-dng-sdk.txt',
  ),
  LicenceEntry(
    'Hash without Sine',
    'MIT',
    'assets/licenses/hash-without-sine.txt',
  ),
];

/// The bundled font licences, found from the asset list (one text file per family).
Future<List<LicenceEntry>> fontLicences() async {
  try {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths =
        manifest
            .listAssets()
            .where(
              (p) =>
                  p.startsWith('assets/fonts/licenses/') && p.endsWith('.txt'),
            )
            .toList()
          ..sort();
    return [
      for (final p in paths)
        LicenceEntry(
          p
              .split('/')
              .last
              .replaceAll('.txt', '')
              .split('-')
              .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
              .join(' '),
          'Font licence',
          p,
        ),
    ];
  } catch (_) {
    return const [];
  }
}

/// "Licences": the software and fonts e-Layout uses, each with its full licence text.
class LicencesScreen extends StatefulWidget {
  const LicencesScreen({super.key});

  @override
  State<LicencesScreen> createState() => _LicencesScreenState();
}

class _LicencesScreenState extends State<LicencesScreen> {
  List<LicenceEntry> _fonts = const [];

  @override
  void initState() {
    super.initState();
    unawaited(
      fontLicences().then((f) {
        if (mounted) setState(() => _fonts = f);
      }),
    );
  }

  void _open(LicenceEntry e) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => LicenceTextScreen(entry: e)),
    );
  }

  Widget _row(LicenceEntry e, AppColors c) => AppRow(
    label: e.name,
    detail: e.licence,
    trailing: Icon(
      CupertinoIcons.chevron_forward,
      size: 16,
      color: c.secondary,
    ),
    onTap: () => _open(e),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.page,
      child: Column(
        children: [
          const PageHeader(title: 'Licences'),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppGroup(
                          header: 'Photo editing',
                          children: [
                            for (final e in kEditingLicences) _row(e, c),
                          ],
                        ),
                        if (_fonts.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          AppGroup(
                            header: 'Fonts',
                            children: [for (final e in _fonts) _row(e, c)],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The full text of one licence.
class LicenceTextScreen extends StatelessWidget {
  const LicenceTextScreen({super.key, required this.entry});
  final LicenceEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return CupertinoPageScaffold(
      backgroundColor: c.page,
      child: Column(
        children: [
          PageHeader(title: entry.name),
          Expanded(
            child: FutureBuilder<String>(
              future: rootBundle.loadString(entry.asset),
              builder: (context, snap) => SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                      child: Text(
                        snap.data ??
                            (snap.hasError
                                ? "This licence can't be shown."
                                : ''),
                        style: AppText.caption.copyWith(color: c.text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
