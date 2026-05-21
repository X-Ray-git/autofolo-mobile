import 'dart:convert';
import 'package:dio/dio.dart';

import '../models/article.dart';
import '../utils/article_content_utils.dart';
import '../utils/storage.dart';
import 'llm_config.dart';

/// AI 文章过滤结果
class FilterResult {
  final bool shouldReject;
  final String reason;

  const FilterResult({required this.shouldReject, required this.reason});
}

/// AI 文章过滤服务 — 使用 DeepSeek JSON Output 判定是否过滤
abstract final class ArticleFilterService {
  static const String _apiBase = 'https://api.deepseek.com';
  static const Duration _timeout = Duration(seconds: 120);

  static String getApiKey() {
    return GStorage.setting.get('deepseek_api_key', defaultValue: '') as String;
  }

  static void setApiKey(String key) {
    GStorage.setting.put('deepseek_api_key', key);
  }

  /// 获取当前 prompt（默认从 autofolo prompts.yaml 裁剪）
  static String getPrompt() {
    return GStorage.setting.get(
      'filter_prompt',
      defaultValue: _defaultPrompt,
    ) as String;
  }

  static Future<void> setPrompt(String prompt) async {
    await GStorage.setting.put('filter_prompt', prompt);
  }

  static void resetPrompt() {
    GStorage.setting.delete('filter_prompt');
  }

  /// 判定单篇文章
  static Future<FilterResult> filterArticle(ArticleModel article) async {
    final apiKey = getApiKey();
    if (apiKey.isEmpty) {
      throw StateError('DeepSeek API key not configured');
    }

    final htmlContent = ArticleContentUtils.normalizeHtml(
      article.content ?? '',
    );
    final textContent = htmlContent
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final prompt = getPrompt();
    final title = article.title;
    final source = article.feedTitle;
    final channelHint = article.feedId.isNotEmpty
        ? '来源频道ID: ${article.feedId}'
        : '';

    final dio = Dio(BaseOptions(
      baseUrl: _apiBase,
      connectTimeout: _timeout,
      receiveTimeout: _timeout,
      sendTimeout: _timeout,
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
    ));

    final config = LlmConfig.loadFilter();
    final requestBody = <String, dynamic>{
      'messages': [
        {'role': 'system', 'content': prompt},
        {
          'role': 'user',
          'content':
              '频道: $source\n$channelHint\n标题: $title\n正文前500字: ${textContent.substring(0, textContent.length.clamp(0, 500))}',
        },
      ],
      'response_format': {'type': 'json_object'},
      'stream': false,
      ...config.toRequestBody(),
    };

    dio.options.baseUrl = _apiBase;
    final response = await dio.post(
      '/chat/completions',
      data: requestBody,
    );

    final data = response.data as Map<String, dynamic>?;
    final choices = data?['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw StateError('DeepSeek returned empty response');
    }
    final message = (choices.first as Map<String, dynamic>)['message'];
    if (message == null) {
      throw StateError('DeepSeek response missing message');
    }
    final content = message['content'] as String?;
    if (content == null || content.trim().isEmpty) {
      throw StateError('DeepSeek returned empty filter result');
    }

    var raw = content.trim();
    if (raw.startsWith('```')) {
      raw = raw.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
      raw = raw.replaceFirst(RegExp(r'\s*```$'), '');
    }
    final first = raw.indexOf('{');
    final last = raw.lastIndexOf('}');
    if (first >= 0 && last > first) {
      raw = raw.substring(first, last + 1);
    }

    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    return FilterResult(
      shouldReject: parsed['should_reject'] == true,
      reason: (parsed['reason'] ?? '未分类').toString(),
    );
  }

  // ─── 默认 Prompt（裁自 autofolo prompts.yaml）─────────────────

  static const String _defaultPrompt = '''
你是一个专业的全智能技术前沿文章分析判定机器。
任务：快速判定给定文章是否应当被过滤抛弃，返回 JSON。

需要抛弃的条件（符合一条即可，不意味着文章是垃圾，只是与领域不相关）：
1. 纯视觉模态（Vision AI、图像/视频生成、GUI操作、数字人等），但医学影像除外。
2. 具身智能（VLA）、机器人控制、自动驾驶、点云、3D感知。
3. 加密货币、区块链、Web3且不含其他技术内容。
4. 音频处理、音乐生成、语音识别（Audio/TTS）。
5. 纯粹政治话题、军事新闻等无技术内涵的杂项。
6. 疑似夸张、炒作的内容。
7. 公司收购、融资等商业新闻（除非涉及技术创新）。
8. 个人宣传、营销推广、公司产品发布公告，缺乏技术方案深度分析。判断标准：是「告诉你某某发布了什么」还是「分析了技术原理」。
9. 非AI领域的技术（数据库、OS、编程语言），除非同时涉及AI。
10. arXiv论文仅将AI应用于小语种/金融等垂直领域→过滤；仅使用金融数据集→保留。

以下频道全部保留（频道名匹配，不是内容匹配）：
"tldr"、"派早报"、"社区速递"、"AI洞察日报"、"AI日报"、"AI资讯日报"、"AI HOT 日报"、"Hacker Podcast"、"The Neuron"、"the rundown ai"、"ai breakfast"、"The Batch"、"今日开源"。
注意：不是名字叫这些的频道，例如保留名字是"AI日报"的频道，而不是说内容是一份AI日报就保留。
少数派「新玩意」「派评」「社区速递」栏目始终保留（标题含相应字样）。
Claude Opus 3的Substack、Andrew Ng(@AndrewYNg)、inbox文章全部保留。
新智元来源严格审查：标题党、推广、缺乏技术原理→坚决过滤。
Arena.ai等模型竞技场：含具体基准分数/模型对比→保留；仅推广投票/印象→过滤。
Notion等用户工具功能集成/模型切换/产品迭代→倾向保留；纯工具推广→过滤。
部分文章为新闻集合，仅部分涉及上述条件但仍含其他技术内容→不应当被过滤。
务必严格把关，宁可错杀也不能放过不相关的。

返回 JSON（直接输出，不要 Markdown 标记）：
{"should_reject": true或false, "reason": "命中原因的简短中文"}
''';
}
