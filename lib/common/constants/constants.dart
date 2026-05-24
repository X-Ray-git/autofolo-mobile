abstract final class ApiConstants {
  static const String baseUrl = 'https://api.folo.is';
  static const String subscriptions = '/subscriptions';
  static const String entries = '/entries';
  static const String entriesInbox = '/entries/inbox';
  static const String entriesInboxDetail = '/entries/inbox'; // GET ?id=
  static const String inboxesList = '/inboxes/list';
  static const String reads = '/reads';
}

abstract final class AppConstants {
  static const String appName = 'autofolo';
  static const int defaultPageSize = 50;
  static const int defaultTimeout = 30000;
  static const int defaultReadSyncWindowDays = 2;
}

abstract final class StorageKeys {
  static const String sessionToken = 'session_token';
  static const String clientId = 'client_id';
  static const String sessionId = 'session_id';
  static const String localCache = 'localCache';
  static const String setting = 'setting';
  static const String readStatus = 'readStatus';
  static const String readSyncWindowDays = 'read_sync_window_days';
  static const String badgeStrategy = 'badge_strategy';
  static const String articleLazyLoading = 'article_lazy_loading';
}
