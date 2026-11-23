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
  const AiSettings({
    this.deviceKeys = const {},
    this.features = const {},
    this.featureModels = const {},
    this.models = const {},
    this.keyErrors = const {},
    this.loaded = false,
  });

  final Map<AiProvider, DeviceAiKey> deviceKeys;
  final Map<AiFeature, AiProvider> features;

  /// Model chosen for a feature (for its provider); null = recommended.
  final Map<AiFeature, String> featureModels;

  /// Models each key can use, fetched from the provider (cached per session).
  final Map<AiProvider, List<AiModelInfo>> models;

  /// Last key check failure per provider.
  final Map<AiProvider, String> keyErrors;
  final bool loaded;

  AiSettings copyWith({
    Map<AiProvider, DeviceAiKey>? deviceKeys,
    Map<AiFeature, AiProvider>? features,
    Map<AiFeature, String>? featureModels,
    Map<AiProvider, List<AiModelInfo>>? models,
    Map<AiProvider, String>? keyErrors,
  }) =>
      AiSettings(
        deviceKeys: deviceKeys ?? this.deviceKeys,
        features: features ?? this.features,
        featureModels: featureModels ?? this.featureModels,
        models: models ?? this.models,
        keyErrors: keyErrors ?? this.keyErrors,
        loaded: true,
      );
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
    final featureModels = <AiFeature, String>{};
    for (final f in AiFeature.values) {
      final name = prefs?.getString('ai.feature.${f.name}');
      final p = AiProvider.values.where((p) => p.name == name).firstOrNull;
      if (p != null) features[f] = p;
      final m = prefs?.getString('ai.featureModel.${f.name}');
      if (m != null && m.isNotEmpty) featureModels[f] = m;
    }
    state = state.copyWith(deviceKeys: keys, features: features, featureModels: featureModels);
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
    state = state.copyWith(deviceKeys: keys, models: {...state.models}..remove(p));
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
    // A model belongs to its provider: switching provider resets it.
    prefs?.remove('ai.featureModel.${f.name}');
    state = state.copyWith(features: features, featureModels: {...state.featureModels}..remove(f));
  }

  void setFeatureModel(AiFeature f, String? model) {
    final prefs = ref.read(sharedPrefsProvider);
    if (model == null || model.isEmpty) {
      prefs?.remove('ai.featureModel.${f.name}');
      state = state.copyWith(featureModels: {...state.featureModels}..remove(f));
    } else {
      prefs?.setString('ai.featureModel.${f.name}', model);
      state = state.copyWith(featureModels: {...state.featureModels, f: model});
    }
  }

  void setModels(AiProvider p, List<AiModelInfo> models) => state = state.copyWith(
        models: {...state.models, p: models},
        keyErrors: {...state.keyErrors}..remove(p),
      );

  void setKeyError(AiProvider p, String error) => state = state.copyWith(keyErrors: {...state.keyErrors, p: error});
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

  /// Model for [f]: the user's choice, else the recommended one, else the key's.
  String? modelFor(AiFeature f) {
    final p = providerFor(f);
    if (p == null) return null;
    final s = _ref.read(aiSettingsProvider);
    if (s.features[f] == p && s.featureModels[f] != null) return s.featureModels[f];
    return recommendedModel(p, tierOf(f), s.models[p] ?? const []) ??
        s.deviceKeys[p]?.model ??
        _ref.read(activeHouseholdProvider)?.aiShared[p.name];
  }

  /// Fetches (and caches) the models a key can use. With [key] it checks a
  /// key that isn't saved yet.
  Future<List<AiModelInfo>> loadModels(AiProvider p, {String? key}) async {
    final notifier = _ref.read(aiSettingsProvider.notifier);
    try {
      final k = key ?? _ref.read(aiSettingsProvider).deviceKeys[p]?.key;
      List<AiModelInfo> models;
      if (k != null) {
        models = await _direct.listModels(p, k);
      } else {
        final res = await FirebaseFunctions.instanceFor(region: 'europe-west3')
            .httpsCallable('aiListModels')
            .call<Map<String, dynamic>>({'householdId': _ref.read(activeHouseholdProvider)?.id, 'provider': p.name});
        models = [
          for (final m in (res.data['models'] as List? ?? const []))
            if (m is Map) AiModelInfo('${m['id']}', m['name'] as String?),
        ];
      }
      if (key == null) notifier.setModels(p, models);
      return models;
    } on FirebaseFunctionsException catch (e) {
      if (key == null) notifier.setKeyError(p, e.message ?? e.code);
      throw AiException(e.message ?? e.code);
    } catch (e) {
      if (key == null) notifier.setKeyError(p, '$e');
      rethrow;
    }
  }

  Future<String> run(AiFeature f, AiRequest r) async {
    final p = providerFor(f);
    if (p == null) throw const AiException('no-provider');
    final model = modelFor(f);
    final key = _ref.read(aiSettingsProvider).deviceKeys[p];
    if (key != null) return _direct.run(p, DeviceAiKey(key: key.key, model: model ?? key.model), r);
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
        'model': ?model,
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
