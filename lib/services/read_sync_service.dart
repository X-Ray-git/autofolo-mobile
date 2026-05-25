import '../http/feed_http.dart';
import '../http/init.dart';
import '../utils/storage.dart';

class PendingReadSyncItem {
  final String entryId;
  final bool isInbox;
  final int updatedAt;

  const PendingReadSyncItem({
    required this.entryId,
    required this.isInbox,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'entryId': entryId,
    'isInbox': isInbox,
    'updatedAt': updatedAt,
  };

  factory PendingReadSyncItem.fromJson(Map<dynamic, dynamic> json) {
    return PendingReadSyncItem(
      entryId: json['entryId'] as String? ?? '',
      isInbox: json['isInbox'] as bool? ?? false,
      updatedAt: json['updatedAt'] as int? ?? 0,
    );
  }
}

/// 管理本地待同步的已读队列
abstract final class ReadSyncService {
  static const String _pendingReadIdsKey = 'pending_read_items';
  static Future<void>? _syncInFlight;

  static List<PendingReadSyncItem> get pendingReadItems {
    final raw = GStorage.localCache.get(_pendingReadIdsKey);
    if (raw is! List) return <PendingReadSyncItem>[];

    return raw
        .whereType<Object?>()
        .map((e) {
          if (e is Map) {
            return PendingReadSyncItem.fromJson(Map<dynamic, dynamic>.from(e));
          }
          final id = e?.toString() ?? '';
          if (id.isEmpty) {
            return null;
          }
          return PendingReadSyncItem(entryId: id, isInbox: false, updatedAt: 0);
        })
        .whereType<PendingReadSyncItem>()
        .toList();
  }

  static void enqueue(String entryId, {required bool isInbox}) {
    final normalized = entryId.trim();
    if (normalized.isEmpty) return;

    final items = <String, PendingReadSyncItem>{
      for (final item in pendingReadItems) item.entryId: item,
    };
    items[normalized] = PendingReadSyncItem(
      entryId: normalized,
      isInbox: isInbox,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    GStorage.localCache.put(
      _pendingReadIdsKey,
      items.values.map((item) => item.toJson()).toList()..sort((a, b) {
        final left = a['updatedAt'] as int? ?? 0;
        final right = b['updatedAt'] as int? ?? 0;
        return left.compareTo(right);
      }),
    );
  }

  static void removeMany(Iterable<String> entryIds) {
    final removeSet = entryIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (removeSet.isEmpty) return;

    final items = pendingReadItems
        .where((item) => !removeSet.contains(item.entryId))
        .toList();
    if (items.isEmpty) {
      clear();
      return;
    }

    GStorage.localCache.put(
      _pendingReadIdsKey,
      items.map((e) => e.toJson()).toList(),
    );
  }

  static Future<void> syncPendingReads() {
    if (_syncInFlight != null) return _syncInFlight!;
    _syncInFlight = _syncPendingReadsInternal().whenComplete(() {
      _syncInFlight = null;
    });
    return _syncInFlight!;
  }

  static void clear() {
    GStorage.localCache.delete(_pendingReadIdsKey);
  }

  static Future<void> _syncPendingReadsInternal() async {
    final items = pendingReadItems;
    if (items.isEmpty) return;

    final grouped = <bool, List<PendingReadSyncItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.isInbox, () => <PendingReadSyncItem>[]);
      grouped[item.isInbox]!.add(item);
    }

    for (final entry in grouped.entries) {
      final ids = entry.value.map((item) => item.entryId).toList();
      for (var i = 0; i < ids.length; i += 50) {
        final end = i + 50 > ids.length ? ids.length : i + 50;
        final chunk = ids.sublist(i, end);
        var ok = false;
        for (int retry = 0; retry < 3; retry++) {
          final result = await FeedHttp.markRead(
            entryIds: chunk,
            isInbox: entry.key,
          );
          if (result is Success<void>) {
            ok = true;
            break;
          }
          if (retry < 2) await Future.delayed(Duration(seconds: 1 << retry));
        }
        if (ok) removeMany(chunk);
      }
    }
  }
}
