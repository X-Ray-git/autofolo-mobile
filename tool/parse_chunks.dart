import 'dart:io';
import 'dart:math';
import 'dart:convert';

import 'package:autofolo/utils/html_chunk_parser.dart';
import 'package:autofolo/utils/article_content_utils.dart';

void main() {
  final dir = Directory('/tmp/folo_sim/html');
  final out = File('/tmp/folo_sim/chunk_reports.json');
  final List reports = [];

  if (!dir.existsSync()) {
    print('NO_HTML_DIR');
    return;
  }

  for (final ent in dir.listSync()) {
    if (ent is File && ent.path.endsWith('.html')) {
      final content = ent.readAsStringSync();
      final normalized = ArticleContentUtils.normalizeHtml(content);
      final chunks = HtmlChunkParser.parseSync(normalized);
      final chunkInfos = chunks.map((c) {
        final type = c.type.toString().split('.').last;
        var preview = c.content.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (preview.length > 160) preview = preview.substring(0, 160);
        return {'type': type, 'preview': preview};
      }).toList();
      reports.add({'file': ent.path.split('/').last, 'count': chunkInfos.length, 'chunks': chunkInfos});
    }
  }

  out.writeAsStringSync(json.encode(reports), mode: FileMode.write);
  print('WROTE ${out.path}');
}
