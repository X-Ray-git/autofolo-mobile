import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

abstract final class GStorage {
  static late final Box<dynamic> setting;
  static late final Box<dynamic> localCache;
  static late final Box<dynamic> readStatus;
  static late final Box<dynamic> articleDb;
  static late final Box<dynamic> translations;
  static late final Box<dynamic> summaries;

  static Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    await Hive.initFlutter('${appDir.path}/hive');

    setting = await Hive.openBox('setting');
    localCache = await Hive.openBox('localCache');
    readStatus = await Hive.openBox(
      'readStatus',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 10,
    );
    articleDb = await Hive.openBox(
      'articleDb',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 50,
    );
    translations = await Hive.openBox(
      'translations',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 30,
    );
    summaries = await Hive.openBox(
      'summaries',
      compactionStrategy: (entries, deletedEntries) => deletedEntries > 30,
    );
  }

  static Future<void> close() async {
    await Future.wait([
      setting.close(),
      localCache.close(),
      readStatus.close(),
      articleDb.close(),
      translations.close(),
      summaries.close(),
    ]);
  }
}
