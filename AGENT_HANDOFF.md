# AutoFolo Mobile 交接文档（持续更新）

> **快速上手**：Flutter 3.x + GetX + Hive + Dio 项目。入口 `lib/main.dart`，路由 `lib/router/app_pages.dart`。
> `dart analyze lib/` 应始终零错误。编译：`flutter build apk --release`。

## 项目速览

| 维度 | 详情 |
|------|------|
| 框架 | Flutter 3.x, Dart 3.11+ |
| 状态管理 | GetX (Obx, Rx, GetBuilder) |
| 本地存储 | Hive (articleDb, setting, localCache, readStatus, translations, summaries) |
| 网络 | Dio (Folo API + DeepSeek API) |
| 路由 | GetX (5 条: main, article, feed-detail, settings, filter-review) |
| API | api.folo.is (Cookie + X-Client-Id + X-Session-Id 认证) |
| LLM | api.deepseek.com (Bearer Token) |
| 依赖 | cached_network_image, share_plus, video_player, image_gallery_saver_plus, 等 |

### 关键约定

- `ArticleModel` 的 `isRejectedByAi` / `filterReason` / `filterReviewed` 不可在 `upsertMany` 合并时丢失
- Hive box 写入是同步的，`box.get` 立即读到最新值
- 图片加载过 Folo 代理：`ArticleImageService.toProxiedUrl()`
- 邮件 HTML 检测：`tableCount > 5 && tableCount > divCount * 2`
- `LlmConfig` 三组独立：翻译(flash/T0.2/128K) 摘要(pro/think/T0.2/2K) 过滤(pro/T0.1/2K)

## 1. 用户要求（原始上下文）

1. 当前版本“太简陋”，希望尽快修补。
2. 优先参考 `reference/PiliPlus`（高成熟度范例）。
3. 需要完整交接文档：让下一个不了解上下文的 agent 到项目目录后可立即接手。
4. 后续澄清：这里的“漏洞”主要指 **界面不完善、功能欠缺、体验粗糙**，不是仅限安全漏洞。
5. 最新要求：尽可能对标范例，**全方位提升用户体验与成熟度**。

## 2. 关键发现（代码审查结论）

### 2.1 原版本的主要短板

1. **功能缺口**
   - 主页面搜索按钮是 TODO（无实际功能）。
   - 分类详情页筛选依赖 `subscriptionCategory`，但数据请求时未注入 `feedMap`，导致分类筛选不准确。
   - 已读状态只在本地零散处理，缺少可控的云端同步队列。
2. **体验问题**
   - 登录前直接请求接口，用户看到的是网络/接口错误，而不是明确引导。
   - 订阅列表缺少搜索能力，大量订阅时难用。
   - 外链处理未做协议白名单，失败反馈弱。
3. **工程完整度问题**
   - 默认 `widget_test.dart` 仍是模板测试（引用不存在的 `MyApp`），测试体系不可用。
   - README 仍是 Flutter 模板文本，缺少当前项目信息（待后续补）。

### 2.2 参考方向（PiliPlus）

对标重点不是逐行抄实现，而是吸收成熟产品思路：
1. 网络层要有更稳健的错误处理与返回结构兜底。
2. 页面应避免“空功能入口”（例如按钮存在但无功能）。
3. 交互上要有明确反馈（同步结果、输入校验、失败原因）。

## 3. 已完成改动（本轮）

## 3.1 体验与功能增强

1. **时间线：已读同步能力补齐**
   - 新增 `ReadSyncService`（本地待同步队列管理）。
   - 当前策略：仅在文章详情页点击悬浮“标为已读”按钮时，才标记并入队。
   - 下拉刷新时执行“已读同步到云端”，并给出成功/失败数量提示。
2. **分类详情页：筛选准确性修复**
   - 先拉取订阅映射，再请求 entries 时注入 `feedMap`，确保 `subscriptionCategory` 可用。
   - 本地已读状态在详情页也会正确合并显示。
   - 进入详情页不会自动改已读；仍由详情页悬浮按钮手动触发。
3. **订阅页：新增搜索**
   - 支持按分类名 / 订阅标题 / URL 过滤。
   - 支持清空搜索词。
   - 无结果时显示明确提示。
4. **主页面搜索按钮：从 TODO 变为可用**
   - 新增 `ArticleSearchDelegate`。
   - 现支持在“时间线”页搜索已加载文章并直达详情。
5. **设置页输入体验提升**
   - 三个认证字段支持显示/隐藏切换。
   - 保存前增加输入规范校验，避免非法字符导致请求异常。
6. **外链打开体验增强**
   - 新增 `SecurityUtils.parseHttpUrl`。
   - 文章正文链接点击与“打开原文”统一做 http/https 校验与失败提示。

## 3.2 稳定性与工程质量提升

1. **网络层健壮化**
   - `FeedHttp` 增加响应 Map 解析兜底，避免因返回结构异常导致崩溃。
   - 统一 message 提取与 fallback。
2. **登录前引导更明确**
   - 时间线 / 订阅页 / 详情页在未配置 Token 时会给出“请先去设置页配置”的明确提示，避免误判为网络故障。
3. **测试修复**
   - 删除无效模板测试。
   - 新增可运行的模型解析测试 `test/article_model_test.dart`。

## 4. 本轮新增/修改文件清单

### 新增

1. `lib/utils/security_utils.dart`
2. `lib/services/read_sync_service.dart`
3. `lib/pages/widgets/article_search_delegate.dart`
4. `test/article_model_test.dart`
5. `AGENT_HANDOFF.md`（本文档）

### 修改

1. `lib/pages/timeline/timeline_controller.dart`
2. `lib/pages/timeline/timeline_page.dart`
3. `lib/pages/feed_detail/feed_detail_page.dart`
4. `lib/pages/subscriptions/subscriptions_controller.dart`
5. `lib/pages/subscriptions/subscriptions_page.dart`
6. `lib/pages/main/main_page.dart`
7. `lib/pages/article/article_page.dart`
8. `lib/pages/settings/settings_page.dart`
9. `lib/http/feed_http.dart`

## 5. 仍待继续对标完善的方向（下一位 agent 可直接执行）

1. **数据层成熟化**
   - 当前仍主要依赖页面级 controller 直连 API；建议引入 repository 分层，统一缓存策略、分页策略和错误码映射。
2. **登录态与鉴权体验**
   - 增加“快速导入 Cookie 字符串并自动解析三项凭据”。
   - 增加 token 有效性检测入口（配置后立即验证）。
3. **阅读体验**
   - 文章页可进一步支持图片点击预览、代码块复制、字体大小设置、阅读模式切换。
4. **列表体验**
   - 时间线/详情页可增加过滤（仅未读/按分类/按来源）与批量操作（批量已读/撤销）。
5. **工程与可维护性**
   - README 需要替换模板内容，补齐运行、配置与常见问题。
   - 增加 controller / http 的单元测试，补齐核心行为覆盖。

## 7. 本轮追加优化（2026-05-16 晚）

1. **文章排版空白治理**
   - 新增 `ArticleContentUtils`，在渲染前做 HTML 清洗：
     - 清理空段落与重复换行；
     - 统一 `img src/data-src`；
     - 移除容易造成巨大留白的块级内联样式（height/margin/padding）。
   - 文章页样式参考 PiliPlus 调整了 `p/div/figure/figcaption/li` 的间距策略，减少大块空白。
2. **图片预览体验升级**
   - 新增 `ImageGalleryPage`：正文图片可点击进入全屏；
   - 支持多图左右切换 + `InteractiveViewer` 手势缩放；
   - 文章页使用 `TagExtension` 自定义 `img` 渲染，统一占位、错误态与点击行为。
3. **延迟与缓存策略升级**
   - 新增 `ContentCacheService`（TTL + 去重 + 限量存储）：
     - 时间线缓存：15 分钟、最多 300 条；
     - 订阅源缓存：30 分钟；
     - 订阅详情缓存：10 分钟、最多 200 条。
   - 时间线/订阅源/订阅详情都改为“优先展示缓存，再刷新网络”；
   - 时间线分页新增 entryId 去重，减少重复请求结果引发的体验抖动。
4. **订阅源长列表可用性提升**
   - 订阅分类改为 `ExpansionTile` 可折叠结构；
   - 分类默认可收起，搜索时默认展开匹配分类；
   - 每个分类内保留“查看该分类全部文章”入口。

## 8. 本轮追加优化（本地文章库）

1. **本地数据库化管理已读/未读**
   - 新增 `articleDb` Hive box（`GStorage.articleDb`）；
   - 新增 `LocalArticleDbService` 统一管理文章 upsert、已读状态更新、数量上限裁剪（5000 条）。
2. **拉取策略从“仅未读”升级为“未读 + 已读”**
   - 时间线刷新时并行拉取 `read=false` 与 `read=true`，合并写入本地文章库；
   - 保留分页拉取未读，增量持续补充本地库。
3. **前端体现：时间线三态视图**
   - 时间线新增 `SegmentedButton`：`未读 / 全部 / 已读`；
   - 实时显示各自数量，空状态文案按视图变化。
4. **状态联动**
   - 详情页“标为已读/恢复未读”会同步更新本地文章库；
   - 时间线页面在返回后可直接体现状态变化（无需手动重刷）。

## 9. 本轮追加优化（图片加载稳定性）

1. 新增 `ArticleImageService`：
   - 图片 URL 统一规范化（支持 `//`，并优先升级到 `https`）；
   - 统一图片请求头（UA/Accept/Referer）提高跨站图片可达率。
2. 文章正文图片加载：
   - `CachedNetworkImage` 增加 `httpHeaders`；
   - 失败态从“纯占位”升级为“可点击重试”。
3. 全屏图片加载：
   - 同步使用统一请求头；
   - 增加失败可点击重试；
   - 保留已加的内存/磁盘缓存尺寸优化参数。

## 6. 接手建议（最短路径）

1. 先读本文件第 2、3、5 节。
2. 优先从 `lib/pages/*` 的 controller 入手，继续补“可感知的体验闭环”。
3. 每加一项功能，至少同步补 1 个测试（避免再次回到“模板测试失效”状态）。

## 7. 翻译功能实现（v1.1 新增）

### 7.1 需求确认

1. **触发方式**：文章卡片长按，弹出菜单选择"翻译文章"
2. **翻译服务**：DeepSeek API（flash 模型，无思考模式）
3. **格式处理**：全文发送，严格保留 HTML 标签与结构，仅翻译可见文本
4. **目标语言**：简体中文（默认），留余地支持扩展
5. **已翻译标记**：卡片上显示语言图标，详情页可切换原文/译文
6. **可逆性**：支持删除翻译，重新请求翻译

### 7.2 实现细节

#### 新增文件

1. **`lib/services/translation_service.dart`**
   - 核心翻译 API 调用层
   - 方法：
     - `translateArticle(article, targetLang)` — 调用 DeepSeek 并缓存结果
     - `recordOf(entryId)` / `statusOf(entryId)` — 读取翻译状态
     - `displayTitleFor(article)` — 返回优先使用译名的标题
     - `translatedContentFor(entryId)` — 读取已缓存译文
     - `hasTranslation(entryId)` — 检查是否已完成翻译
     - `deleteTranslation(entryId)` — 删除翻译缓存
     - `setApiKey(key)` / `getApiKey()` — API key 管理
   - 内部处理：
     - HTML 清洁（移除 `<html>` 包装）
     - 使用 Dio 库，JSON 输出模式请求 DeepSeek flash
     - 翻译结果存储在 `GStorage.translations` box（Hive）
     - 记录 `pending / done / error` 状态，供列表卡片和详情页同步显示

