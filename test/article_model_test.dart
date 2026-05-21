import 'package:flutter_test/flutter_test.dart';

import 'package:autofolo/models/article.dart';

void main() {
  test('fromEntryJson should parse nested entry/feed fields', () {
    final article = ArticleModel.fromEntryJson({
      'entries': {
        'id': 'e-1',
        'title': 'Hello',
        'url': 'https://example.com',
        'publishedAt': '2026-01-01T00:00:00.000Z',
        'read': false,
        'author': 'Tester',
        'media': [
          {'url': 'https://example.com/a.png'},
        ],
      },
      'feeds': {'id': 'f-1', 'title': 'FeedA'},
    }, subscriptionCategory: 'Tech');

    expect(article.entryId, 'e-1');
    expect(article.feedId, 'f-1');
    expect(article.feedTitle, 'FeedA');
    expect(article.subscriptionCategory, 'Tech');
    expect(article.imageUrl, 'https://example.com/a.png');
  });
}
