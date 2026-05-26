# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2026-05-26

### Added
- **Performance**: Introduced Isolate-based background rendering for HTML parsing, ensuring butter-smooth swipe transitions (60/120fps) between articles.
- **UI State Sync**: Re-engineered `TimelineController` to use fine-grained `ArticleStateNotifier` updates, resolving issues where AI-filtered or read articles would drift out of sync with the UI without a manual refresh.

### Fixed
- **Rich Text & Tables**: Re-integrated `flutter_html_table` and fixed HTML chunk parsing to restore missing tables and perfectly preserve inline rich text (bold, links, images) within lists.
- **Clickable Links**: Restored interactivity for nested links (e.g., inside headings or quotes) by using `outerHtml` parsing instead of stripping them down to pure text.
- **Inbox Caching**: Rewrote the `_trimOverflow` logic in `LocalArticleDbService` with a priority queue to protect ancient but unread Inbox items from being prematurely evicted by the 5000-article cache limit.
- **Adaptive Images**: Lifted the hardcoded `maxWidth` restriction for inline icons, fixing issues where WordPress emojis were stretched and ruined layout proportions.
