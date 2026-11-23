/// AI with the user's own API keys: providers, features and request shape.
library;

import 'dart:typed_data';

enum AiProvider { gemini, openai, anthropic }

/// What the AI is used for; each feature can use a different provider.
enum AiFeature { receipt, recipe, product, date }

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