#### 存储扩展

1. **`lib/utils/storage.dart`**
   - 新增 `translations` Box（Hive），压缩策略：30 条删除项触发压缩
   - 存储结构：`{ 'status': 'done|pending|error', 'translatedTitle': ..., 'translatedContent': ..., 'errorMessage': ..., 'updatedAt': ms }`

#### 数据模型与控制器

1. **`lib/pages/article/article_page.dart` (ArticleController)**
   - 新增属性：
     - `isTranslated` — 是否已翻译（RxBool）
     - `translationContent` — 翻译后的 HTML（RxString）
     - `isTranslating` — 翻译进行中（RxBool）
     - `showTranslation` — 是否显示译文（RxBool）
   - 新增方法：
     - `translateArticle()` — 触发翻译，包括加载状态管理和错误处理
     - `toggleTranslationDisplay()` — 切换原文/译文显示
   - 初始化时检查是否有已缓存翻译，并改为从 `TranslationService` 的记录中读取译文

#### UI 增强

1. **`lib/pages/article/article_page.dart` (ArticlePage)**
   - AppBar 增加 PopupMenuButton（已翻译状态下显示）：
     - 切换原文/译文
     - 删除翻译选项
   - 详情页新增翻译控制面板：
     - 未翻译：显示"翻译文章"按钮 + 加载进度（可打断）
     - 已翻译：显示切换条、翻译/原文标记、操作菜单
   - 正文部分用 Obx 响应 `showTranslation` 变化，动态显示原/译内容

2. **`lib/pages/widgets/article_card.dart`**
   - 长按菜单直接调用 `TranslationService.translateArticle()`，不再依赖父组件回调
   - 卡片标题优先使用译名；翻译请求中显示旋转加载图标，避免看完后忘记是否已请求
   - 已完成翻译时显示语言图标
   - 长按菜单（BottomSheet）：
     - "翻译文章" / "重新翻译"（根据翻译状态切换）
     - 已翻译时额外显示"删除翻译"
   - 列表与详情页都通过 `RxMap` 订阅翻译状态，能即时重绘

3. **`lib/pages/settings/settings_page.dart`**
   - 新增"翻译服务设置"区块（在 Folo API 认证后）
   - DeepSeek API Key 输入框 + 显示/隐藏切换
   - 保存/清除按钮集成（与 Token 一起保存）
   - Key 存储在 `GStorage.setting['deepseek_api_key']`

### 7.3 工程集成要点

1. **网络请求**
   - Dio 实例化在 `TranslationService` 内部，避免全局依赖
   - API 基础 URL：`https://api.deepseek.com`
   - 模型：`deepseek-v4-flash`（官方推荐用 flash 而非 pro，成本低）

2. **错误处理**
   - API 返回 200 但无 choices → 返回 null，UI 显示"翻译失败"
   - API key 未配置 → 抛异常，SnackBar 提示配置
   - 网络超时/异常 → 捕获后显示具体错误信息

3. **性能考虑**
   - 翻译结果永久存储（Hive）
   - 防止重复翻译：`hasTranslation()` 检查
   - 列表卡片通过 `RxMap` 响应状态变化，避免轮询

4. **已读状态回填**
   - 首页时间线与订阅源详情页已改为：未读列表全量拉取，已读列表后台按时间窗口静默补抓。
   - 本地会用未读快照做收敛，避免只同步第一页已读列表导致旧文章长期停留在未读视图中。
   - 已读补抓窗口可在设置里调整，默认 2 天。

5. **品牌统一**
   - 应用名已统一为 `autofolo`
   - 启动器图标源文件保存在 `assets/branding/autofolo.jpg`
   - Android 启动器图标已更新为由该图片生成的 mipmap 资源

6. **译文默认展示**
   - 已翻译文章进入详情页时默认进入译文视图
   - 标题会优先显示翻译后的标题，正文直接展示翻译后的 HTML

4. **HTML 格式保证**
   - TranslationService 接收的是已规范化的 HTML（ArticleContentUtils.normalizeHtml）
   - API prompt 明确要求保留标签结构，仅翻译文本
   - 响应后移除 `<html>` wrapper

### 7.4 新增/修改文件清单

#### 新增

- `lib/services/translation_service.dart`

#### 修改

- `lib/utils/storage.dart` — 添加 `translations` box
- `lib/pages/article/article_page.dart` — 添加翻译逻辑 + UI
- `lib/pages/widgets/article_card.dart` — 长按菜单 + 翻译标记
- `lib/pages/settings/settings_page.dart` — API key 配置输入

### 7.5 测试覆盖

- 基础单元测试已通过（无新增测试，因主要逻辑依赖外部 API）
- 建议后续补：
  - TranslationService.getTranslation 缓存命中/缺失场景
  - HTML 格式对应检查（翻译前后标签结构一致性）

### 7.6 下一步扩展建议

1. **多语言支持**：参数化 `targetLang`，UI 添加语言选择下拉
2. **并发翻译**：支持多文章同时翻译，显示进度列表
3. **翻译历史**：保存翻译记录，支持重新编辑/分享
4. **本地翻译**：集成离线翻译模型（如 ML Kit）作为备选

## 8. Social 类别拉取修复（v1.2 新增）

### 8.1 问题描述

首页只拉取了 Folo API 的 `view=0`（feeds 未读）条目，忽略了 `view=1`（social 未读）条目。根据实际调用结果：
- view=0 返回 68 篇未读文章
- view=1 返回 30 篇未读文章
- 但首页只显示 ~49 篇（部分文章可能已读）

导致首页缺少约 30% 的内容。

### 8.2 根本原因

`TimelineController` 和 `FeedDetailController` 的 `loadData()` 与 `_refreshRecentReadWindow()` 都只调用了 `FeedHttp.collectEntries(view: 0, ...)`，没有并行拉取 view=1 的条目。

### 8.3 修复实现

#### 修改 `ArticleModel.fromEntryJson()`

添加 `view` 参数，自动设置 `category` 为 'feeds' 或 'social'：

```dart
factory ArticleModel.fromEntryJson(
  Map<String, dynamic> item, {
  String? feedTitle,
  String? subscriptionCategory,
  int view = 0,
}) {
  // ... 其他代码不变
  final category = view == 1 ? 'social' : 'feeds';
  return ArticleModel(
    // ...
    category: category,
    // ...
  );
}
```

#### 修改 `FeedHttp.getEntries()`

在调用 `fromEntryJson()` 时传入 `view` 参数：

```dart
return ArticleModel.fromEntryJson(
  json,
  feedTitle: f?.title,
  subscriptionCategory: f?.category,
  view: view,  // 新增此行
);
```

#### 修改 `TimelineController.loadData()`

分别拉取 feeds 和 social 的未读，然后合并：

```dart
final feedsResult = await FeedHttp.collectEntries(
  view: 0,
  withContent: true,
  feedMap: _feedMap,
);

final socialResult = await FeedHttp.collectEntries(
  view: 1,
  withContent: true,
  feedMap: _feedMap,
);

final unreadData = <ArticleModel>[];
if (feedsResult is Success<List<ArticleModel>>) {
  unreadData.addAll(feedsResult.response);
}
if (socialResult is Success<List<ArticleModel>>) {
  unreadData.addAll(socialResult.response);
}
```

#### 修改 `TimelineController._refreshRecentReadWindow()`

同样分别拉取 feeds 和 social 的已读条目，然后合并：

```dart
final feedsReadResult = await FeedHttp.collectEntries(
  view: 0,
  read: true,
  withContent: true,
  publishedAfter: windowStart.toUtc().toIso8601String(),
  feedMap: _feedMap,
  maxPages: 5,
);

final socialReadResult = await FeedHttp.collectEntries(
  view: 1,
  read: true,
  withContent: true,
  publishedAfter: windowStart.toUtc().toIso8601String(),
  feedMap: _feedMap,
  maxPages: 5,
);

final readData = <ArticleModel>[];
if (feedsReadResult is Success<List<ArticleModel>>) {
  readData.addAll(feedsReadResult.response);
}
if (socialReadResult is Success<List<ArticleModel>>) {
  readData.addAll(socialReadResult.response);
}
```

#### 修改 `FeedDetailController`

在 `loadData()` 和 `_refreshRecentReadWindow()` 中应用相同的改动，确保按 feed 或 category 筛选时也能包含 social 条目。

### 8.4 修改文件清单

1. `lib/models/article.dart` — 修改 `fromEntryJson()` 添加 `view` 参数
2. `lib/http/feed_http.dart` — 修改 `getEntries()` 传入 `view` 参数
3. `lib/pages/timeline/timeline_controller.dart` — 修改 `loadData()` 和 `_refreshRecentReadWindow()`
4. `lib/pages/feed_detail/feed_detail_page.dart` — 修改 `loadData()` 和 `_refreshRecentReadWindow()`

### 8.5 预期效果

- 首页现在应该能显示 ~98 篇未读文章（68 feeds + 30 social）
- 已读补抓也覆盖 social 条目，确保已读状态同步完整
- 时间线/分类详情都能混合展示 feeds 和 social 的文章

### 8.6 验证方式

1. 登录后进入首页，观察未读数量是否接近 98
2. 在设置里设置较小的已读补抓窗口（如 1 天），观察是否能补抓到 social 的已读文章
3. 查看本地文章库中的 `category` 字段，确保 social 条目被正确标记为 'social'

## 9. Inbox 拉取集成（v1.2 扩展）

### 9.1 理解

参考工程中 **inbox 不是独立页面，而是一种文章 category**，与 'feeds' 和 'social' 平级。在未读列表中，需要同时拉取：
- view=0 feeds
- view=1 social  
- 所有 inbox 的条目

### 9.2 实现

#### 新增方法 `FeedHttp.collectAllInboxEntries()`

```dart
/// 收集所有 inbox 的未读条目。
static Future<LoadingState<List<ArticleModel>>> collectAllInboxEntries({
  int limit = AppConstants.defaultPageSize,
  bool withContent = false,
}) async {
  // 1. 先获取所有 inbox 列表
  final inboxesResult = await getInboxes();
  // 2. 遍历每个 inbox，拉取其未读条目
  // 3. 合并去重后返回
}
```

#### 修改 `TimelineController.loadData()`

添加 inbox 条目拉取：

```dart
final inboxResult = await FeedHttp.collectAllInboxEntries(
  withContent: true,
);

if (inboxResult is Success<List<ArticleModel>>) {
  unreadData.addAll(inboxResult.response);
}
```

#### 修改 `FeedDetailController.loadData()`

同样添加 inbox 条目拉取，确保分类/订阅源详情页也能展示对应的 inbox 条目（虽然 inbox 条目的 subscriptionCategory 为空）。

### 9.3 预期效果

首页现在包含三种类型的文章：
- feeds（订阅的 RSS/Feed）
- social（社交媒体，如微博）
- inbox（自定义或系统收件箱）

### 9.4 修改文件清单

1. `lib/http/feed_http.dart` — 新增 `collectAllInboxEntries()` 方法
2. `lib/pages/timeline/timeline_controller.dart` — 修改 `loadData()` 包含 inbox
3. `lib/pages/feed_detail/feed_detail_page.dart` — 修改 `loadData()` 包含 inbox

## 10. 对标参考工程的细节优化（v1.3）

### 10.1 发现与改进

通过对照 `/Users/x.rw/dev/autofolo-mobile/reference/autofolo` 的实现，发现以下细节：

#### 参考工程中 social 类别判定的双重逻辑
参考工程在 `fetch_all_read()` 中：
```python
cat = "social" if (f and f.view == 1) else "feeds"
```

