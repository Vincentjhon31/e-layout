// Reads the `crs:` values of an XMP packet (a `.xmp` file, or the packet inside
// a DNG). Values live in attributes of `rdf:Description` and in `crs:` child
// elements (`rdf:Alt` for names, `rdf:Seq` for lists).

import 'package:xml/xml.dart';

import 'crs_map.dart';

const _crsNs = 'http://ns.adobe.com/camera-raw-settings/1.0/';
const _rdfNs = 'http://www.w3.org/1999/02/22-rdf-syntax-ns#';

bool _is(XmlElement e, String local, String ns) =>
    e.name.local == local && e.name.namespaceUri == ns;

List<String> _items(XmlElement list) => [
  for (final li in list.childElements)
    if (_is(li, 'li', _rdfNs)) li.innerText.trim(),
];

void _collect(
  XmlElement desc,
  CrsFields into,
  void Function(XmlElement)? onLook,
) {
  for (final a in desc.attributes) {
    if (a.name.namespaceUri == _crsNs) into.scalars[a.name.local] = a.value;
  }
  for (final e in desc.childElements) {
    if (e.name.namespaceUri != _crsNs) continue;
    final name = e.name.local;
    if (name == 'Look') {
      onLook?.call(e);
      continue;
    }
    final kids = e.childElements.toList();
    if (kids.isEmpty) {
      final t = e.innerText.trim();
      if (t.isNotEmpty) into.scalars[name] = t;
      continue;
    }
    for (final k in kids) {
      if (_is(k, 'Seq', _rdfNs) || _is(k, 'Bag', _rdfNs)) {
        into.seqs[name] = _items(k);
      } else if (_is(k, 'Alt', _rdfNs)) {
        final lis = k.childElements.where((l) => _is(l, 'li', _rdfNs)).toList();
        if (lis.isEmpty) continue;
        final def = lis.firstWhere(
          (l) => l.attributes.any(
            (a) => a.name.qualified == 'xml:lang' && a.value == 'x-default',
          ),
          orElse: () => lis.first,
        );
        final t = def.innerText.trim();
        if (t.isNotEmpty) into.scalars[name] = t;
      }
    }
  }
}

/// Reads [text] as XMP. Returns null if it is not XML or holds no `crs:` data.
ParsedFile? parseXmp(String text) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(text.startsWith('﻿') ? text.substring(1) : text);
  } catch (_) {
    return null;
  }
  final fields = CrsFields();
  XmlElement? lookElement;
  for (final rdf in doc.findAllElements('RDF', namespaceUri: _rdfNs)) {
    for (final d in rdf.childElements) {
      if (!_is(d, 'Description', _rdfNs)) continue;
      _collect(d, fields, (l) => lookElement ??= l);
    }
  }
  if (fields.scalars.isEmpty && fields.seqs.isEmpty && lookElement == null) {
    return null;
  }

  LookInfo? look;
  final le = lookElement;
  if (le != null) {
    final lf = CrsFields();
    for (final d in le.childElements) {
      if (_is(d, 'Description', _rdfNs)) _collect(d, lf, null);
    }
    final tableId = lf['RGBTable'];
    final amount = parseCrsNumber(lf['Amount']);
    look = LookInfo(
      id: lf['UUID'] ?? '',
      name: lf['Name'] ?? '',
      amount: (amount ?? 1).clamp(0.0, 2.0),
      stubbed: isTrue(lf['Stubbed']),
      tableId: tableId,
      tableText: tableId == null
          ? null
          : (lf['Table_$tableId'] ?? fields['Table_$tableId']),
    );
  }
  return ParsedFile(
    fields,
    id: fields['UUID'],
    name: fields['Name'],
    look: look,
  );
}
