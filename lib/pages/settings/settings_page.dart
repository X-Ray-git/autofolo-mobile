import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../common/constants/constants.dart';
import '../../common/widgets/feedback_toast.dart';
import '../../services/account_service.dart';
import '../../services/article_filter_service.dart';
import '../../services/llm_config.dart';
import '../../services/translation_service.dart';
import '../../utils/security_utils.dart';
import '../../utils/storage.dart';

/// 设置页 — Token 输入
class SettingsPage extends StatefulWidget {
  final bool showAppBar;

  const SettingsPage({super.key, this.showAppBar = true});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AccountService _accountService;

  final _tokenController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _sessionIdController = TextEditingController();
  final _deepseekApiKeyController = TextEditingController();
  final _readSyncWindowDaysController = TextEditingController();
  bool _obscureToken = true;
  bool _obscureClientId = true;
  bool _obscureSessionId = true;
  bool _obscureDeepseekKey = true;
  late String _badgeStrategy;
  late bool _articleLazyLoading;

  @override
  void initState() {
    super.initState();
    _accountService = AccountService.instance;

    // 填入已保存的值
    _tokenController.text = _accountService.sessionToken ?? '';
    _clientIdController.text = _accountService.clientId ?? '';
    _sessionIdController.text = _accountService.sessionId ?? '';
    _deepseekApiKeyController.text = TranslationService.getApiKey() ?? '';
    final readWindowDays = GStorage.setting.get(
      StorageKeys.readSyncWindowDays,
      defaultValue: AppConstants.defaultReadSyncWindowDays,
    );
    _readSyncWindowDaysController.text = readWindowDays.toString();
    _badgeStrategy = GStorage.setting.get(
      StorageKeys.badgeStrategy,
      defaultValue: 'unread_count',
    );
    _articleLazyLoading = GStorage.setting.get(
      StorageKeys.articleLazyLoading,
      defaultValue: false,
    ) as bool;
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _clientIdController.dispose();
    _sessionIdController.dispose();
    _deepseekApiKeyController.dispose();
    _readSyncWindowDaysController.dispose();
    super.dispose();
  }

  void _save() {
    final token = SecurityUtils.normalizeCredential(_tokenController.text);
    final clientId = SecurityUtils.normalizeCredential(
      _clientIdController.text,
    );
    final sessionId = SecurityUtils.normalizeCredential(
      _sessionIdController.text,
    );

    if (token.isEmpty || clientId.isEmpty || sessionId.isEmpty) {
      AppFeedback.warning('配置未保存', '请填写全部三项');
      return;
    }

    if (!SecurityUtils.isSafeCookieValue(token) ||
        !SecurityUtils.isSafeHeaderValue(clientId) ||
        !SecurityUtils.isSafeHeaderValue(sessionId)) {
      AppFeedback.error('配置未保存', '输入格式不合法，请检查是否包含换行或特殊分隔符');
      return;
    }

    _accountService.saveTokens(
      sessionToken: token,
      clientId: clientId,
      sessionId: sessionId,
    );

    // 保存 DeepSeek API key
    final deepseekKey = _deepseekApiKeyController.text.trim();
    if (deepseekKey.isNotEmpty) {
      TranslationService.setApiKey(deepseekKey);
      GStorage.setting.put('deepseek_api_key', deepseekKey);
    }

    final readWindowDays = int.tryParse(
      _readSyncWindowDaysController.text.trim(),
    );
    if (readWindowDays == null || readWindowDays < 1) {
      AppFeedback.warning('配置未保存', '已读拉取窗口请填写大于 0 的天数');
      return;
    }
    GStorage.setting.put(StorageKeys.readSyncWindowDays, readWindowDays);
    GStorage.setting.put(StorageKeys.badgeStrategy, _badgeStrategy);
    GStorage.setting.put(StorageKeys.articleLazyLoading, _articleLazyLoading);

    AppFeedback.success('配置已保存', '设置已更新');
  }