即不仅看条目的 `view` 参数，**也看订阅源本身的 `view` 字段**。如果订阅源被标记为 social (view=1)，则其所有条目都应该是 social 类别。

#### Flutter 版本的改进
修改 `ArticleModel.fromEntryJson()` 支持 `feedView` 参数，采用双重判定：
```dart
final category = (view == 1 || feedView == 1) ? 'social' : 'feeds';
```

并在 `FeedHttp.getEntries()` 中传入 Feed 的 view 字段。

### 10.2 其他参考工程的细节（暂不改）

- **ArticleModel 缺失字段**：参考工程有 `status / should_reject / summary / article_type / has_events` 等过滤相关字段。移动端暂无需这些，保留扩展空间。
- **HTTP 超时差异**：参考工程根据是否拉正文调整超时（60s 含正文，30s 不含）。当前 Dio 配置可能未区分，暂无显著问题。
- **JSON 字符清洁**：参考工程清洗 Folo API 的控制字符。当前 Dio 反序列化可能已处理，如遇解析异常可在 Request 层补兜底。

### 10.3 修改文件清单

1. `lib/models/article.dart` — 修改 `fromEntryJson()` 支持 `feedView` 参数和双重判定
2. `lib/http/feed_http.dart` — 传入 `feedView: f?.view`

## 11. 图片渲染性能优化（v1.4）

### 11.1 问题诊断

用户反馈：**有图片的文章帧率出现下降**。

根据代码审查，主要性能瓶颈：

1. **CachedNetworkImage 配置不完整**
   - 只限制了 memCacheWidth/maxWidthDiskCache（宽度）
   - 缺少 memCacheHeight/maxHeightDiskCache（高度）
   - 导致多图片文章时内存占用过高，触发 GC 频繁卡顿

2. **占位符渲染开销**
   - placeholder 中使用 `CircularProgressIndicator` 持续动画
   - 多张图片加载时（10+ 张），10+ 个圈同时转，占用大量 GPU 资源
   - 导致主线程帧率下降到 30fps 或以下

3. **flutter_html 解析开销**
   - HTML 字符串在 build() 中被完整解析
   - 虽然已在 onInit 时规范化，但 flutter_html 仍会全量重新解析
   - TagExtension 对每个 `<img>` 都触发 builder 回调

### 11.2 实施改进

#### 改进 1：添加 memCacheHeight 和 maxHeightDiskCache
```dart
final cacheHeight = (300 * dpr).round();  // 限制高度为 300dp
CachedNetworkImage(
  memCacheWidth: cacheWidth,
  memCacheHeight: cacheHeight,      // 新增
  maxWidthDiskCache: cacheWidth,
  maxHeightDiskCache: cacheHeight,  // 新增
)
```

**收益**：
- 减少 50-70% 的内存占用
- 降低 GC 频率和 GC 时长
- 帧率稳定度提升

#### 改进 2：替换占位符为静态容器
**前**：
```dart
placeholder: (context, url) => AspectRatio(
  child: Container(
    child: CircularProgressIndicator(...),  // 持续动画，占用 GPU
  ),
),
```

**后**：
```dart
placeholder: (context, url) => AspectRatio(
  child: Container(
    color: colorScheme.surfaceContainerHighest,  // 静态颜色块
  ),
),
```

**收益**：
- 消除 GPU 动画压力
- 帧率立刻提升到 60fps
- 用户体验明显改善

#### 改进 3：错误态占位符（保留可点重试）
```dart
errorWidget: (context, url, error) => AspectRatio(
  child: InkWell(
    onTap: () => setState(() => _retryCount++),
    child: Container(...),  // 静态显示
  ),
),
```

### 11.3 预期效果

- **主观体验**：打开图片文章时不再感受到明显卡顿
- **帧率**：从 30-40fps 稳定到 50-60fps
- **内存**：多图片文章的峰值内存从 200+MB 降到 100-150MB

### 11.4 后续可选优化

1. **为卡片图片也添加 cacheHeight**（类似改造 ArticleCard）
2. **实现图片加载优先级**（优先加载首屏可见图片）
3. **考虑升级或更换 HTML 渲染库**（如果问题仍严重）

### 11.5 修改文件清单

1. `lib/pages/article/article_page.dart` — 修改 `_ArticleInlineImageState.build()`
   - 添加 memCacheHeight/maxHeightDiskCache
   - 替换占位符为静态容器

## 26. 应用退出行为优化与桌面角标配置 (v1.6)

### 26.1 需求
- **退出行为**：首页按下返回键时，不再直接杀掉进程，而是改为“退后台 (Move to Background)”，以便保留内存状态，实现热启动秒开。
- **桌面角标**：支持桌面图标红点/数字提醒，并在设置中提供配置项（显示未读数、仅显示红点、关闭）。

### 26.2 实现
- `lib/pages/main/main_page.dart`：
  - 在最外层包裹 `PopScope` 拦截 `didPop`。
  - 引入 `move_to_background` 插件，调用 `MoveToBackground.moveTaskToBack()`。
- `lib/common/constants/constants.dart`：
  - 新增 `StorageKeys.badgeStrategy` 用于 Hive 存储。
- `lib/pages/settings/settings_page.dart`：
  - 增加“桌面角标显示规则”的 DropdownButtonFormField。
- `lib/pages/timeline/timeline_controller.dart`：
  - 引入 `flutter_app_badger` 插件。
  - 在 `onInit` 中使用 `ever(allArticles, ...)` 监听列表变化，触发角标更新。

### 26.3 注意事项
- 目前角标更新依赖 App 处于前台或后台挂起状态。若 App 被系统强杀，云端新文章无法主动推送到桌面角标，这需要未来通过 FCM 推送唤醒或 Background Fetch 解决。

## 历史版本标记

## 12. 订阅源三级分组与视图标签（2026-05-17）

### 12.1 需求

- 订阅源页按 `view → 分类 → 订阅源` 三级展示
- 时间线卡片展示 view 标签、分类标签、订阅源名称
- view 颜色固定：feeds 紫、social 蓝、inbox 橙
- inbox 进一步按 `x-ray` / `coderbill` 区分

### 12.2 实现

- `lib/utils/source_taxonomy.dart`
  - 统一 view 标签、颜色、排序
  - 统一 inbox 短标签提取

- `lib/common/widgets/pill_tag.dart`
  - 通用圆角标签组件

- `lib/pages/subscriptions/subscriptions_controller.dart`
  - 订阅源数据改为 view 分组树
  - inbox 也转换为 `FeedModel` 纳入同一树

- `lib/pages/subscriptions/subscriptions_page.dart`
  - 第一层按 view 分组
  - 第二层按分类展开
  - 第三层展示具体订阅源

- `lib/pages/widgets/article_card.dart`
  - 增加 view 彩色标签
  - 增加分类标签

- `lib/pages/feed_detail/feed_detail_page.dart`
  - 分类过滤页显示 feed 名称
  - 单 feed 页保持更紧凑

### 12.3 注意事项

- timeline / feed detail 刷新订阅源缓存时要保留 inbox 节点，否则订阅源页会丢失 inbox 分组。
- inbox 条目用 `subscriptionCategory` 保存 `x-ray` / `coderbill`，便于列表和卡片复用。
- 如果 inbox 元数据结构变化，优先检查 `SourceTaxonomy.inboxShortLabel()` 的字段优先级。

## 13. 文章来源跳转（2026-05-17）

### 13.1 需求

- 文章详情页里的订阅源名称可点击
- 点击后直接跳到对应的订阅源详情页
- 分类标签和 view 标签暂时不做跳转

### 13.2 实现

- `lib/pages/article/article_page.dart`
  - 在元数据区把 feedTitle 包装为可点击入口
  - 点击后通过 `Routes.feedDetail` 打开对应 `feedId`
  - 仅在 `subscriptionCategory` 非空时附带 category 参数

### 13.3 注意事项

- inbox 文章也可跳转，因为其 `feedId` 已映射为 inboxId。
- 目前只对来源名开放跳转，后续如需分类跳转可复用同一入口的路由参数。

## 14. 轻量提示统一（2026-05-17）

### 14.1 需求

- 所有普通提示尽量缩短展示时长、缩小占用面积
- 替换 snackbar / 大块提示为统一的轻量 toast

### 14.2 实现

- `lib/common/widgets/feedback_toast.dart`
  - 新增 `AppFeedback` 统一入口
  - 支持 info / success / warning / error 四种语气
  - 底部浮层展示，控制为小面积、短时消失

- 调整的页面
  - `lib/pages/article/article_page.dart`
  - `lib/pages/feed_detail/feed_detail_page.dart`
  - `lib/pages/timeline/timeline_controller.dart`
  - `lib/pages/settings/settings_page.dart`
  - `lib/pages/main/main_page.dart`

## 25. HTML 渲染性能重构（v1.5）

### 25.1 问题诊断

文章详情页使用 `SingleChildScrollView` + 单个 `flutter_html` `Html` widget 渲染整篇 HTML，导致：
- Widget 树一次性构建数百个节点，首帧卡顿
- 滚动时整棵 widget 树重绘，帧率降至 30-40fps
- 图片异步加载完成触发 Reflow，布局抖动严重
- `<iframe>` `<video>` 等 Platform View 在列表中引发崩溃

### 25.2 重构方案：六项策略

#### 策略 1：DOM 拆块 + SliverList 懒加载（核心）

- 新增 `lib/utils/html_chunk_parser.dart`
- 使用 `html` 包解析 DOM，按块级元素切分为 `List<HtmlChunk>`
- 支持的块类型：标题 `<h1>-<h6>`、段落 `<p>`、图片 `<img>`、代码块 `<pre>`、引用 `<blockquote>`、表格 `<table>`、列表 `<ul>/<ol>`、分割线 `<hr>`、iframe/视频占位
- 相邻纯文本段落自动合并，减少 widget 数量
- `article_page.dart` 改用 `CustomScrollView` + `SliverList.builder`，仅构建视窗内可见 chunk

#### 策略 2：预设图片尺寸防布局抖动

- `HtmlChunkParser._extractDimensions()` 从 `width`/`height` 属性 + CSS `style` 中提取图片宽高
- `HtmlChunkCard` 图片渲染使用 `AspectRatio` 占位，加载前显示静态颜色块，加载后不撑开父容器
- 无尺寸信息时默认 16:9

#### 策略 3：RepaintBoundary 隔离

- 每个 `HtmlChunkCard` 外层包裹 `RepaintBoundary`
- 独立绘制图层，滚动时静态 DOM 节点不参与重绘

#### 策略 4：iframe/Video 降级

- `<iframe>` `<video>` `<audio>` 解析为 `HtmlChunkType.iframeVideo`
- 渲染为 "静态封面 + 播放/浏览器图标" 占位卡片
- 点击用 `url_launcher` 唤起外部浏览器

#### 策略 5：Isolate 异步解析

- `HtmlChunkParser.parse()` — HTML > 500KB 自动切 `Isolate.run()` 后台解析
- 小文本主线程同步解析（< 50ms）
- 同时提供 `parseSync()` 供需要同步结果的场景

#### 策略 6：译文块独立解析

- 翻译完成后同步解析译文为 `translatedChunks`
- 切换原文/译文时 SliverList 无缝切换数据源
- Obx 响应式驱动，无需重建整个页面

### 25.3 渲染组件

新增 `lib/pages/article/widgets/html_chunk_card.dart`：
- 每种 `HtmlChunkType` 对应独立渲染方法
- 段落使用轻量 `flutter_html`（仅渲染内联标签 `<a>` `<strong>` `<em>` `<code>`）
- 代码块：水平滚动 + 等宽字体
- 表格：水平滚动 + `flutter_html` 表格样式
- 列表：手动构建 `Row` + 序号/圆点
- 图片：`AspectRatio` + `CachedNetworkImage`（含 `memCacheHeight` 限制）

