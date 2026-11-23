/// Parser for barcodes: plain EAN/UPC and GS1 element strings
/// (GS1-128, GS1 DataMatrix, GS1 QR) including GS1 Digital Link URLs.
///
/// GS1 Application Identifiers we care about:
///   01 GTIN, 10 batch, 15 best before, 17 use by / expiry, 310x net weight (kg)
library;

const String gs1GroupSeparator = '\u001d';

class BarcodeData {
  const BarcodeData({this.gtin, this.bestBefore, this.useBy, this.batch, this.netWeightKg, this.raw = ''});

  /// GTIN normalised to EAN-13 / EAN-8 where possible.
  final String? gtin;
  final DateTime? bestBefore;
  final DateTime? useBy;
  final String? batch;
  final double? netWeightKg;
  final String raw;

  bool get hasDate => bestBefore != null || useBy != null;

  /// In-store codes (prefix 20–29) are not globally unique and cannot be
  /// looked up in public databases.
  bool get isInStoreCode {
    final g = gtin;
    if (g == null || g.length != 13) return false;
    final p = int.tryParse(g.substring(0, 2)) ?? 0;
    return p >= 20 && p <= 29;
  }
}

/// Fixed lengths of AIs (data length, excluding the AI itself).
const Map<String, int> _fixedLength = {
  '00': 18, '01': 14, '02': 14, '11': 6, '12': 6, '13': 6, '15': 6, '16': 6, '17': 6, '20': 2,
};

/// 4-digit AIs with a 6-digit value (measures, 310x–369x).
bool _isMeasureAi(String s) {
  if (s.length < 4) return false;
  final p = int.tryParse(s.substring(0, 2));
  return p != null && p >= 31 && p <= 36 && int.tryParse(s.substring(2, 4)) != null;
}

bool isValidGtin(String code) {
  if (!RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(code)) return false;
  final digits = code.split('').map(int.parse).toList();
  final check = digits.removeLast();
  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    // Weight 3 for the digit right before the check digit, alternating.
    final w = (digits.length - i).isOdd ? 3 : 1;
    sum += digits[i] * w;
  }
  return (10 - sum % 10) % 10 == check;
}

/// GTIN-14/12 → EAN-13 by stripping leading zeros where the result stays valid.
String normalizeGtin(String gtin) {
  var g = gtin;
  if (g.length == 14 && g.startsWith('0')) g = g.substring(1);
  if (g.length == 12) g = '0$g'; // UPC-A → EAN-13
  if (g.length == 13 && g.startsWith('00000')) {
    final ean8 = g.substring(5);
    if (isValidGtin(ean8)) return ean8;
  }
  return g;
}

/// GS1 YYMMDD. DD == 00 means the last day of the month.
/// Century per GS1 GenSpecs 7.12: sliding window of −49…+50 years.
DateTime? parseGs1Date(String yymmdd, {DateTime? now}) {
  if (!RegExp(r'^\d{6}$').hasMatch(yymmdd)) return null;
  final yy = int.parse(yymmdd.substring(0, 2));
  final mm = int.parse(yymmdd.substring(2, 4));
  final dd = int.parse(yymmdd.substring(4, 6));
  if (mm < 1 || mm > 12) return null;
  final current = (now ?? DateTime.now()).year;
  final century = current ~/ 100 * 100;
  var year = century + yy;
  final diff = year - current;
  if (diff > 50) year -= 100;
  if (diff < -49) year += 100;
  final lastDay = DateTime(year, mm + 1, 0).day;
  if (dd > lastDay) return null;
  return DateTime(year, mm, dd == 0 ? lastDay : dd);
}

BarcodeData parseBarcode(String input, {DateTime? now}) {
  var raw = input.trim();
  // Symbology identifiers some scanners prepend, e.g. "]C1", "]d2", "]Q3".
  raw = raw.replaceFirst(RegExp(r'^\][A-Za-z]\d'), '');

  if (RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(raw) && isValidGtin(raw)) {
    return BarcodeData(gtin: normalizeGtin(raw), raw: input);
  }
  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    return _parseDigitalLink(raw, input, now);
  }
  if (raw.startsWith('(')) {
    return _fromAis(_parseHumanReadable(raw), input, now);
  }
  return _fromAis(_parseElementString(raw), input, now);
}

Map<String, String> _parseHumanReadable(String s) {
  final out = <String, String>{};
  for (final m in RegExp(r'\((\d{2,4})\)([^(]*)').allMatches(s)) {
    out[m.group(1)!] = m.group(2)!.trim();
  }
  return out;
}

Map<String, String> _parseElementString(String s) {
  final out = <String, String>{};
  var i = 0;
  while (i < s.length) {
    if (s[i] == gs1GroupSeparator) {
      i++;
      continue;
    }
    final rest = s.substring(i);
    String? ai;
    int? len;
    if (rest.length >= 2 && _fixedLength.containsKey(rest.substring(0, 2))) {
      ai = rest.substring(0, 2);
      len = _fixedLength[ai];
    } else if (_isMeasureAi(rest)) {
      ai = rest.substring(0, 4);
      len = 6;
    } else if (rest.length >= 2 && (rest.startsWith('10') || rest.startsWith('21'))) {
      ai = rest.substring(0, 2);
    } else {
      break; // unknown AI – stop rather than guess
    }
    final start = i + ai.length;
    if (len != null) {
      if (start + len > s.length) break;
      out[ai] = s.substring(start, start + len);
      i = start + len;
    } else {
      final end = s.indexOf(gs1GroupSeparator, start);
      final stop = end == -1 ? s.length : end;
      out[ai] = s.substring(start, stop);
      i = stop;
    }
  }
  return out;
}

BarcodeData _parseDigitalLink(String url, String input, DateTime? now) {
  final uri = Uri.tryParse(url);
  if (uri == null) return BarcodeData(raw: input);
  final ais = <String, String>{};
  final seg = uri.pathSegments;
  for (var i = 0; i + 1 < seg.length; i++) {
    if (RegExp(r'^\d{2,4}$').hasMatch(seg[i])) {
      ais[seg[i]] = Uri.decodeComponent(seg[i + 1]);
      i++;
    }
  }
  uri.queryParameters.forEach((k, v) {
    if (RegExp(r'^\d{2,4}$').hasMatch(k)) ais[k] = v;
  });
  return _fromAis(ais, input, now);
}

BarcodeData _fromAis(Map<String, String> ais, String input, DateTime? now) {
  final gtin = ais['01'] ?? ais['02'];
  double? weight;
  for (final e in ais.entries) {
    if (e.key.length == 4 && e.key.startsWith('310')) {
      final decimals = int.parse(e.key[3]);
      weight = int.parse(e.value) / _pow10(decimals);
    }
  }
  return BarcodeData(
    gtin: gtin == null ? null : normalizeGtin(gtin),
    bestBefore: ais['15'] == null ? null : parseGs1Date(ais['15']!, now: now),
    useBy: ais['17'] == null ? null : parseGs1Date(ais['17']!, now: now),
    batch: ais['10'],
    netWeightKg: weight,
    raw: input,
  );
}

int _pow10(int n) {
  var r = 1;
  for (var i = 0; i < n; i++) {
    r *= 10;
  }
  return r;
}
