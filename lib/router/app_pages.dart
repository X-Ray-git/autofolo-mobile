import 'package:get/get.dart';

import '../pages/main/main_page.dart';
import '../pages/article/article_page.dart';
import '../pages/feed_detail/feed_detail_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/timeline/filter_review_page.dart';

class Routes {
  Routes._();

  static const String main = '/';
  static const String article = '/article';
  static const String feedDetail = '/feed-detail';
  static const String settings = '/settings';
  static const String filterReview = '/filter-review';
}

List<GetPage> get appPages => [
  GetPage(name: Routes.main, page: () => const MainPage()),
  GetPage(
    name: Routes.article,
    page: () => const ArticlePage(),
    transition: Transition.rightToLeft,
  ),
  GetPage(
    name: Routes.feedDetail,
    page: () => const FeedDetailPage(),
    transition: Transition.rightToLeft,
  ),
  GetPage(
    name: Routes.settings,
    page: () => const SettingsPage(),
    transition: Transition.rightToLeft,
  ),
  GetPage(
    name: Routes.filterReview,
    page: () => const FilterReviewPage(),
    transition: Transition.rightToLeft,
  ),
];