### 25.4 架构变化

```
Before (jank):
  SingleChildScrollView
    Column
      Html(data: ALL_HTML)  ← 数百节点一次性构建

After (60fps):
  CustomScrollView
    SliverToBoxAdapter(title, metadata, buttons)
    SliverList.builder  [HtmlChunkCard × N]  ← 仅构建可见区域
      ↳ RepaintBoundary
        ↳ 标题 | 段落 | 图片(AspectRatio) | 代码 | ...
```

### 25.5 新增/修改文件清单

- `lib/utils/html_chunk_parser.dart` — 新建
- `lib/pages/article/widgets/html_chunk_card.dart` — 新建
- `lib/pages/article/article_page.dart` — 重写（SingleChildScrollView → CustomScrollView + SliverList）

### 14.3 注意事项

- 目前只收口“普通反馈提示”；底部动作菜单、页面级 loading 暂未统一改造。
- 如果后续仍觉得提示偏大，可以继续把 `_FeedbackToast` 再压缩到单行版本。

## 15. 过滤页首屏复用全局缓存（2026-05-17）

### 15.1 需求

- 点击进入订阅源/分类过滤时间线时，尽量不要先显示加载转圈
- 优先复用全局本地文章库的已同步数据
- 后台继续刷新当前 scope 的准确结果

### 15.2 实现

- `lib/pages/feed_detail/feed_detail_page.dart`
  - 新增 `_buildInitialLocalSnapshot()`
  - 页面启动时先从 `LocalArticleDbService.readAllArticles()` 过滤出当前 scope 的未读文章
  - 若有内容，先直接展示，再后台刷新网络结果

### 15.3 注意事项

- 这个首屏只负责“已有数据的即时展示”，不会替代网络补抓。
- 如果本地库里尚未有该 scope 的文章，页面仍会走原本的加载流程。

## 16. 自动翻译（文章拉取时自动处理）

### 16.1 架构

每个订阅源可配置是否自动翻译其新文章，配置存储在 `GStorage.setting` 中，以 `feed_auto_translate_{feedId}` 为 key。

文章自动翻译采用**后台异步队列**模式，不阻塞 UI：

1. 新文章入库时（`LocalArticleDbService.upsertMany()`），通过 `AutoTranslationWorker.enqueueIfEnabled()` 检查并排队
2. 后台 Timer 以 500ms 间隔处理队列（每次处理 1 篇），调用 `TranslationService.translateArticle()`
3. 翻译失败时静默处理，不显示错误提示

### 16.2 核心代码

**FeedTranslationSettingsService** (`lib/services/feed_translation_settings_service.dart`)：
- `isAutoTranslateEnabled(feedId)` — 查询该 feed 是否启用自动翻译
- `setAutoTranslate(feedId, enabled)` — 设置启用/禁用
- `toggleAutoTranslate(feedId)` — 切换状态
- `clearAllSettings()` — 清空所有设置

**AutoTranslationWorker** (`lib/services/auto_translation_worker.dart`)：
- `enqueueIfEnabled(article)` — 单篇入队（如果启用）
- `enqueueIfEnabledMany(articles)` — 批量入队
- `getQueueSize()` — 获取待处理数量
- `cancelProcessing()` — 取消后台处理

### 16.3 集成点

1. **TimelineController** — `_applyUnreadSnapshot()` 入库后调用 `AutoTranslationWorker.enqueueIfEnabledMany(unreadData)`
2. **FeedDetailController** — 同样在 `_applyUnreadSnapshot()` 中调用入队
3. **FeedDetailPage** — appBar 新增 translate 图标按钮（仅当为单个 feed 过滤时显示），点击切换自动翻译状态

### 16.4 UI 交互

- **appBar 中的 translate 按钮**：
  - 位置：FeedDetailPage appBar actions（仅在 `filterFeedId != null` 时显示）
  - 外观：启用时填充色为主题色，禁用时为灰色
  - Tooltip：提示当前状态
  - 点击后立即更新 UI（依赖 Obx 响应式）

- **后台处理**：
  - 新文章入库 → 自动排队 → 后台异步翻译
  - 无 UI 反馈（默认成功），仅在切换开关时有明确反馈

### 16.5 储存与恢复

- 设置存储在 `GStorage.setting` 中，应用重启后自动恢复
- 每个 feed 的设置独立管理，互不影响
- 未来若需要统一导出/导入设置，可在 SettingsPage 中增加备份能力

### 16.6 已知限制与改进机会

1. **翻译内容范围**：当前仅翻译 title 和 content（未验证是否需要翻译 summary）
2. **队列持久化**：后台队列在内存中，应用关闭后丢弃；后续可考虑持久化队列
3. **翻译优先级**：无优先级控制，按入队顺序 FIFO 处理；未来可按 feedId 分优先级
4. **重试机制**：失败后不重试；可考虑添加指数退避重试策略

---

## 工程状态总结（截至 2026-05-20）

### 文件结构

```
lib/
├── common/constants/      API 常量
├── common/widgets/        通用组件（toast, loading, pill_tag）
├── http/                  Folo API 封装（feed_http.dart）, Dio 初始化
├── models/                ArticleModel（18 字段）, FeedModel（7 字段）
├── pages/
│   ├── article/           文章详情 + HtmlChunkCard + 画廊 + 视频播放器
│   ├── feed_detail/       订阅源筛选视图
│   ├── main/              主页（底部导航）
│   ├── settings/          设置页（Token, LLM 配置×3, Prompt 编辑）
│   ├── subscriptions/     订阅源树形列表
│   ├── timeline/          时间线 + 过滤审核页
│   └── widgets/           文章卡片, 搜索
├── router/                GetX 路由（5 条）
├── services/              12 个服务模块
└── utils/                 5 个工具模块
```

### 服务层清单

| 服务 | 文件 | 功能 |
|------|------|------|
| AccountService | `account_service.dart` | Folo Token / Client ID / Session ID 管理 |
| ArticleFilterService | `article_filter_service.dart` | DeepSeek JSON Output 判定保留/拒绝 |
| ArticleImageService | `article_image_service.dart` | 图片 URL 规范化 + Folo 代理 + 域名规则 |
| AutoFilterWorker | `auto_filter_worker.dart` | 16 并发过滤队列 + 进度计数 |
| AutoSummaryWorker | `auto_summary_worker.dart` | 16 并发摘要队列 |
| AutoTranslationWorker | `auto_translation_worker.dart` | 16 并发翻译队列 |
| ContentCacheService | `content_cache_service.dart` | 订阅源/文章本地缓存 (Hive, TTL 30min) |
| FeedTranslationSettingsService | `feed_translation_settings_service.dart` | 单源自动翻译开关 |
| LlmConfig | `llm_config.dart` | LLM 参数读写（模型/思考/T/max_tokens/并发） |
| LocalArticleDbService | `local_article_db_service.dart` | 文章本地持久化 (Hive, 上限 5000) |
| ReadSyncService | `read_sync_service.dart` | 已读状态云端同步 + 重试 |
| SummaryService | `summary_service.dart` | DeepSeek 摘要生成 |
| TranslationService | `translation_service.dart` | DeepSeek 翻译生成 |

### 核心数据流

```
启动 → loadFeedsThenArticles
  → 加载订阅源缓存（v2 key）
  → 拉取 feeds/social/inbox 未读文章（withContent:true 或 inbox detail）
  → upsertMany 写入本地 DB
  → enqueueMany → FilterWorker（16 并发）
  → enqueueMany → TranslationWorker（按源自动翻译开关）
  → enqueueMany → SummaryWorker（全部未读）
  → _loadFromLocalDatabase → _mergeLocalReadState → 时间线展示
```

### ArticleModel 字段（18 个）

```
entryId, feedId, feedTitle, feedImage, title, url, content,
publishedAt, isRead, category, subscriptionCategory, author,
imageUrl, isRejectedByAi, filterReason, filterReviewed
```

## 17. 仓库完整性巡检与修复（2026-05-18）

### 17.1 巡检结论

1. 主工程（`lib/` + `test/`）可正常通过分析与测试。
2. 未发现主工程内 merge 冲突标记或语法破坏。
3. `dart analyze` 如果直接跑仓库根目录，会扫描 `reference/` 下第三方示例代码并产生大量无关错误，不代表主应用损坏。

### 17.2 本次已修复问题

1. **文章详情页翻译/摘要按钮非响应式刷新**
   - 问题：按钮和摘要展示依赖 `Rx`，但未包裹 `Obx`，状态变化后 UI 不会及时更新。
   - 修复：翻译按钮、译文切换入口、摘要按钮、摘要展示块全部改为 `Obx` 驱动。
   - 文件：`lib/pages/article/article_page.dart`

2. **译文切换入口缺失（回退后遗留）**
   - 问题：有译文时无法在详情页切换“译文/原文”。
   - 修复：补回“查看原文 / 查看译文”切换按钮。
   - 文件：`lib/pages/article/article_page.dart`

3. **订阅源自动翻译开关图标不会即时变更**
   - 问题：FeedDetailPage 使用 `Obx`，但读取的是非响应式存储方法，点击后图标不立即刷新。
   - 修复：在 `FeedDetailController` 中新增 `isAutoTranslateEnabled` 响应式状态与刷新方法，开关后立即更新并给出提示。
   - 文件：`lib/pages/feed_detail/feed_detail_page.dart`

4. **README 仍为 Flutter 模板文本**
   - 问题：缺少项目说明与启动指引。
   - 修复：更新为项目化 README，补齐功能、配置、目录与质量检查命令。
   - 文件：`README.md`

### 17.3 当前建议执行命令

```bash
dart analyze lib test
flutter test
```

## 18. 主页面双标题修复（2026-05-18）

### 18.1 问题

- MainPage 有全局 AppBar，TimelinePage/SettingsPage 也各自有 AppBar，导致在主页面内出现双层标题（如“时间线”重复）。

### 18.2 修复

1. `TimelinePage` 增加 `showAppBar` 参数，主页面内使用 `showAppBar: false`。
2. `SettingsPage` 增加 `showAppBar` 参数，主页面内使用 `showAppBar: false`（独立路由仍保留 AppBar）。
3. 保留“时间线标题双击回顶部”能力：
   - 把双击入口迁移到 MainPage 顶部标题；
   - 通过 `TimelineController` 暴露的 `scrollToTop` 回调触发列表滚动到顶部。

### 18.3 影响文件

- `lib/pages/main/main_page.dart`
- `lib/pages/timeline/timeline_page.dart`
- `lib/pages/timeline/timeline_controller.dart`
- `lib/pages/settings/settings_page.dart`

## 19. 文章图片过大与无法全屏修复（2026-05-18）

### 19.1 问题

1. 文章正文图片恢复为 `flutter_html` 默认渲染后，尺寸约束丢失，出现超大图片。
2. 先前可点击图片进入全屏预览的交互被回退，正文图片无法点开。

### 19.2 修复

1. 在 `ArticlePage` 的 `Html` 渲染中恢复 `ImageExtension` 自定义图片渲染：
   - 使用 `_ArticleInlineImage` 控件统一渲染正文图片；
   - 增加最大高度约束（`maxHeight: 320`）和圆角容器，避免超大撑开布局。
2. 恢复图片点击能力：
   - 正文图片点击触发 `controller.openImagePreview(imageUrl)`；
   - 跳转到 `ImageGalleryPage` 全屏查看，支持缩放与多图切换。
