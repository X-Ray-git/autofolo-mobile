import '../utils/storage.dart';

/// LLM 参数配置（翻译 / 摘要各自独立）
class LlmConfig {
  final String model;
  final bool thinking;
  final String reasoningEffort; // high / max
  final double temperature;
  final int maxTokens;
  final int concurrency;

  const LlmConfig({
    required this.model,
    required this.thinking,
    required this.reasoningEffort,
    required this.temperature,
    required this.maxTokens,
    this.concurrency = 16,
  });

  static const _translatePrefix = 'llm_translate_';
  static const _summaryPrefix = 'llm_summary_';

  // ─── 默认值 ───

  static const LlmConfig translateDefault = LlmConfig(
    model: 'deepseek-v4-flash',
    thinking: false,
    reasoningEffort: 'high',
    temperature: 0.2,
    maxTokens: 131072,
    concurrency: 16,
  );

  static const LlmConfig summaryDefault = LlmConfig(
    model: 'deepseek-v4-pro',
    thinking: true,
    reasoningEffort: 'high',
    temperature: 0.2,
    maxTokens: 2048,
    concurrency: 16,
  );

  static const LlmConfig filterDefault = LlmConfig(
    model: 'deepseek-v4-pro',
    thinking: false,
    reasoningEffort: 'high',
    temperature: 0.1,
    maxTokens: 2048,
    concurrency: 16,
  );

  static const _filterPrefix = 'llm_filter_';

  static LlmConfig loadFilter() => _load(_filterPrefix, filterDefault);
  static Future<void> saveFilter(LlmConfig c) => _save(_filterPrefix, c);
  static void resetFilter() => _clear(_filterPrefix);

  // ─── 读写 ───

  static LlmConfig loadTranslate() => _load(
        _translatePrefix,
        translateDefault,
      );
  static LlmConfig loadSummary() => _load(_summaryPrefix, summaryDefault);

  static Future<void> saveTranslate(LlmConfig c) =>
      _save(_translatePrefix, c);
  static Future<void> saveSummary(LlmConfig c) => _save(_summaryPrefix, c);

  static void resetTranslate() => _clear(_translatePrefix);
  static void resetSummary() => _clear(_summaryPrefix);

  // ─── 构建 API 请求体 ───

  Map<String, dynamic> toRequestBody() {
    final body = <String, dynamic>{
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
    if (thinking) {
      body['thinking'] = {'type': 'enabled'};
      body['reasoning_effort'] = reasoningEffort;
    }
    return body;
  }

  // ─── 内部 ───

  static LlmConfig _load(String prefix, LlmConfig defaults) {
    return LlmConfig(
      model:
          (GStorage.setting.get('${prefix}model') as String?) ?? defaults.model,
      thinking: (GStorage.setting.get('${prefix}thinking') as bool?) ??
          defaults.thinking,
      reasoningEffort:
          (GStorage.setting.get('${prefix}reasoning_effort') as String?) ??
              defaults.reasoningEffort,
      temperature:
          (GStorage.setting.get('${prefix}temperature') as double?) ??
              defaults.temperature,
      maxTokens:
          (GStorage.setting.get('${prefix}max_tokens') as int?) ??
              defaults.maxTokens,
      concurrency:
          (GStorage.setting.get('${prefix}concurrency') as int?) ??
              defaults.concurrency,
    );
  }

  static Future<void> _save(String prefix, LlmConfig c) async {
    await GStorage.setting.putAll({
      '${prefix}model': c.model,
      '${prefix}thinking': c.thinking,
      '${prefix}reasoning_effort': c.reasoningEffort,
      '${prefix}temperature': c.temperature,
      '${prefix}max_tokens': c.maxTokens,
      '${prefix}concurrency': c.concurrency,
    });
  }

  static void _clear(String prefix) {
    GStorage.setting.delete('${prefix}model');
    GStorage.setting.delete('${prefix}thinking');
    GStorage.setting.delete('${prefix}reasoning_effort');
    GStorage.setting.delete('${prefix}temperature');
    GStorage.setting.delete('${prefix}max_tokens');
    GStorage.setting.delete('${prefix}concurrency');
  }
}