  void _clear() {
    _tokenController.clear();
    _clientIdController.clear();
    _sessionIdController.clear();
    _deepseekApiKeyController.clear();
    _accountService.clearTokens();
    GStorage.setting.delete('deepseek_api_key');

    AppFeedback.info('配置已清除', '已移除本地配置');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('设置'),
              centerTitle: true,
              backgroundColor: colorScheme.surface.withValues(alpha: 0.7),
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(color: Colors.transparent),
                ),
              ),
            )
          : null,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(context).top + 8,
          16,
          MediaQuery.paddingOf(context).bottom + kBottomNavigationBarHeight + 32,
        ),
        children: [
          // 登录状态
          Obx(
            () => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      _accountService.isLoggedIn.value
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: _accountService.isLoggedIn.value
                          ? colorScheme.primary
                          : colorScheme.error,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _accountService.isLoggedIn.value
                          ? '已配置 Token'
                          : '未配置 Token',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _accountService.isLoggedIn.value
                            ? colorScheme.primary
                            : colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Token 输入
          Text(
            'Folo API 认证',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '从 Folo Web 应用的 Cookie 中获取',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _tokenController,
            decoration: InputDecoration(
              labelText: 'Session Token',
              hintText: 'T9VlefMC...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureToken ? '显示' : '隐藏',
                onPressed: () {
                  setState(() => _obscureToken = !_obscureToken);
                },
                icon: Icon(
                  _obscureToken ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            obscureText: _obscureToken,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _clientIdController,
            decoration: InputDecoration(
              labelText: 'Client ID',
              hintText: 'YlxGJddT...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureClientId ? '显示' : '隐藏',
                onPressed: () {
                  setState(() => _obscureClientId = !_obscureClientId);
                },
                icon: Icon(
                  _obscureClientId ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            obscureText: _obscureClientId,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _sessionIdController,
            decoration: InputDecoration(
              labelText: 'Session ID',
              hintText: 'TepZonTA...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureSessionId ? '显示' : '隐藏',
                onPressed: () {
                  setState(() => _obscureSessionId = !_obscureSessionId);
                },
                icon: Icon(
                  _obscureSessionId ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            obscureText: _obscureSessionId,
            textInputAction: TextInputAction.next,
          ),

          const SizedBox(height: 32),

          // 通知与角标
          Text(
            '通知与角标',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                color: colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            '控制桌面图标角标显示',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<String>(
            value: _badgeStrategy,
            decoration: const InputDecoration(
              labelText: '桌面角标显示规则',
              border: OutlineInputBorder(),
              helperText: '退到后台后图标右上角的红点行为',
            ),
            items: const [
              DropdownMenuItem(value: 'unread_count', child: Text('显示未读数量')),
              DropdownMenuItem(value: 'dot_only', child: Text('仅显示红点')),
              DropdownMenuItem(value: 'off', child: Text('关闭角标')),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _badgeStrategy = val);
            },
          ),

          const SizedBox(height: 32),

          // 渲染与性能
          Text(
            '渲染与性能',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
                color: colorScheme.onSurface),
          ),
          const SizedBox(height: 16),

          SwitchListTile(
            title: const Text('正文 DOM 懒加载'),
            subtitle: const Text('动态按需渲染视窗内的 HTML 节点'),
            value: _articleLazyLoading,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) {
              setState(() => _articleLazyLoading = val);
            },
            secondary: IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('关于正文 DOM 懒加载'),
                    content: const Text(
                      '开启后：\n使用 SliverList 机制进行视窗内懒加载。可以显著降低多图长文的首帧渲染时间，避免内存占用过高导致崩溃。\n\n'
                      '副作用：\n由于系统无法提前预知未渲染节点的高度，会导致页面顶部的阅读进度条出现跳动、不准确或无法达到 100%。\n\n'
                      '关闭时：\n一次性全量构建所有节点，进度条绝对精准。现代设备推荐关闭。'
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('我知道了'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 32),

          // DeepSeek 翻译服务
          Text(
            '翻译服务设置',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '使用 DeepSeek API 为文章提供翻译功能',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _deepseekApiKeyController,
            decoration: InputDecoration(
              labelText: 'DeepSeek API Key',
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscureDeepseekKey ? '显示' : '隐藏',
                onPressed: () {
                  setState(() => _obscureDeepseekKey = !_obscureDeepseekKey);
                },
                icon: Icon(
                  _obscureDeepseekKey ? Icons.visibility : Icons.visibility_off,
                ),
              ),
            ),
            obscureText: _obscureDeepseekKey,
            textInputAction: TextInputAction.done,
          ),

          const SizedBox(height: 16),

          TextField(
            controller: _readSyncWindowDaysController,
            decoration: const InputDecoration(
              labelText: '已读拉取窗口（天）',
              hintText: '2',
              border: OutlineInputBorder(),
              helperText: '后台静默拉取最近已读文章的时间范围',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),

          const SizedBox(height: 24),

          // 按钮
          Row(
            children: [
              Expanded(
                child: FilledButton(onPressed: _save, child: const Text('保存')),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _clear,
                  child: const Text('清除'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 48),

          // ─── LLM 参数配置 ─────────────────────

          _LlmConfigCard(
            title: '翻译 LLM 参数',
            defaultConfig: LlmConfig.translateDefault,
            loadConfig: LlmConfig.loadTranslate,
            saveConfig: LlmConfig.saveTranslate,
            resetConfig: LlmConfig.resetTranslate,
          ),
          const SizedBox(height: 16),
          _LlmConfigCard(
            title: '摘要 LLM 参数',
            defaultConfig: LlmConfig.summaryDefault,
            loadConfig: LlmConfig.loadSummary,
            saveConfig: LlmConfig.saveSummary,
            resetConfig: LlmConfig.resetSummary,
          ),

          const SizedBox(height: 12),

          _LlmConfigCard(
            title: '过滤 LLM 参数',
            defaultConfig: LlmConfig.filterDefault,
            loadConfig: LlmConfig.loadFilter,
            saveConfig: LlmConfig.saveFilter,
            resetConfig: LlmConfig.resetFilter,
          ),

          const SizedBox(height: 12),

          // AI 过滤 Prompt
          _FilterPromptCard(),

          const SizedBox(height: 24),

          // 关于
          Text(
            '关于',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'autofolo v1.0.0',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '基于 Folo API 的 RSS 信息流浏览器。'
                    '仅支持 Android 平台。',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Folo API: api.folo.is',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.7,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 过滤 Prompt 卡片 ───────────────────

class _FilterPromptCard extends StatefulWidget {
  @override
  State<_FilterPromptCard> createState() => _FilterPromptCardState();
}

class _FilterPromptCardState extends State<_FilterPromptCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ArticleFilterService.getPrompt());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      AppFeedback.warning('Prompt 不能为空', '请保留至少一条过滤规则');
      return;
    }
    await ArticleFilterService.setPrompt(text);
    if (mounted) AppFeedback.success('Prompt 已保存', '新过滤将从下次请求生效');
  }

  void _reset() {
    ArticleFilterService.resetPrompt();
    _controller.text = ArticleFilterService.getPrompt();
    setState(() {});
    AppFeedback.success('已重置', 'Prompt 恢复为默认');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: ExpansionTile(
        title: const Text('AI 过滤 Prompt',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('自定义文章过滤规则（LLM 判定）'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  maxLines: 12,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: '输入过滤规则...',
                    helperText:
                        '${_controller.text.split('\n').length} 行',
                    helperStyle: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('保存'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _reset,
                      child: const Text('默认'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── LLM 参数配置卡片 ────────────────────

class _LlmConfigCard extends StatefulWidget {
  final String title;
  final LlmConfig defaultConfig;
  final LlmConfig Function() loadConfig;
  final Future<void> Function(LlmConfig) saveConfig;
  final void Function() resetConfig;

  const _LlmConfigCard({
    required this.title,
    required this.defaultConfig,
    required this.loadConfig,
    required this.saveConfig,
    required this.resetConfig,
  });

  @override
  State<_LlmConfigCard> createState() => _LlmConfigCardState();
}

class _LlmConfigCardState extends State<_LlmConfigCard> {
  late String _model;
  late bool _thinking;
  late String _reasoningEffort;
  late String _temperature;
  late int _maxTokens;
  late int _concurrency;

  static const _models = ['deepseek-v4-flash', 'deepseek-v4-pro'];
  static const _efforts = ['high', 'max'];
  static const _maxTokenOptions = [1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072];

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final c = widget.loadConfig();
    _model = c.model;
    _thinking = c.thinking;
    _reasoningEffort = c.reasoningEffort;
    _temperature = c.temperature.toString();
    _maxTokens = c.maxTokens;
    _concurrency = c.concurrency;
  }

  void _reset() {
    widget.resetConfig();
    _load();
    setState(() {});
  }

  Future<void> _save() async {
    final temp = double.tryParse(_temperature.trim());
    if (temp == null || temp < 0 || temp > 2) {
      if (mounted) {
        AppFeedback.warning('Temperature 无效', '请输入 0~2 之间的小数');
      }
      return;
    }
    await widget.saveConfig(LlmConfig(
      model: _model,
      thinking: _thinking,
      reasoningEffort: _reasoningEffort,
      temperature: temp,
      maxTokens: _maxTokens,
      concurrency: _concurrency,
    ));
    if (mounted) {
      AppFeedback.success('${widget.title}已保存', '新翻译将从下一次请求生效');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: ExpansionTile(
        title: Text(widget.title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$_model  |  并发 $_concurrency'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                // 模型
                DropdownButtonFormField<String>(
                  initialValue: _model,
                  decoration: const InputDecoration(
                    labelText: '模型',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _models
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (v) => setState(() => _model = v!),
                ),
                const SizedBox(height: 12),

                // 思考模式
                DropdownButtonFormField<bool>(
                  initialValue: _thinking,
                  decoration: const InputDecoration(
                    labelText: '思考模式',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(value: false, child: Text('关闭')),
                    DropdownMenuItem(value: true, child: Text('开启')),
                  ],
                  onChanged: (v) => setState(() => _thinking = v!),
                ),
                const SizedBox(height: 12),

                // 思考强度（仅思考开启时显示）
                if (_thinking)
                  DropdownButtonFormField<String>(
                    initialValue: _reasoningEffort,
                    decoration: const InputDecoration(
                      labelText: '思考强度',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _efforts
                        .map((e) => DropdownMenuItem(value: e,
                            child: Text(e == 'high' ? '标准 (high)' : '最大 (max)')))
                        .toList(),
                    onChanged: (v) => setState(() => _reasoningEffort = v!),
                  ),
                if (_thinking) const SizedBox(height: 12),

                // Temperature
                TextFormField(
                  initialValue: _temperature,
                  decoration: InputDecoration(
                    labelText: 'Temperature',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    helperText: _thinking ? '思考模式下此参数不生效' : null,
                    helperStyle: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  enabled: true, // 允许输入，但提示不生效
                  onChanged: (v) => _temperature = v,
                ),
                const SizedBox(height: 12),

                // 最大输出
                DropdownButtonFormField<int>(
                  initialValue: _maxTokenOptions.contains(_maxTokens)
                      ? _maxTokens
                      : _maxTokenOptions.first,
                  decoration: const InputDecoration(
                    labelText: '最大输出 (max_tokens)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _maxTokenOptions
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t >= 1024
                              ? '${t ~/ 1024}K'
                              : t.toString())))
                      .toList(),
                  onChanged: (v) => setState(() => _maxTokens = v!),
                ),
                const SizedBox(height: 12),

                // 并发
                TextFormField(
                  initialValue: _concurrency.toString(),
                  decoration: const InputDecoration(
                    labelText: '并发数',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) {
                    final parsed = int.tryParse(v);
                    if (parsed != null && parsed > 0 && parsed <= 1024) {
                      _concurrency = parsed;
                    }
                  },
                ),
                const SizedBox(height: 16),

                // 按钮
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        child: const Text('保存'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: _reset,
                      child: const Text('重置默认'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