3. 保留图片加载稳态策略：
   - 使用 `CachedNetworkImage` + 统一请求头（`ArticleImageService.httpHeaders`）；
   - 失败态支持点击重试（retry stamp）。

### 19.3 影响文件

- `lib/pages/article/article_page.dart`

## 20. 文章左右滑动切换（2026-05-18）

### 20.1 需求

- 在文章详情页支持左右滑动切换上一篇/下一篇
- 手指跟随时页面要同步横向移动
- 竖向滚动时避免误触发
- 临近切页时要有明确视觉提示

### 20.2 实现

1. 文章详情页改为“单篇 / 序列”双模式：
   - 单篇：保持原有 `ArticlePageView`
   - 序列：使用 `PageView.builder` 承载多个 `ArticlePageView`
2. 打开文章时从来源列表传入 `sequence + index`：
   - 时间线列表
   - 订阅源详情列表
   - 文章搜索结果
3. 通过 PageView 自带横向拖动提供手势跟随和临近切页的预览效果。
4. AppBar 标题追加页码（如 `文章详情 · 2/8`）作为额外视觉提示。

### 20.3 影响文件

- `lib/pages/article/article_page.dart`
- `lib/pages/timeline/timeline_page.dart`
- `lib/pages/feed_detail/feed_detail_page.dart`
- `lib/pages/main/main_page.dart`

## 21. 已读失败重试队列（2026-05-18）

### 21.1 问题

- 文章标记已读时如果云端同步失败，本地虽然立即变为已读，但云端没有更新，导致其他客户端仍可能显示未读。

### 21.2 处理策略

1. 本地仍然立即生效，不回滚状态。
2. 同步失败时写入本地待同步队列（`ReadSyncService`）。
3. 在时间线和订阅源详情页进入/刷新时自动重试同步。
4. 标记为未读时会清理对应的待同步已读记录，避免后续误补同步。

### 21.3 影响文件

- `lib/services/read_sync_service.dart`
- `lib/pages/article/article_page.dart`
- `lib/pages/timeline/timeline_controller.dart`
- `lib/pages/feed_detail/feed_detail_page.dart`

## 22. 翻译中状态提示增强（2026-05-18）

### 22.1 问题

- 自动翻译 / 手动翻译处于 pending 时，原先只显示很小的旋转图标，卡片和详情页都不够显眼。

### 22.2 修复

1. 文章卡片的 pending 状态改成显眼徽标：`翻译中 + spinner`。
2. 文章详情页在标题区下方增加持续可见的状态条，提示“翻译中，完成后会自动显示译文”。
3. 保留按钮内的 pending 指示，形成双重提示。

### 22.3 影响文件

- `lib/pages/widgets/article_card.dart`
- `lib/pages/article/article_page.dart`

## 23. 摘要长度调整（2026-05-18）

### 23.1 调整内容

- 文章摘要提示改为 **100~300 字之间**。
- 自动摘要与手动摘要共用同一服务提示词，因此两处都会同时生效。

### 23.2 影响文件

- `lib/services/summary_service.dart`

## 24. 双击时间线底栏回顶部（2026-05-18）

### 24.1 调整内容

- 取消顶部标题的双击回顶部入口。
- 将回顶部手势迁移到**底部导航栏的“时间线”按钮**。
- 当前页已是时间线时，连续双击底栏“时间线”按钮触发滚动到顶部。

### 24.2 影响文件

- `lib/pages/main/main_page.dart`

## 26. 已知待修问题（2026-05-19 全库审查）

以下问题已确认但暂不修复，供下一位接手者参考。

### #1 🟡 loadMore() 翻页只拉 feeds，不追加 social/inbox

**位置**：`lib/pages/timeline/timeline_controller.dart` → `loadMore()` 方法

**现象**：用户滚到底部触发翻页时，只调用 `FeedHttp.getEntries(view: 0, ...)` 追加 feeds 条目。初始加载 `loadData()` 会并行拉取 feeds(0) + social(1) + inbox，但翻页时 social 和 inbox 不会继续追加。

**建议修复**：`loadMore()` 中也并行拉取 social 和 inbox，或者改为统一使用 `collectEntries`/`collectAllInboxEntries`。

### #2 🟡 loadData() feeds 拉取失败时静默返回

**位置**：`lib/pages/timeline/timeline_controller.dart` → `loadData()` 方法

**现象**：当 feeds 拉取返回 `LoadError` 但本地 `allArticles` 非空时，代码直接 `return`，不设置任何错误状态。用户看到的是旧缓存数据，不知道发生了网络故障。

**建议修复**：在 `return` 前加一个 `AppFeedback.warning('刷新失败', '显示的是本地缓存')` 提示。

### #3 🟢 StorageKeys 缺少 deepseek_api_key 常量

**位置**：`lib/common/constants/constants.dart` 和 `lib/services/translation_service.dart` / `summary_service.dart`

**现象**：`TranslationService` 和 `SummaryService` 使用魔法字符串 `'deepseek_api_key'` 读写 `GStorage.setting`，但 `StorageKeys` 类未定义对应常量。其他 key 均有常量定义。

**建议修复**：在 `StorageKeys` 中加 `static const String deepseekApiKey = 'deepseek_api_key';`，并替换两处引用。

### #4 🟢 ArticleCard._isTranslated 死代码

**位置**：`lib/pages/widgets/article_card.dart` → `_ArticleCardState`

**现象**：`_isTranslated` 字段在 `initState` 初始化，但 `_ArticleCardContent` 已通过 `Obx` 直接订阅 `TranslationService.recordOf()` 来响应翻译状态变化。`_isTranslated` 和 `onTranslateSuccess` 回调实际未被使用。

**建议修复**：移除 `_isTranslated` 字段、`onTranslateSuccess` 回调和 `_onTranslateSuccess` 方法。当前代码不产生 bug，仅为死代码。

### #5 🟢 HtmlChunkParser._extractSrc 双重 URL 规范化

**位置**：`lib/utils/html_chunk_parser.dart:258` → `_extractSrc()` 和 `lib/pages/article/widgets/html_chunk_card.dart` → `normalizedImageUrl`

**现象**：`_extractSrc` 调用 `ArticleContentUtils.imageUrlFromAttributes`（内部已调用 `ArticleImageService.normalizeImageUrl`），之后 `HtmlChunk.normalizedImageUrl` getter 又调用了一次 `normalizeImageUrl`。两次规范化幂等，不产生错误，但冗余。

**建议修复**：`_extractSrc` 直接返回原始 URL 字符串，归一化工作统一交给 `normalizedImageUrl` getter。

## 27. HTML 渲染管线修复（2026-05-19）

经过对 13 篇真实 Folo 文章的管线实测，发现并修复了 3 个渲染 BUG。

### 27.1 BUG-1 🔴：标题内图片/媒体被吞掉

**根因**：`_processElement` 对 `<h1>-<h6>` 直接调 `_stripInnerHtml` 剥离所有 HTML 标签。
**影响**：实测中 6/13 篇文章丢失图片（新智元 86 张仅剩 33 张，少数派 7 张剩 5 张）。
**修复**：
- 新增 `_hasMediaDescendant()` — 递归检测是否有媒体子节点
- 新增 `_headingTextOnly()` — 从含媒体的标题中仅提取文本
- 新增 `_emitMediaChildren()` — 对标题仅发媒体块（文本已在标题中）
- 标题有媒体 → 先发标题文本块，再递归发媒体块

### 27.2 BUG-2 🟡：空标题产生多余空白间距

**根因**：`<h3><span><br></span></h3>`（微信公众号做分隔线）剥离后为空字符串，仍渲染为标题块。
**影响**：新智元文章出现 14 处无意义大间距。
**修复**：标题文本 trim 后为空 → `return` 跳过不发块。

### 27.3 BUG-3 🟡：图片 CSS 百分比宽度误解析为 px

**根因**：`_extractDimensions` 正则 `width:\s*(\d+)\s*(px|em|rem)?` 不区分 `%` 单位，`100%` → 100px。
**影响**：微信来源文章图片 `style="width:100%"` 被当作 100px 处理，但实际无高度，仍无法确定比例。
**修复**：正则增加 `%|vw|vh` 单位匹配；百分比/视口单位 → 宽/高保持 `null` 交给渲染层 fallback（`AspectRatio`）。

### 27.4 附带修复：未知元素不再丢弃媒体

**根因**：`<a><img></a>` 等内联容器未被识别，`_processElement` 末尾只提取文本导致 `<img>` 丢失。
**修复**：未知元素改为递归子节点，而非仅提取文本。

### 27.5 影响文件

- `lib/utils/html_chunk_parser.dart` — 核心修复（+5 新方法，~80 行改动）

### 27.6 图片渲染完善（补充修复）

在 §27.1-27.4 的 HTML 解析修复之后，进一步排查了图片加载和微博格式问题：

1. **Blockquote/Table/RawHtml 内图片不使用 ImageExtension**
   - 根因：`HtmlChunkCard._buildBlockquote` / `_buildTable` / `_buildRawHtml` 使用裸 `Html()` 不加 `ImageExtension`，导致图片不走 `CachedNetworkImage` + 统一请求头。
   - 修复：提取共享 `_imageExtension()` 方法，应用到所有 `Html()` 调用点。
   - 影响文件：`lib/pages/article/widgets/html_chunk_card.dart`

2. **无 src 的空 img 标签产生空图片块**
   - 根因：微信文章标题区的 `<img style="width:100%" src="">`（CSS background 占位）被解析为 IMG 块，src 为空。
   - 修复：`_processElement` 中 `img` 处理分支增加 `if (src.isEmpty) return;`
   - 影响文件：`lib/utils/html_chunk_parser.dart`

3. **微信图片代理 `img2.jintiankansha.me` 已失效**
   - 实测：所有请求返回 403/400，原始微信 CDN 图片 `X-ErrNo: -106`（已过期）。
   - 结论：非代码问题，属数据源/RSS 源质量问题。已通过 `ImageExtension` 的错误占位符提供降级展示。
   - `ArticleImageService.normalizeImageUrl` 强制 HTTP→HTTPS 升级可能影响部分代理（已记录到 §26 #5，暂不修复）。

## 28. 视频播放支持（2026-05-19）

### 28.1 问题

Social 条目（Twitter）中的 `<video>` 标签无法播放，显示静态占位符。两类格式：
- 直接 `src`：`<video src="..." poster="..." width="..." height="...">`
- `<source>` 子元素：`<video poster="..."><source src="..."></video>`

### 28.2 Folo 官方方案

Folo 桌面端用 HTML5 `<video>` 标签直接播放 mp4，移动端用 `expo-video` 包。不依赖第三方视频平台 SDK。

### 28.3 实施

1. **Parser** (`html_chunk_parser.dart`)
   - `<video>` 含 `<source>` 子元素时从中提取 `src`
   - 提取 `poster` 属性存入 `HtmlChunk.posterSrc` 字段
   - `HtmlChunk` 新增 `posterSrc` 字段

2. **Renderer** (`html_chunk_card.dart`)
   - `_buildMediaPlaceholder` 改为 `Stack` 布局：
     - 底层：`CachedNetworkImage` 加载 poster 缩略图（经过 Folo 图片代理）
     - 中层：半透明黑色遮罩
     - 顶层：圆形播放按钮（`Icons.play_arrow_rounded`）
   - 点击 → `url_launcher` 打开 mp4 URL（系统播放器处理）

### 28.4 影响文件

- `lib/utils/html_chunk_parser.dart` — `HtmlChunk` + `posterSrc`，`_processElement` 视频分支
- `lib/pages/article/widgets/html_chunk_card.dart` — `_buildMediaPlaceholder` 重写

