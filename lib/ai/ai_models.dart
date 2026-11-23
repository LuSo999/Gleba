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
      final sorted = [...ids]..sort((a, b) => b.compareTo(a));
      String? pick(List<String> any, [List<String> none = const []]) =>
          sorted.contains('gemini-${any.first}-latest') ? 'gemini-${any.first}-latest' : sorted.where((i) => has(i, any, none)).firstOrNull;
      return tier == AiTier.fast ? pick(['flash'], ['lite', 'image', 'tts', 'live']) : pick(['pro'], ['image', 'tts']);
    case AiProvider.openai:
      final sorted = [...ids]..sort((a, b) => b.compareTo(a));
      return tier == AiTier.fast
          ? sorted.where((i) => i.startsWith('gpt-') && i.endsWith('-mini')).firstOrNull
          : sorted.where((i) => i.startsWith('gpt-') && !has(i, ['mini', 'nano', 'audio', 'realtime', 'search'])).firstOrNull;
  }
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
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A key stored on this device.
class DeviceAiKey {
  const DeviceAiKey({required this.key, required this.model});

  final String key;
  final String model;
}
