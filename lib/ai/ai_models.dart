/// AI with the user's own API keys: providers, features and request shape.
library;

import 'dart:typed_data';

enum AiProvider { gemini, openai, anthropic }

/// What the AI is used for; each feature can use a different provider and model.
enum AiFeature { receipt, recipe, product, date }

/// Fast & cheap models are enough for reading; planning benefits from a smarter one.
enum AiTier { fast, smart }

AiTier tierOf(AiFeature f) => f == AiFeature.recipe ? AiTier.smart : AiTier.fast;

class AiModelInfo {
  const AiModelInfo(this.id, [this.name]);

  final String id;
  final String? name;

  String get label => name == null || name == id ? id : '$name ($id)';
}

/// Picks the recommended model of [tier] from what the key can use.
String? recommendedModel(AiProvider p, AiTier tier, List<AiModelInfo> models) {
  final ids = models.map((m) => m.id).toList();
  if (ids.isEmpty) return null;
  bool has(String id, List<String> any, [List<String> none = const []]) =>
      any.any(id.contains) && !none.any(id.contains);
  String? first(bool Function(String) test) => ids.where(test).firstOrNull;
  switch (p) {
    case AiProvider.anthropic: // the Models API lists the newest first
      return tier == AiTier.fast
          ? first((i) => has(i, ['haiku'])) ?? first((i) => has(i, ['sonnet']))
          : first((i) => has(i, ['opus'])) ?? first((i) => has(i, ['sonnet']));
    case AiProvider.gemini:
      return _geminiPick(ids, tier);
    case AiProvider.openai:
      final sorted = [...ids]..sort((a, b) => b.compareTo(a));
      return tier == AiTier.fast
          ? sorted.where((i) => i.startsWith('gpt-') && i.endsWith('-mini')).firstOrNull
          : sorted.where((i) => i.startsWith('gpt-') && !has(i, ['mini', 'nano', 'audio', 'realtime', 'search'])).firstOrNull;
  }
}

/// Gemini: Google's '-latest' alias when listed, else the newest generation
/// (whatever its tiers are called) – a fast tier (flash/…) or a smart one (pro/…).
String? _geminiPick(List<String> ids, AiTier tier) {
  const skip = ['image', 'tts', 'live', 'embedding', 'audio', 'robotics', 'computer-use', 'native'];
  const smartWords = ['pro', 'ultra', 'neon', 'deep'];
  bool isSmart(String i) => smartWords.any(i.contains);
  double version(String i) => double.tryParse(RegExp(r'gemini-(\d+(?:\.\d+)?)').firstMatch(i)?.group(1) ?? '') ?? 0;
  final usable = ids.where((i) => i.startsWith('gemini') && !skip.any(i.contains)).toList()
    ..sort((a, b) {
      final v = version(b).compareTo(version(a));
      if (v != 0) return v;
      // Stable before preview/experimental, then shorter (base) names first.
      int rank(String i) => RegExp(r'preview|exp').hasMatch(i) ? 1 : 0;
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.length.compareTo(b.length);
    });
  final numbered = usable.where((i) => version(i) > 0).toList();
  final alias = tier == AiTier.fast ? 'gemini-flash-latest' : 'gemini-pro-latest';
  final newest = numbered.isEmpty ? 0 : version(numbered.first);
  final gen = numbered.where((i) => version(i) == newest).toList();
  String? inGen() => tier == AiTier.fast
      ? gen.where((i) => !isSmart(i) && !i.contains('lite')).firstOrNull ?? gen.where((i) => !isSmart(i)).firstOrNull
      : gen.where(isSmart).firstOrNull;
  // The alias follows Google's current stable default (newer generations often
  // start as busy previews); without it, the newest generation.
  if (ids.contains(alias)) return alias;
  return inGen() ??
      usable.where((i) => tier == AiTier.fast ? !isSmart(i) : isSmart(i)).firstOrNull ??
      usable.firstOrNull;
}

/// Other models of [p] to try when the chosen one is overloaded, best first.
List<String> fallbackModels(AiProvider p, AiTier tier, String primary, List<AiModelInfo> models) {
  final ids = models.map((m) => m.id).toSet();
  final other = tier == AiTier.fast ? AiTier.smart : AiTier.fast;
  final candidates = <String?>[
    if (p == AiProvider.gemini) ...[
      if (tier == AiTier.smart) 'gemini-flash-latest',
      'gemini-flash-lite-latest',
      if (tier == AiTier.fast) 'gemini-pro-latest',
      recommendedModel(p, other, models),
    ] else ...[
      recommendedModel(p, other, models),
      if (ids.isEmpty) defaultAiModels[p],
    ],
  ];
  final out = <String>[];
  for (final c in candidates) {
    if (c == null || c == primary || out.contains(c)) continue;
    // The '-latest' aliases are not always listed; everything else must be.
    if (ids.isNotEmpty && !ids.contains(c) && !c.endsWith('-latest')) continue;
    out.add(c);
  }
  return out;
}

const Map<AiProvider, String> defaultAiModels = {
  AiProvider.gemini: 'gemini-flash-latest',
  AiProvider.openai: 'gpt-5-mini',
  AiProvider.anthropic: 'claude-opus-5-5',
};

const Map<AiProvider, String> aiProviderNames = {
  AiProvider.gemini: 'Google Gemini',
  AiProvider.openai: 'OpenAI ChatGPT',
  AiProvider.anthropic: 'Anthropic Claude',
};

/// Where to get a key.
const Map<AiProvider, String> aiKeyUrls = {
  AiProvider.gemini: 'https://aistudio.google.com/apikey',
  AiProvider.openai: 'https://platform.openai.com/api-keys',
  AiProvider.anthropic: 'https://platform.claude.com/settings/keys',
};

class AiImage {
  const AiImage(this.bytes, {this.mime = 'image/jpeg'});

  final Uint8List bytes;
  final String mime;
}

class AiRequest {
  const AiRequest({required this.prompt, this.images = const [], this.schema, this.maxTokens = 16000});

  final String prompt;
  final List<AiImage> images;

  /// JSON schema for structured output. When set, the reply is a JSON string.
  final Map<String, Object?>? schema;
  final int maxTokens;
}

class AiException implements Exception {
  const AiException(this.message, {this.status, this.transient = false});

  final String message;
  final int? status;

  /// Overloaded / rate limited / timed out: worth retrying or another model.
  final bool transient;

  /// Classifies a provider error.
  factory AiException.http(int status, String message) => AiException(
        message,
        status: status,
        transient: const {408, 429, 500, 502, 503, 504, 529}.contains(status) ||
            RegExp(r'overloaded|high demand|unavailable|try again', caseSensitive: false).hasMatch(message),
      );

  @override
  String toString() => message;
}

/// A key stored on this device.
class DeviceAiKey {
  const DeviceAiKey({required this.key, required this.model});

  final String key;
  final String model;
}