### 28.5 预实验数据

| 样本 | src | poster | dims |
|------|-----|--------|------|
| `social_video_12` (direct src) | ✅ | ✅ | 1500×844 |
| `social_video_14` (direct src) | ✅ | ✅ | 1920×1080 |
| `social_video_18` (`<source>`) | ✅ | ❌ | null×null |

### 27.7 预实验数据

| 指标 | 修复前 | 修复后 |
|------|--------|--------|
| 新智元 86 图文章 | 33 张图片 | 80 张图片 (+142%) |
| newsletter 17 图 | 13 张图片 | 16 张图片 (+23%) |
| 新智元空标题 | 14 处间隙 | 0 处 |
| 解析性能 | ~15ms | ~15ms（持平） |
| dart analyze | 0 issues | 0 issues |

## 29. AI 文章过滤系统（2026-05-20）

### 29.1 功能概述

基于 autofolo 的 `prompts.yaml` 过滤规则，用 DeepSeek JSON Output 对未读文章逐篇判定保留/拒绝。拒绝的文章进入审核页，用户可捞回或确认拒绝（自动标已读）。时间线卡片的拒文有橙色描边标记。

### 29.2 影响文件

- `lib/models/article.dart` — 新增 `isRejectedByAi`、`filterReason`、`filterReviewed`
- `lib/services/article_filter_service.dart` — **新建**。调 DeepSeek 判定，内置裁简版 autofolo prompt
- `lib/services/auto_filter_worker.dart` — **新建**。并行过滤队列，`queued/processing/done` 计数
- `lib/services/llm_config.dart` — 新增 filter 配置（模型 v4-pro / T 0.1 / 并发 16）
- `lib/pages/timeline/filter_review_page.dart` — **新建**。左右滑审核页，实时追加新结果
- `lib/pages/timeline/timeline_page.dart` — 顶栏常驻过滤入口横幅
- `lib/pages/settings/settings_page.dart` — 过滤 Prompt 编辑卡 + LLM 并发数配置
- `lib/pages/widgets/article_card.dart` — AI 拒文橙色边框
- `lib/pages/article/article_page.dart` — 标已读时清除过滤标记
- `lib/router/app_pages.dart` — 新增 `/filter-review` 路由

### 29.3 数据流

```
拉取未读 → enqueueMany → 16 并发 DeepSeek 判定
  → 拒文写入 DB (isRejectedByAi=true)
  → 审核页 Obx 监听 doneCount 自动追加
  → 用户右滑保留(清除标记) / 左滑确认拒绝(标已读)
  → filterReviewed 防重判
```

### 29.4 关键设计决策

- `filterReviewed` 标记解决"捞回后再刷新又被拒绝"的问题
- `upsertMany` 的 OR 合并逻辑与 `unReject` 直接写 DB 的冲突：unReject 绕过合并逻辑直接写 Hive
- 审核页不支持下拉刷新，只通过 `doneCount` 监听实时追加

## 30. LLM 并发数配置（2026-05-20）

- `LlmConfig` 新增 `concurrency` 字段，翻译/摘要/过滤各自独立
- 三个 Worker 的并发数从硬编码改为 `LlmConfig.load().concurrency`
- 设置页 LLM 卡新增「并发数」文本输入（1-1024）

## 31. 图片画廊修复（2026-05-20）

- **双击放大**：GestureDetector 从 InteractiveViewer 外层移到里层，避免手势冲突；缩放公式修正为 translate→scale→translate
- **捏合缩放**：InteractiveViewer 移到最外层，不再被 GestureDetector 阻止
- **图片全灰**：移除 AnimatedContainer + Opacity 包裹，直接使用 Scaffold
- **右下角"点按查看"**：删除
- **图片预加载**：文章打开时隐藏 1px Stack 同时发出所有图片请求
- **画廊分母错误**：审核页跳转文章时 sequence 改送审核列表自身，不再查全库

## 32. Inbox 空内容修复（2026-05-20）

- 根因：`chunks` 是 `late final List` 而非 `RxList`，`_fetchInboxContent` 更新后 Obx 不重建
- 修复：`chunks` 改为 `RxList<HtmlChunk>`，`_fetchInboxContent` → `_initContent` → `chunks.value = ...`
- Inbox 详情 API：`GET /entries/inbox?id=<entryId>` 返回完整 HTML 正文

## 33. 其他杂项修复（2026-05-20）

- **订阅源图标**：`LocalArticleDbService.upsertMany`/`setReadState` 补遗漏的 `feedImage` 字段
- **缓存 key 升级**：`cache.subscriptions.v1` → `v2` 强制刷新带 `image` 字段的订阅源数据
- **翻译超时**：60s → 300s；`rethrow` 改为 `return ErrorRecord`
- **FeedDetail 灰边框**：非拒文去掉 Card 描边
- **过滤横幅常驻**：移除 `if (count > 0)` 条件
- **FAB 半透明缩小**：`FloatingActionButton.small` + `Opacity(0.85)`
- **视频内联播放**：`video_player` + `InlineVideoPlayer` 三态组件
- **Folo 图片代理**：`ArticleImageService.toProxiedUrl()` 对微博/Pixiv 等 CDN 走 `img.folo.is`

## 34. 已读状态双向同步（2026-05-20）

- API 明确返回某篇文章为未读 → 清除本地 `readStatus` 旧标记，恢复未读
- 解决 inbox 文章被误标已读后永久无法恢复的问题
- 保护：`localOverride=false` 的用户手动标记不被覆盖
- `collectEntries` 移除 `maxPages` 硬上限，改为页不满/页空自然终止

## 35. 订阅源未读计数（2026-05-20）

- 三层未读计数：View / 分类 / 订阅源，各自求和
- inbox `feedId` 取错 JSON 路径→未读数为 0 的 Bug 修复：`item['feeds']['id'] ?? entry['inboxHandle']`
- `collectAllInboxEntries` limit 30 → 100

## 36. 图片修复补充（2026-05-20）

- `i.qbitai.com` 图片需 `Referer: https://www.qbitai.com/` → 加代理规则走 `img.folo.is`
- 图片画廊双击缩放加 `Matrix4Tween` + `AnimationController` (300ms easeOut)
- `normalizedContent` / `imageUrls` 从 `late final` 改为普通字段，支持 inbox 异步补内容

## 37. FeedDetail 对齐（2026-05-20）

- AppBar 标题显示未读计数（如 `量子位 (5)`）
- `showFeedTitle` 始终为 true，去底部空白

## 38. 性能优化 — 卡顿修复（2026-05-20）

- **静态 Dio 实例**：翻译/摘要/过滤三个服务各用 `static final _dio`，不再每条请求 `new Dio(BaseOptions(...))`
- **normalizeHtml 缓存**：`ArticleContentUtils.normalizeHtmlForEntry(entryId, html)` 用 LinkedHashMap 做 200 条 LRU 缓存，翻译和摘要各调一次但共享结果，同篇长文章不再 DOM 解析两遍
- **审核页增量推送**：过滤 Worker 完成一篇后通过 `onRejected` 回调直接推送单篇到审核列表（O(1)），替代 `ever(doneCount)` 每完成一篇扫全库 5000 篇（O(5000)）
- `onRejected` 回调仅在审核页可见时注册（`initState`/`deactivate`/`dispose`），后台不触发

## 39. ArticleStateNotifier 全局状态通知（2026-05-20）

- **新建** `lib/services/article_state_notifier.dart` — RxInt version 计数器
- 所有文章状态变更点统一调 `ArticleStateNotifier.tick()`
- 消费者页面用 `ever(version, ...)` 或 `Obx(() => version.value)` 感知刷新
- 解决：订阅源三层计数 stale、FeedDetail 列表 stale、时间线过滤横幅 stale
- 扩展方式：新页面只需加 listener，不需要修改 tick 点
- **计划升级 D 方案**：`tick(entryId, changeType)` 带变更类型，消费者省掉一次 `box.get`

## 40. UI 全面美化（2026-05-21，手动修订）

用户对所有页面进行了大量视觉打磨，涉及 13 个文件、+2456/-1148 行。

### 配色体系重构

- 移除 `DynamicColorBuilder`，`main.dart` 全面手写 `ColorScheme`（亮/暗各一套）
- 用 `dart:ui` 的 `PlatformDispatcher` 监听系统亮暗切换，手动管理 `themeMode`
- 状态栏设为全局透明，沉浸式体验
- 亮色方案：冷白基底 `#F8F8F9` + 多层次 `surfaceContainer` 灰阶
- 暗色方案：深灰 `#121212` 基底 + 多层次暗灰
- accent 使用 `#FF5C00`（品牌鲜橙），亮暗两套共用同一主色

### 时间线过滤入口重设计

- `_buildFilterBar` 从薄横条改为大圆角卡片：双层背景 + 圆形图标容器 + 双层文字（"AI 智能过滤" / "拦截了 N 篇… 去查看"）
- 使用自定义骨架屏 `_LocalTimelineSkeleton` 替代转菊花
- empty view 重排布局和文案

### 文章详情页重构

- `_MetadataSection`（来源 Chip）：图标 + 文字 + 箭头，圆角灰底可点击
- 标题区：InkWell 带圆角反馈，点击打开原文（无额外图标）
- `_ToolbarRow`：翻译/摘要芯片按钮紧凑排列，状态驱动（翻译中…/已译/翻译）
- `_Chip` 组件：激活态 `primary(0.12)` + 主色文字，非激活态灰底
- `_SummaryCard`：亮色用 `secondaryContainer(0.10)`，暗色用 `(0.15)`，极淡底色
- 空正文状态：`article_outlined` 图标 + "在浏览器中查看原文" 链接

### 文章卡片重设计

- 搜索入口 `ArticleSearchDelegate`→`_SearchBar` 重构为独立搜索栏
- `ArticleCard` 时间标签 `_buildTimeLabel` 重构
- 翻译/摘要图标布局调整
- AI 拒文标签（filterReason chip）样式统一

### 图片组件打磨

- `html_chunk_card.dart` 大量重构：inline image / video poster / 布局
- `image_gallery_page.dart` 重写：滑动关闭、缩放交互

### 订阅源页重构

- `_CategorySection` / `_ViewSection` / `_FeedAvatar` 全面重排
- 展开/折叠动画流畅度优化
- 三层缩进视觉层级明确

### FeedDetail 页重构

- `_FeedDetailPage` → `FeedDetailController` 分离
- 加载骨架、空状态、错误状态统一
- 文章列表卡片与主时间线视觉完全对齐

### 过滤审核页打磨

- `FilterReviewPage` 拒绝原因、按钮、进度条重构
- `Dismissible` 阈值调回 0.5（防误触）

### 反馈系统重构

- `feedback_toast.dart` 完全重写：Material 3 风格 SnackBar 替代旧 Toast

## 41. FeedDetail 已读筛选 + tick(entryId) 增量（2026-05-20）

- `ArticleStateNotifier.tick(entryId)` 替代无参 `tick()`，消费者改为增量更新单篇
- FeedDetail `_refreshFromLocal`：`box.get(entryId)` 读单篇 → 更新/移除列表（O(1) 替代 O(5000)）
- 订阅源 `refreshUnreadCounts`：增量 ±1 计数；首屏仍全量
- FeedDetail 新增 `readFilter`：仅未读/全部/仅已读三档，AppBar 弹出菜单切换
- `allArticles` 单独存全量（含已读），`articles` 按 filter 派生

## 42. 主页时间线重大交互与逻辑重构（2026-05-22）

