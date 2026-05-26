# autofolo — Folo RSS 信息流 Android 阅读器

基于 Flutter 的 Folo RSS 聚合阅读客户端，致力于提供丝滑、原生的专属信息流体验，仅支持 Android。

## 功能矩阵

| 模块 | 功能 |
|------|------|
| **时间线** | 未读 / 全部 / 已读 三态视图，下拉刷新 + 无限滚动，游标分页 |
| **订阅源** | view → 分类 → 订阅源 三级分组，搜索，按分类/按源筛选文章 |
| **文章详情** | DOM 拆块懒加载渲染（60fps），图片画廊 + 手势缩放，内嵌图片防布局抖动 |
| **已读管理** | 文章内 FAB 标已读/恢复未读，本地 + Folo 云端双向同步，后台已读窗口补抓 |
| **翻译** | DeepSeek 逐篇 HTML 翻译（保留标签结构），按订阅源自动翻译开关，卡片翻译状态标记 |
| **摘要** | DeepSeek 100-300 字一句话摘要，后台自动摘要队列 |
| **本地库** | Hive 持久化文章库（5000 条上限），TTL 分级缓存（15min/30min/10min） |
| **搜索** | 文章标题/来源/作者搜索，订阅源搜索 |
| **安全** | URL 协议白名单校验，Cookie 注入安全过滤 |

## 技术栈

| 层 | 选型 |
|----|------|
| 框架 | Flutter 3.x / Dart 3.11+ |
| 状态管理 | GetX（Rx 响应式 + GetPage 路由） |
| 网络 | Dio + Cookie 拦截器 |
| 本地存储 | Hive（6 个 Box：setting / localCache / readStatus / articleDb / translations / summaries） |
| 渲染 | CustomScrollView + SliverList 逐块渲染 + RepaintBoundary 隔离 |
| HTML 解析 | `html` 包 DOM 遍历拆块 + Isolate 大文本异步 |
| 主题 | Material You / Dynamic Color |
| AI | DeepSeek API（翻译 v4-flash / 摘要 v4-flash） |

## 目录结构

```
lib/
├── main.dart                         # 应用入口
├── common/
│   ├── constants/constants.dart      # API 端点、配置常量
│   └── widgets/                      # 通用组件（Loading/Error/Empty/Toast/PillTag）
├── http/
│   ├── init.dart                     # Dio 单例、AuthInterceptor、LoadingState 密封类
│   └── feed_http.dart                # Folo REST API（订阅/条目/收件箱/已读）
├── models/
│   ├── article.dart                  # 文章模型（JSON/缓存序列化）
│   └── feed.dart                     # 订阅源模型（含 view/inbox 分类）
├── pages/
│   ├── main/main_page.dart           # 底部导航（时间线/订阅源/设置）
│   ├── timeline/                     # 时间线（三态视图 + 本地库合并）
│   ├── subscriptions/                # 订阅源（三级分组 + 搜索）
│   ├── feed_detail/                  # 按源/按分类筛选文章
│   ├── article/
│   │   ├── article_page.dart         # 文章详情（CustomScrollView + SliverList）
│   │   └── widgets/
│   │       ├── html_chunk_card.dart  # 逐块渲染组件（RepaintBoundary + 图片占位）
│   │       └── image_gallery_page.dart # 全屏图片画廊
│   ├── settings/settings_page.dart   # Token + API Key 配置
│   └── widgets/
│       ├── article_card.dart         # 文章卡片（彩色标签 + 翻译标记）
│       └── article_search_delegate.dart # 文章搜索
├── services/
│   ├── account_service.dart          # Token 存取 + 登录状态
│   ├── local_article_db_service.dart # 本地文章库 CRUD
│   ├── content_cache_service.dart    # TTL 分级缓存
│   ├── read_sync_service.dart        # 已读同步队列
│   ├── translation_service.dart      # DeepSeek 翻译
│   ├── summary_service.dart          # DeepSeek 摘要
│   ├── auto_translation_worker.dart  # 后台自动翻译队列
│   ├── auto_summary_worker.dart      # 后台自动摘要队列
│   ├── feed_translation_settings_service.dart # 按源翻译开关
│   └── article_image_service.dart    # 图片 URL 规范化 + 请求头
├── utils/
│   ├── storage.dart                  # Hive Box 初始化
│   ├── html_chunk_parser.dart        # HTML 块级拆分解器（Isolate 可选）
│   ├── article_content_utils.dart    # HTML 清洗 + 图片提取
│   ├── source_taxonomy.dart          # view 分类标签/颜色
│   └── security_utils.dart           # URL 安全校验
└── router/
    └── app_pages.dart                # GetX 路由表
```

## 快速开始

```bash
flutter pub get
flutter run
# 或直接构建 APK
flutter build apk --debug
```

## 首次配置

1. 打开应用 → 设置页
2. 填写 **Folo API 凭据**（Session Token / Client ID / Session ID）— 从 Folo Web 应用 Cookie 获取
3. 填写 **DeepSeek API Key**（翻译和摘要功能需要）

## API 端点

| 端点 | 方法 | 用途 |
|------|------|------|
| `/subscriptions` | GET | 订阅源列表 |
| `/entries` | POST | 文章条目（view=0 feeds, view=1 social） |
| `/entries/inbox` | POST | 收件箱条目 |
| `/inboxes/list` | GET | 收件箱列表 |
| `/reads` | POST / DELETE | 标已读 / 标未读 |

## 质量检查

```bash
dart analyze lib/
flutter test
```

## 交接文档

详见 [`AGENT_HANDOFF.md`](AGENT_HANDOFF.md) — 包含完整的功能演进历史、实现细节、文件清单和接手建议。
