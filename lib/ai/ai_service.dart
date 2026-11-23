import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../app_state.dart';
import 'ai_client.dart';
import 'ai_models.dart';

/// Per-device AI settings: keys stored on this device and which provider
/// each feature uses. Shared household keys come from the household document.
class AiSettings {
  const AiSettings({this.deviceKeys = const {}, this.features = const {}, this.loaded = false});

  final Map<AiProvider, DeviceAiKey> deviceKeys;
  final Map<AiFeature, AiProvider> features;
  final bool loaded;
}

class AiSettingsNotifier extends Notifier<AiSettings> {
  static const _storage = FlutterSecureStorage();

  @override
  AiSettings build() {
    _load();
    return const AiSettings();
  }

  Future<void> _load() async {
    final keys = <AiProvider, DeviceAiKey>{};
    for (final p in AiProvider.values) {
      try {
        final key = await _storage.read(key: 'ai.key.${p.name}');
        final model = await _storage.read(key: 'ai.model.${p.name}');
        if (key != null && key.isNotEmpty) keys[p] = DeviceAiKey(key: key, model: model ?? defaultAiModels[p]!);
      } catch (_) {}
    }
    final prefs = ref.read(sharedPrefsProvider);
    final features = <AiFeature, AiProvider>{};
    for (final f in AiFeature.values) {
      final name = prefs?.getString('ai.feature.${f.name}');
      final p = AiProvider.values.where((p) => p.name == name).firstOrNull;
      if (p != null) features[f] = p;
    }
    state = AiSettings(deviceKeys: keys, features: features, loaded: true);
  }

  Future<void> setDeviceKey(AiProvider p, String? key, String model) async {
    final keys = {...state.deviceKeys};
    if (key == null || key.isEmpty) {
      await _storage.delete(key: 'ai.key.${p.name}');
      await _storage.delete(key: 'ai.model.${p.name}');
      keys.remove(p);
    } else {
      await _storage.write(key: 'ai.key.${p.name}', value: key);
      await _storage.write(key: 'ai.model.${p.name}', value: model);
      keys[p] = DeviceAiKey(key: key, model: model);
    }
    state = AiSettings(deviceKeys: keys, features: state.features, loaded: true);
  }

  void setFeature(AiFeature f, AiProvider? p) {
    final prefs = ref.read(sharedPrefsProvider);
    final features = {...state.features};
    if (p == null) {
      features.remove(f);
      prefs?.remove('ai.feature.${f.name}');
    } else {
      features[f] = p;
      prefs?.setString('ai.feature.${f.name}', p.name);
    }
    state = AiSettings(deviceKeys: state.deviceKeys, features: features, loaded: true);
  }
}

final aiSettingsProvider = NotifierProvider<AiSettingsNotifier, AiSettings>(AiSettingsNotifier.new);

/// Runs AI requests with the right key: on this device first, else the
/// household's shared key through the server.
class AiService {
  AiService(this._ref);

  final Ref _ref;
  final _direct = DirectAiClient();

  bool _sharedAvailable(AiProvider p) =>
      !_ref.read(isDemoProvider) && (_ref.read(activeHouseholdProvider)?.aiShared.containsKey(p.name) ?? false);

  bool available(AiProvider p) => _ref.read(aiSettingsProvider).deviceKeys.containsKey(p) || _sharedAvailable(p);

  /// Providers with a usable key.
  List<AiProvider> get availableProviders => AiProvider.values.where(available).toList();

  /// Provider for [f]: the chosen one if usable, otherwise the first usable.
  AiProvider? providerFor(AiFeature f) {
    final chosen = _ref.read(aiSettingsProvider).features[f];
    if (chosen != null && available(chosen)) return chosen;
    return availableProviders.firstOrNull;
  }

  bool enabledFor(AiFeature f) => providerFor(f) != null;

  Future<String> run(AiFeature f, AiRequest r) async {
    final p = providerFor(f);
    if (p == null) throw const AiException('no-provider');
    final key = _ref.read(aiSettingsProvider).deviceKeys[p];
    if (key != null) return _direct.run(p, key, r);
    final hid = _ref.read(activeHouseholdProvider)?.id;
    try {
      final res = await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('aiProxy', options: HttpsCallableOptions(timeout: const Duration(seconds: 130)))
          .call<Map<String, dynamic>>({
        'householdId': hid,
        'provider': p.name,
        'prompt': r.prompt,
        'images': [for (final i in r.images) {'mime': i.mime, 'data': base64Encode(i.bytes)}],
        'schema': r.schema,
        'maxTokens': r.maxTokens,
      });
      return res.data['text'] as String? ?? '';
    } on FirebaseFunctionsException catch (e) {
      throw AiException(e.message ?? e.code);
    }
  }

  /// Saves / removes the household-shared key (stored server-side only).
  Future<void> setSharedKey(AiProvider p, String? key, String model) async {
    final hid = _ref.read(activeHouseholdProvider)?.id;
    try {
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('aiSetKey')
          .call({'householdId': hid, 'provider': p.name, 'key': key, 'model': model});
    } on FirebaseFunctionsException catch (e) {
      throw AiException(e.message ?? e.code);
    }
  }
}

final aiServiceProvider = Provider<AiService>((ref) {
  ref.watch(aiSettingsProvider);
  ref.watch(activeHouseholdProvider);
  return AiService(ref);
});