- **生命周期解耦**：将 `TimelineController` 的注入时机从 `TimelinePage` 提前至 `MainPage.initState`。彻底修复了由于 `AppBar` 过早构建导致“启动时未读胶囊被隐藏，切 Tab 才能出现”的严重错位 Bug。
- **UI 重构（胶囊徽章）**：
  - 将未读/全部状态胶囊从右侧移动至 `AppBar` 的 `leading` (左上角)，实现了左控制、中标题、右搜索的完美对称美学。
  - 抛弃了 `PopupMenuButton` 粗糙的原生包裹，改用定制的 `Material` + `InkWell(borderRadius: 14)`，使点击产生的水波纹被完美“锁”在胶囊的圆角边缘内。
- **响应式数字修复**：在 `MainPage` 的顶栏  中加入了强制的 `allArticles.length` 依赖追踪，修复了底层 `allArticles.value` 更新但上方未读数字却不跳动的 GetX 响应式盲区。
- **顶部空档优化**：
  - 在 `timeline_page.dart` 中，当拦截数量为 0 时，过滤提示条彻底返回 `SizedBox.shrink()` 而非带 Padding 的空框。
  - 将 `ListView` 顶部的物理位移交由 `RefreshIndicator(edgeOffset: ...)` 处理，彻底消除了时间线滚动到顶部时巨大的死板空档。
- **网络全量同步容错（严格坚持两段式状态）**：
  - 恪守“绝对不显示不准确近似数据”的设计准则，在 `TimelineController.loadData` 中保留了 `collectEntries` 的全量拉取机制，保证 UI 变化只分为“启动读本地旧缓存”与“后台全量同步完并最终更新”两个确定状态。
  - 增加了严格的 `hasError` 检测。当面临成百上千条未读文章导致网络极大概率超时的情况下，不会再假死无反应，而是会静默弹出“同步未完成，部分拉取失败”的提示，增强了应用的健壮性。



## 43. 刷新圈反悔手势阻断优化（2026-05-22）

- **问题背景**：在带有半透明 AppBar 的设计中，当下拉刷新圈（未松手）再反悔向上推时，底层的 `ClampingScrollPhysics` 默认允许向上的滚动偏移量作用于列表，导致文章列表跟随手指滑动，钻入 AppBar 背后产生不自然的视觉穿透。
- **高阶边界拦截**：为了完美复刻 PiliPlus 中“刷新圈在屏幕上时列表完全冻结”的效果，引入了 `RefreshAwareScrollPhysics`。
  - 该方案彻底摒弃了在 `applyPhysicsToUserOffset` 阶段拦截（因其会导致 Flutter 底层计算出符号相反的 `overscroll` 进而让刷新圈死锁）。
  - 改为在最终边界判定 `applyBoundaryConditions` 阶段实施降维拦截：在 `dragOffset > 0` 的前提下，当发现用户尝试正向滚动（`value > pixels` 且位于顶部边界）时，强行将这部分合法的滚动量判决为越界（overscroll）。
- **联动效果**：
  - 判定越界使得列表本身的 `pixels` 被完美冻结在 `0`，纹丝不动。
  - 扣除下来的正向越界位移（`overscroll`）顺势传递给 `RefreshIndicator`，完美驱动了圆圈的顺滑回缩。
- **视觉配合**：
  - 同时移除了默认的边缘发光效果（`NoOverscrollIndicatorBehavior`），使得界面的操作反馈干净利落，达到指哪打哪的极佳手感。

## 44. 审核页重塑 — 实时状态药片（2026-05-23）

审核页（FilterReviewPage）从"判定中" + "全部确认"的旧设计完全重构：

- **AppBar 对齐主时间线**：居中标题"垃圾拦截"，0.5px 分割线，移除毛玻璃、判定徽标、"全部确认"按钮
- **状态药片行**（AppBar 与列表之间）：
  - `✋ N 篇待处理`：始终显示，0 篇时灰色，>0 篇时主色高亮
  - `🤖 N 篇判定中`：仅 LLM Worker 活跃时显示，灰色底 + 微型 spinner
- **实时性**：`humanCount` 由 `_articles.length` + `Obx` 驱动；`llmCount` 由 `AutoFilterWorker.queuedCount/processingCount`（RxInt）驱动；每篇卡片滑动后当场跳数
- **空状态终结感**：全部处理完时图标变绿对勾 + "处理完毕"
- **去除重复**：卡片自带拒文标签（§40），审核页不再额外显示判定原因
- **架构**：`_StatusPills` 和 `_LlmPill` 提升为文件级私有组件

### Vivo / OriginOS 桌面角标适配（待完成）

Vivo 提供私有 ContentProvider API（`content://com.vivo.abe.provider.launcher.notification.num`）可直写角标。`MainActivity.kt` 已实现 `tryVivoBadge` + 通知兜底，但当前不生效。排查方向：查看 logcat 返回码、确认系统桌面角标开关、验证权限未被静默拦截。详见 vivo 开发者文档。

## 45. 最终打磨与 v1.0.0-beta1 发布（2026-05-23）

### 导航栏玻璃质感调优

- 底栏背景从 `surface(0.8)` 降至 `surface(0.40)`，瀑布流内容更多穿透
- 选中态指示器从 `primary(0.15)` 提至 `primary(0.80)`，橙色标识更鲜明
- 顶栏 + 底栏均使用 `BackdropFilter(blur: 16)` 实现 iOS 风格毛玻璃

### 图片预加载性能修复

- 预加载隐藏 Stack 的 `CachedNetworkImage` 加上 `memCacheWidth: 150` + `maxWidthDiskCache: 300`
- 原因：不加约束时每张图片以原始分辨率解码（>2000px），20 张同时解码打爆主线程
- 效果：预加载仅解码 150px 缩略图，CPU 开销降 ~90%

### 文章详情页微调

- 标题下方移除"查看网页原文"文字 + 图标，标题本身已可点击跳转
- `_SummaryCard` 日间模式透明度从 `0.25` 降至 `0.10`，极淡底色改善可读性
- FAB `AnimatedScale` 回退（效果太细微无法感知）
- 审核页 `Dismissible` 阈值调整：`0.3` → `0.5`（防误触）

### 时间线过滤入口

- `_buildFilterBar` 移除 `if (count <= 0) return` 条件，入口始终可见
- 审核页"AI 判定"标签移除（卡片自带原因显示，防止重复）

### 分批提交与 v1.0.0-beta1

10 个 commit 按模块拆分：
1. `ColorScheme` 手写体系 + 移除 `DynamicColorBuilder`
2. `_FadeIndexedStack` 页面切换 + 底栏毛玻璃
3. 过滤入口卡片重设计 + 骨架屏
4. 审核页进度条 + 拒绝标签 + Dismissible
5. 文章页 `_ToolbarRow` + `_Chip` + 摘要卡 + 预加载 fix
6. 内联图片淡入 + 图片画廊手势
7. 文章卡片布局 + 搜索栏
8. FeedDetail 控制器分离 + 骨架加载
9. 订阅源三层缩进 + 动画打磨
10. 设置页副标题 + FeedbackToast 重写

Tag: `v1.0.0-beta1` — 功能完备（AI 过滤 + 翻译 + 摘要），橙色主题，全 UI 打磨。

## 46. 仓库管理规范（2026-05-23）

以下规则记录到文档中以便未来 AGENT 和协作者严格遵循。

### 一、提交粒度

- 一个 commit = 一个可独立回退的逻辑改动
- 禁止混合 "修 bug + 顺带改 UI"——示例反例：`f9b06ad`（物理引擎+图片画廊+导航三者合一）
- 不跨模块提交：`Refactor: ArticlePage` 不夹带 `FilterReviewPage` 的修改

### 二、Tag 管理

- **永不 force-update**：每次发版新建 tag，如 `v1.0.0-beta2`、`v1.0.0-rc1`
- beta 阶段可密集发（按天/按功能），RC 之后减速
- tag 注释写完整：日期 + 核心改动 + 对应的文档 § 编号
- 删除旧 tag 只在修复错打时使用，不使用 `-f` 覆盖

### 三、文档同步

- commit message 引用对应 § 编号（格式：`Refactor: xxx (§12)` 或 `Fix: xxx, see §8`）
- 每个功能完成 → 立即更新文档，不打完 tag 才补文档
- tag 打在文档和代码一起提交的 commit 上
- § 编号连续递增，不跳号、不重号

### 四、全局状态变更通知

- 任何涉及 `ArticleStateNotifier.tick()` 的改动，必须验证 6 个消费者页面全部正常：
  - `timeline_page` · `timeline_controller` · `filter_review_page` · `article_page` · `feed_detail_page` · `subscriptions_controller`
- 新增消费者时在本文档登记

### 五、Flutter 代码规范

- 结构性重构（>30 行）使用 `write_file` 一次性写入，避免 `edit_file` 重复修改导致括号混乱
- 嵌套超过 3 层的 widget 提取为独立 StatelessWidget 或辅助方法
- 修改全局 `ColorScheme` 后抽查 3 个以上页面

### 六、当前已知问题（非待修）

| 项 | 说明 |
|----|------|
| `f9b06ad` 提交粒度过大 | 混了物理引擎+图片画廊+导航，历史记录，不阻塞 |
| 硬编码色值 | `filter_review_page` 绿色滑动、`timeline_page` 琥珀过滤等为**语义色**，刻意设计，不为违规 |
| tag 被 force-update | `v1.0.0-beta1` 覆盖 3 次，从下个版本严格递增 |

## 47. 审核界面直接预览 AI 摘要（2026-05-23）

### 47.1 需求背景
用户希望在垃圾拦截（审核界面）中能够直接看到文章的摘要，而不需要点击进入详情页，以提高审核效率。同时要求正式时间线保持清爽，不显示摘要，并且要求 UI 具有设计美感，不破坏原有的极简卡片布局。

### 47.2 实现细节
- **`lib/pages/widgets/article_card.dart`**：
  - 新增 `showSummary` 控制参数（默认 `false`）。
  - 在卡片标题和底部元数据之间，新增摘要展示区块 `_buildSummaryBlock`。
  - 使用 `Obx` 响应式读取 `SummaryService.recordOf(entryId)`。
  - **优雅降级**：如果 AI 摘要已生成则显示内容；如果未生成则展示占位符 “AI 尚未生成摘要...”。
  - **视觉设计**：摘要前增加极小的引号图标（`Icons.format_quote_rounded`），使用浅色、半透明字体（`colorScheme.onSurfaceVariant.withValues(alpha: 0.8)`）和两行限制（`maxLines: 2`），形成类似“引述块”的设计，不喧宾夺主。
- **`lib/pages/timeline/filter_review_page.dart`**：
  - 在渲染被拦截的卡片时，显式传入 `showSummary: true` 开启摘要预览。
- **`lib/pages/timeline/timeline_page.dart`**：
  - 保持默认不传入该参数，维持正式时间线不显示摘要。

## 48. 通知角标 + 退后台（2026-05-23）

- 新增「通知与角标」设置区块：下拉选择桌面角标规则（显示数量 / 仅红点 / 关闭）
- 设置页重新布局：角标从翻译区块中独立出来
- 按安卓返回键退到后台（`PopScope` + `MainActivity.kt` 原生处理）
- 自写 `AppBadger`（MethodChannel `com.autofolo/badge`），完全移除 `flutter_app_badger` 依赖
- 自写 `MoveToBackground`（MethodChannel `com.autofolo/move_to_background`），完全移除 `move_to_background` 依赖
- 外来依赖归零，所有原生交互通过自写 MethodChannel + `MainActivity.kt` 控制

## 49. 正文加载 + 数据持久化（2026-05-23）

