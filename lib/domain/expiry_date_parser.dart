/// Extracts expiry dates from OCR text of a package.
///
/// Handles Czech/Slovak/English/German labels and common formats:
/// `12.03.26`, `12/03/2026`, `2026-03-12`, `12 MAR 26`, `12. bře 2026`,
/// `03/2026` (→ end of month), `12.03.` (no year → next occurrence).
library;

import 'models.dart';

class ExpiryCandidate {
  const ExpiryCandidate(this.date, this.score, {this.dateType, required this.matched});

  final DateTime date;

  /// Higher is more likely to be the expiry date.
  final int score;

  /// Type inferred from nearby keywords, if any.
  final DateType? dateType;
  final String matched;

  @override
  String toString() => 'ExpiryCandidate($date, $score, $dateType, "$matched")';
}

const _useByKeywords = [
  'spotřebujte do', 'spotrebujte do', 'spotřeb', 'spotreb', 'use by', 'zu verbrauchen bis',
  'exp', 'expiry', 'expires',
];
const _bestBeforeKeywords = [
  'minimální trvanlivost', 'minimalni trvanlivost', 'minimálna trvanlivosť', 'min. trvanlivost',
  'min.trv', 'trvanlivost', 'trvanlivosť', 'best before', 'bbe', 'bb', 'mhd', 'mindestens haltbar',
  'dmt', 'datum minimální',
];
const _productionKeywords = ['vyrobeno', 'výroba', 'datum výroby', 'produced', 'prod', 'packed', 'baleno'];

const Map<String, int> _months = {
  'jan': 1, 'led': 1, 'feb': 2, 'úno': 2, 'uno': 2, 'mar': 3, 'bře': 3, 'bre': 3, 'mär': 3,
  'apr': 4, 'dub': 4, 'may': 5, 'maj': 5, 'mai': 5, 'kvě': 5, 'kve': 5, 'jun': 6, 'čvn': 6,
  'cvn': 6, 'jul': 7, 'čvc': 7, 'cvc': 7, 'aug': 8, 'srp': 8, 'sep': 9, 'zář': 9, 'zar': 9,
  'oct': 10, 'okt': 10, 'říj': 10, 'rij': 10, 'nov': 11, 'lis': 11, 'dec': 12, 'pro': 12, 'dez': 12,
};

/// Fixes typical OCR confusions inside digit groups (O→0, l/I→1, S→5, B→8).
String _normalizeDigits(String s) => s.replaceAllMapped(
      RegExp(r'(?<=\d)[OoIlSB]|[OoIlSB](?=\d)'),
      (m) => const {'O': '0', 'o': '0', 'I': '1', 'l': '1', 'S': '5', 'B': '8'}[m[0]]!,
    );

int _year(String y) {
  final n = int.parse(y);
  return y.length == 2 ? 2000 + n : n;
}

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1) return null;
  if (d > DateTime(y, m + 1, 0).day) return null;
  return DateTime(y, m, d);
}

List<ExpiryCandidate> findExpiryCandidates(String text, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final norm = _normalizeDigits(text);
  final lower = norm.toLowerCase();
  final found = <ExpiryCandidate>[];
  final taken = <int>{};

  void add(Match m, DateTime? date, [int delta = 0]) {
    if (date == null || taken.contains(m.start)) return;
    taken.add(m.start);
    var score = 10 + delta;
    DateType? type;
    // Look at the 40 chars before the match for a keyword.
    final ctx = lower.substring((m.start - 40).clamp(0, lower.length), m.start);
    if (_useByKeywords.any(ctx.contains)) {
      score += 30;
      type = DateType.useBy;
    } else if (_bestBeforeKeywords.any(ctx.contains)) {
      score += 30;
      type = DateType.bestBefore;
    }
    if (_productionKeywords.any(ctx.contains)) score -= 40;
    final days = date.difference(today).inDays;
    if (days < -30) score -= 30; // most likely a production date
    if (days > 365 * 5) score -= 30;
    if (days >= -1 && days <= 365 * 3) score += 10;
    found.add(ExpiryCandidate(date, score, dateType: type, matched: m[0]!));
  }

  // yyyy-mm-dd / yyyy.mm.dd
  for (final m in RegExp(r'\b(20\d{2})[.\-/ ](\d{1,2})[.\-/ ](\d{1,2})\b').allMatches(norm)) {
    add(m, _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)));
  }
  // dd.mm.yyyy / dd.mm.yy (separators . / - or spaces after dots)
  for (final m in RegExp(r'\b(\d{1,2})\s?[./\-]\s?(\d{1,2})\s?[./\-]\s?(\d{4}|\d{2})\b').allMatches(norm)) {
    add(m, _valid(_year(m[3]!), int.parse(m[2]!), int.parse(m[1]!)));
  }
  // dd MMM yy(yy) – textual month, CZ/EN/DE
  for (final m in RegExp(r'\b(\d{1,2})\.?\s?([a-zA-ZáčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ]{3})[a-zA-Zá-ž]*\.?\s?(\d{4}|\d{2})\b',
          unicode: true)
      .allMatches(norm)) {
    final month = _months[m[2]!.toLowerCase()];
    if (month != null) add(m, _valid(_year(m[3]!), month, int.parse(m[1]!)));
  }
  // mm/yyyy → last day of month
  for (final m in RegExp(r'(?<![\d./\-])(\d{1,2})\s?[./\-]\s?(20\d{2})\b').allMatches(norm)) {
    final mm = int.parse(m[1]!), yy = int.parse(m[2]!);
    if (mm >= 1 && mm <= 12) add(m, DateTime(yy, mm + 1, 0));
  }
  // dd.mm. without a year → next occurrence from today
  for (final m in RegExp(r'\b(\d{1,2})\.\s?(\d{1,2})\.(?!\s?\d)').allMatches(norm)) {
    final d = int.parse(m[1]!), mo = int.parse(m[2]!);
    var date = _valid(today.year, mo, d);
    if (date != null && date.isBefore(today.subtract(const Duration(days: 7)))) {
      date = _valid(today.year + 1, mo, d);
    }
    add(m, date, -5);
  }

  found.sort((a, b) {
    final s = b.score.compareTo(a.score);
    return s != 0 ? s : a.date.compareTo(b.date);
  });
  return found;
}

/// The single most likely expiry date, or null.
ExpiryCandidate? bestExpiryCandidate(String text, {DateTime? now}) {
  final c = findExpiryCandidates(text, now: now);
  return c.isEmpty || c.first.score <= 0 ? null : c.first;
}
