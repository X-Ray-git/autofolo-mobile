import 'package:flutter_test/flutter_test.dart';

import 'package:autofolo/utils/article_content_utils.dart';

void main() {
  test('normalizeHtml should remove empty blocks and normalize image src', () {
    const raw = '''
<div style="margin-top: 120px; padding-bottom: 40px;">
  <p>&nbsp;</p>
  <img data-src="//cdn.example.com/a.png" />
</div>
<p><br></p>
''';

    final normalized = ArticleContentUtils.normalizeHtml(raw);
    expect(normalized.contains('&nbsp;'), isFalse);
    expect(normalized.contains('margin-top'), isFalse);
    expect(normalized.contains('https://cdn.example.com/a.png'), isTrue);
  });

  test('extractImageUrls should dedupe and keep valid http/https urls', () {
    const html = '''
<img src="https://a.com/1.png" />
<img data-src="//a.com/1.png" />
<img src="javascript:alert(1)" />
<img src="https://a.com/2.png" />
''';

    final urls = ArticleContentUtils.extractImageUrls(html);
    expect(urls, ['https://a.com/1.png', 'https://a.com/2.png']);
  });
}