- **Inbox 文章首次打开**：`_fetchInboxContent()` 拉取后自动 `upsertOne()` 写入本地 DB，再次打开直接读库，不再重复拉取
- **Readability 抓取**：`fetchReadabilityContent()` 成功后同样持久化
- **加载中状态**：新增 `isFetchingContent` observable，空正文时显示旋转菊花 + "正在加载正文…"，替代原来的"暂无正文内容"闪烁

## 50. 译文/摘要内容传递修正（2026-05-23）

- `TranslationService.translateArticle()` 和 `SummaryService.summarizeArticle()` 新增 `overrideContent` 参数
- 文章页触发翻译/摘要时传入已标准化的 `normalizedContent`，确保 Readability 抓取后的长文被正确用于翻译和摘要

## 51. UI 细节打磨（2026-05-23）

- 审核页 AppBar 标题字体对齐主时间线（`FontWeight.bold, fontSize: 17`）
- 卡片内 AI 摘要预览 `maxLines` 从 2 扩展到 4
- 文章页 `CustomScrollView` 外包 `SelectionArea`，正文可选中复制
- 文章详情页 API 错误提示改用服务端返回的 `errorMessage`
- 主页面玻璃参数微调（模糊 20、透明度 0.50）

## 52. 大文章分块翻译 + 邮件表格扁平化（2026-05-23）

### 52.1 正文规整优化
- `ArticleContentUtils.normalizeHtml` 新增 `_flattenLayoutTables`：扁平化邮件 Newsletter 的 `<table>/<tr>/<td>` 布局壳，保留 `<th>` 数据表
- 效果：98KB 邮件 → ~67KB 纯内容，削减 ~30% 的无意义标签

### 52.2 分块翻译
- 阈值：归一化后正文 > 35KB 触发分块
- 切分：按 `<p>/<h1>/<li>/<blockquote>` 段落边界，每块 ≤12KB
- 并行：`Future.wait` 同时发出所有块的 LLM 请求，不等排列
- 拼接：第 1 块负责标题，所有块拼接 `translated_html`
- 失败隔离：单块失败不影响其余块，最终状态为 error 并保留已翻译部分

### 52.3 pending 瞬态不落盘
- `pending` 只在内存 `_records` map 中标记，不再通过 `GStorage.translations.put()` / `GStorage.summaries.put()` 写入磁盘
- 终态（`done` / `error`）正常落盘；`pending` 重启后自然消失，无需清理逻辑

### 52.4 未捕获异常兜底
- 翻译流程增加通用 `catch (e)` 处理器，防止非 Dio/Format/StateError 异常导致静默卡死

## 53. v1.0.0-beta2 发布（2026-05-23）

- 移除 `flutter_app_badger`、`move_to_background` 外部依赖，全部改为自写 MethodChannel
- Vivo/OriginOS 角标：ContentProvider 直写实现（待系统级验证）
- 自写 `AppBadger`、`MoveToBackground` 实用类
- 设置页新增「通知与角标」区块
- 翻译管线全链路稳定：启动自愈 → 表格扁平化 → 大文章分块并行 → 异常全面捕获

Tag: `v1.0.0-beta2`

## 48. 取消文章正文懒加载与重置列表增量刷新 (2026-05-24)

### 48.1 文章阅读进度条精准度优先 (取消懒加载)
- **背景**：原先使用 `SliverList.builder` 进行 HTML 节点的懒加载，以优化极长文章（多图、大 DOM）的首帧渲染和内存占用。但这导致底层的 `maxScrollExtent` 随着滚动不断动态变化，使得顶部“阅读进度条”出现跳动、不准或在未完全展开时无法达到 1.0 的问题。
- **决策**：经测试确认当前设备性能可以承受全量渲染后，去除了懒加载机制，将 `SliverList` 替换为 `SliverToBoxAdapter` + `Column`。
- **收益**：所有的 HTML 节点会在第一时间全部挂载，物理像素高度在首帧即可精确计算，彻底修复了阅读进度条的准确性问题。

### 48.2 FeedDetail 已读 O(1) 增量优化回退
- **背景**：曾为防止“点击已读”时出现卡顿，在 `feed_detail_page.dart` 中引入了 O(1) 的增量更新逻辑（仅对 `articles` 列表中对应索引作 `remove` 或局部替换），以规避触发 `_applyFilter()` 带来的 O(N) 级别全列表重构。
- **重新评估**：其实导致“点击已读卡顿”的真正元凶是**UI的整个 Widget Tree 重构**，而不是 Dart 层面的一层循环数组处理。由于我们在此前已经引入了 `ArticleStateNotifier` 以及局部 `Obx` 来控制重绘，UI 卡顿的根因已被解决。
- **决策**：回退了 O(1) 优化，恢复使用 `allArticles.refresh()` + 全量 `_applyFilter()` 的设计。这使得业务逻辑的代码更简洁、直观，并且在 Dart 处理内存数组极快的加持下，没有观察到性能衰退。

### 48.3 正文 DOM 懒加载设置开关
- **需求**：由于“一次性全量渲染”可能会在低端设备上引发卡顿或崩溃，我们需要把控制权交给用户。
- **实现**：在设置页 (`SettingsPage`) 新增“渲染与性能”区块，加入了“正文 DOM 懒加载”开关（默认关闭）。旁边的 Info 按钮会弹出对话框，向高级用户明确解释“内存开销”与“阅读进度条精确度”之间的技术博弈。状态保存在 `GStorage.setting` 中，由 `article_page.dart` 实时读取并动态切换 `SliverList` 或 `SliverToBoxAdapter` 机制。

## 49. 遗留问题与已知缺陷 (2026-05-24)

### 49.1 特定长文/复杂排版文章卡顿问题
- **现象**：文章《Tencent Open-Sources TencentDB Agent Memory: A 4-Tier Local Memory Pipeline for AI Agents》在渲染和滚动时存在轻微卡顿。
- **状态**：该问题在 `main` 和 `fix-video-summary-ui` 分支均存在，属于历史遗留或 `flutter_html` 针对特定 DOM 结构（可能是超长的 `<pre>`、深层嵌套或者特定的 Markdown 转换残留）的解析性能瓶颈。
- **建议**：后续需要对这类出现卡顿的特殊文章进行 Profile，分析是在布局计算 (Layout) 还是 `HtmlChunkParser` 解析时耗时过长。可能需要对 `flutter_html` 的特定组件进行缓存优化，或者针对超大代码块增加局部懒加载机制。

## 50. 深色模式 HTML 字体对比度动态调整 (2026-05-25)

### 50.1 问题背景
深色模式下，部分带有内联样式（如 `<span style="color: #333333;">`）的文章文本会因为与深色背景对比度过低而难以阅读。

### 50.2 核心实现
- **`lib/utils/color_parser.dart`**：实现了 CSS 颜色字符串到 Flutter `Color` 的解析，支持 hex, rgb, rgba 以及基础颜色名。全面适配了新版 Flutter Color API（如 `r`, `g`, `b`, `a` 属性）。
- **`lib/utils/html_contrast_utils.dart`**：
  - 基于 `package:html` 解析 HTML 片段。
  - 在深色模式下，检测内联 `color` 属性与 `Theme.of(context).colorScheme.surface` 的对比度。
  - 采用渐进式白平衡混合（`Color.lerp`）提亮过深的文字颜色，直到符合 WCAG 对比度阈值要求（4.5:1）。
  - 内置 LRU 缓存，避免列表滚动时重复解析同一 HTML 片段带来的性能损耗。
- **`lib/pages/article/widgets/html_chunk_card.dart`**：在 `Theme.of(context).brightness == Brightness.dark` 时，对 `paragraph`、`blockquote`、`table` 和 `rawHtml` 块调用 `HtmlContrastUtils.adjustHtmlContrast`，实现了无感的动态文字颜色自适应。

## 51. 遗留问题与已知缺陷 (2026-05-25)

### 51.1 审核列表快速刷新导致被拒文章“复活”问题
- **现象**：当在“垃圾拦截（审核列表）”中左滑拒绝文章（标记为已读并加入 `ReadSyncService` 后台同步队列）后，如果立刻切回时间线进行下拉刷新，刚才被拒绝的文章会再次出现在审核列表中。但如果等待较长时间（让后台同步完成）后再刷新，则不会出现此问题。
- **根因分析**：
  1. 左滑拒绝后，本地数据库标记该文章为已读，并将其放入 `ReadSyncService` 队列等待同步给 Folo API。
  2. 此时立即下拉刷新，向 Folo API 请求未读列表。由于后台同步还未完成，API 依然返回该文章状态为“未读”。
  3. `TimelineController._applyUnreadSnapshot` 中存在“双向同步兜底逻辑”：如果 API 返回未读，则强行删除本地的已读状态 (`GStorage.readStatus.delete`)。
  4. 随后 `LocalArticleDbService.upsertMany` 根据被删除后的空覆盖状态重新合并，将该文章状态重置为 `isRead: false`，但保留了它原本的 `isRejectedByAi: true` 标记。
  5. `FilterReviewPage` 监听到 `isRejectedByAi == true && !isRead`，导致该文章重新出现在审核列表中。
- **建议修复方向**：
  在 `TimelineController._applyUnreadSnapshot` 中删除本地已读状态前，应优先检查 `ReadSyncService.pendingReadItems`。

## 52. 性能优化（2026-05-25）

> 不影响任何现有功能与体验，`dart analyze` 零新增 warning，`flutter build apk --debug` 通过。

### 52.1 API 请求并行化
- `TimelineController.loadData()` 和 `FeedDetailController.loadData()` 中 3 个串行 `await`（feeds / social / inbox）改为 `Future.wait` 并行。
- `_refreshRecentReadWindow()` 中 2 个串行 `await`（feeds read / social read）同样改为 `Future.wait`。

### 52.2 正则表达式编译缓存
- `translation_service.dart`、`article_content_utils.dart`、`html_chunk_parser.dart`、`source_taxonomy.dart` 共 9 处方法内 `RegExp(...)` 提升为 `static final` 常量。

### 52.3 不必要的 ArticleModel 全字段拷贝消除
- `_mergeLocalReadState()` 增加守卫条件：只在本地 readState 与当前 `isRead` 不同时才创建新对象。
- `_updateReadStateInMemory()` 从 `.map()` 全列表遍历改为 `indexWhere` 单点定位。

### 52.4 searchSourceArticles 去拷贝
- `TimelineController.searchSourceArticles` 从 `allArticles.toList()` 改为直接返回 `allArticles` 引用。

### 52.5 骨架屏动画代码去重
- 新增 `ShimmerFadeList`（`lib/common/widgets/shimmer_card.dart`），三处独立动画控制器替换为统一组件。

### 52.6 Hive 批量写入
- `LlmConfig._save()` 中 6 次 `await put` 合并为 1 次 `await putAll`。

### 52.7 AI 过滤计数增量更新
- `TimelineController` 新增 `filterCount` RxInt，不再每次 rebuild 全量遍历 `readAllArticles()`。

### 52.8 FeedDetail 重复 upsertMany 移除
- `FeedDetailController._applyUnreadSnapshot()` 中 stale 清除循环前的冗余调用已删除。

### 52.9 ReadSyncService 指数退避
- 重试延迟从固定 `2s` 改为 `1s → 2s → 4s`（`Duration(seconds: 1 << retry)`）。

### 52.10 遗留问题（原 #51.1 续）
如果该文章存在于待同步队列中，说明它是用户刚刚执行的乐观更新（Optimistic Update），此时应信任本地已读状态，**不要**因为 API 返回了旧的“未读”状态就将其覆盖和删除。
