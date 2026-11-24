import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_models.dart';

/// Calls the provider directly from the device with a key stored on it.
/// (The household-shared mode goes through the `aiProxy` Cloud Function.)
class DirectAiClient {
  DirectAiClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  Future<String> run(AiProvider provider, DeviceAiKey key, AiRequest r) => switch (provider) {
        AiProvider.anthropic => _anthropic(key, r),
        AiProvider.gemini => _gemini(key, r),
        AiProvider.openai => _openai(key, r),
      };

  /// Models this key can use (also validates the key).
  Future<List<AiModelInfo>> listModels(AiProvider provider, String key) async {
    final (url, headers) = switch (provider) {
      AiProvider.anthropic => (
          Uri.parse('https://api.anthropic.com/v1/models?limit=100'),
          {
            'x-api-key': key,
            'anthropic-version': '2026-10-21',
            if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
          }
        ),
      AiProvider.gemini => (
          Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200'),
          {'x-goog-api-key': key}
        ),
      AiProvider.openai => (Uri.parse('https://api.openai.com/v1/models'), {'authorization': 'Bearer $key'}),
    };
    final res = await _http.get(url, headers: headers).timeout(const Duration(seconds: 20));
    final json = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final err = json is Map ? json['error'] : null;
      throw AiException(err is Map ? '${err['message'] ?? err}' : 'HTTP ${res.statusCode}');
    }
    return parseModelList(provider, json as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> _post(Uri url, Map<String, String> headers, Object body) async {
    final http.Response res;
    try {
      res = await _http
          .post(url, headers: {'content-type': 'application/json', ...headers}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw const AiException('timeout', transient: true);
    } on http.ClientException catch (e) {
      throw AiException(e.message, transient: true);
    }
    Map<String, dynamic> json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw AiException.http(res.statusCode, 'HTTP ${res.statusCode}');
    }
    if (res.statusCode >= 400) {
      final err = json['error'];
      throw AiException.http(res.statusCode, err is Map ? '${err['message'] ?? err}' : 'HTTP ${res.statusCode}');
    }
    return json;
  }

  /// Claude Messages API (raw HTTP – there is no official Dart SDK).
  Future<String> _anthropic(DeviceAiKey key, AiRequest r) async {
    final json = await _post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      {
        'x-api-key': key.key,
        'anthropic-version': '2026-10-21',
        // Re-run a safety-classifier refusal on Anthropic's recommended fallback model.
        'anthropic-beta': 'server-side-fallback-2026-07-01',
        if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
      },
      {
        'model': key.model,
        'max_tokens': r.maxTokens,
        'fallbacks': 'default',
        // Extraction and suggestions are simple tasks: low effort keeps them fast and cheap.
        'output_config': {
          'effort': 'low',
          if (r.schema != null) 'format': {'type': 'json_schema', 'schema': r.schema},
        },
        'messages': [
          {
            'role': 'user',
            'content': [
              for (final i in r.images)
                {
                  'type': 'image',
                  'source': {'type': 'base64', 'media_type': i.mime, 'data': base64Encode(i.bytes)},
                },
              {'type': 'text', 'text': r.prompt},
            ],
          },
        ],
      },
    );
    if (json['stop_reason'] == 'refusal') throw const AiException('refusal');
    return [
      for (final b in (json['content'] as List? ?? const []))
        if (b is Map && b['type'] == 'text') b['text'] as String,
    ].join();
  }

  Future<String> _gemini(DeviceAiKey key, AiRequest r) async {
    final json = await _post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/'
          '${Uri.encodeComponent(key.model)}:generateContent'),
      {'x-goog-api-key': key.key},
      {
        'contents': [
          {
            'role': 'user',
            'parts': [
              for (final i in r.images) {'inline_data': {'mime_type': i.mime, 'data': base64Encode(i.bytes)}},
              {'text': r.prompt},
            ],
          },
        ],
        'generationConfig': {if (r.schema != null) 'responseMimeType': 'application/json'},
      },
    );
    final cand = (json['candidates'] as List?)?.firstOrNull as Map?;
    final parts = cand?['content']?['parts'] as List? ?? const [];
    // Thought summaries are not part of the answer.
    final text = parts.where((p) => p is Map && p['thought'] != true).map((p) => (p as Map)['text'] ?? '').join();
    if (text.trim().isEmpty) {
      final why = cand?['finishReason'] ?? json['promptFeedback']?['blockReason'] ?? 'empty';
      throw AiException('Gemini: $why', transient: why == 'empty' || why == 'MAX_TOKENS');
    }
    return text;
  }

  Future<String> _openai(DeviceAiKey key, AiRequest r) async {
    final json = await _post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      {'authorization': 'Bearer ${key.key}'},
      {
        'model': key.model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': r.prompt},
              for (final i in r.images)
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:${i.mime};base64,${base64Encode(i.bytes)}'},
                },
            ],
          },
        ],
        if (r.schema != null) 'response_format': {'type': 'json_object'},
      },
    );
    return ((json['choices'] as List?)?.firstOrNull as Map?)?['message']?['content'] as String? ?? '';
  }
}

/// Provider model lists → chat/vision models only.
List<AiModelInfo> parseModelList(AiProvider provider, Map<String, dynamic> json) {
  switch (provider) {
    case AiProvider.anthropic:
      return [
        for (final m in (json['data'] as List? ?? const []))
          if (m is Map && m['id'] is String) AiModelInfo(m['id'] as String, m['display_name'] as String?),
      ];
    case AiProvider.gemini:
      return [
        for (final m in (json['models'] as List? ?? const []))
          if (m is Map &&
              (m['supportedGenerationMethods'] as List? ?? const []).contains('generateContent') &&
              '${m['name']}'.contains('gemini') &&
              !RegExp(r'embedding|aqa|imagen|tts|live|image-generation').hasMatch('${m['name']}'))
            AiModelInfo('${m['name']}'.replaceFirst('models/', ''), m['displayName'] as String?),
      ];
    case AiProvider.openai:
      return [
        for (final m in (json['data'] as List? ?? const []))
          if (m is Map &&
              RegExp(r'^(gpt-|o\d|chatgpt-)').hasMatch('${m['id']}') &&
              !RegExp(r'audio|realtime|tts|transcribe|image|search|embedding|instruct|moderation').hasMatch('${m['id']}'))
            AiModelInfo('${m['id']}'),
      ]..sort((a, b) => b.id.compareTo(a.id));
  }
}
