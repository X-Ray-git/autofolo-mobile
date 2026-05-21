import '../utils/security_utils.dart';

abstract final class ArticleImageService {
  static const String _proxyBase = 'https://img.folo.is';

  /// Folo 官方图片代理域名规则（从 Folo 源码 img-proxy.ts 提取）
  /// 仅对需要特定 Referer 才能访问的 CDN 走代理
  static final List<_ProxyRule> _proxyRules = [
    _ProxyRule(
      domainPattern: RegExp(r'^https://\w+\.sinaimg\.cn'),
      referer: 'https://weibo.com',
    ),
    _ProxyRule(
      domainPattern: RegExp(r'^https://i\.pximg\.net'),
      referer: 'https://www.pixiv.net',
    ),
    _ProxyRule(
      domainPattern: RegExp(r'^https://cdnfile\.sspai\.com'),
      referer: 'https://sspai.com',
    ),
    _ProxyRule(
      domainPattern: RegExp(r'^https://(?:\w|-)+\.cdninstagram\.com'),
      referer: 'https://www.instagram.com',
    ),
    _ProxyRule(
      domainPattern: RegExp(r'^https://[\w-]+\.xhscdn\.com'),
      referer: 'https://www.xiaohongshu.com',
    ),
    _ProxyRule(
      domainPattern: RegExp(r'^https://sp1\.piokok\.com'),
      referer: 'https://www.piokok.com',
      force: true,
    ),
    _ProxyRule(
      domainPattern: RegExp(r'^https://[\w-]+\.qbitai\.com'),
      referer: 'https://www.qbitai.com',
    ),
  ];

  /// 默认请求头（不含 Referer——Folo 代理会按域名补正确的 Referer）
  static const Map<String, String> httpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36',
    'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
  };

  static String? normalizeImageUrl(String? rawUrl) {
    if (rawUrl == null) return null;
    var normalized = rawUrl.trim();
    if (normalized.isEmpty) return null;

    if (normalized.startsWith('//')) {
      normalized = 'https:$normalized';
    }
    normalized = normalized.replaceAll(' ', '%20');

    var uri = SecurityUtils.parseHttpUrl(normalized);
    if (uri == null) return null;

    // 许多 RSS 源的图片链接返回 http，强制升级到 https 提升可达率。
    if (uri.scheme.toLowerCase() == 'http') {
      uri = uri.replace(scheme: 'https');
    }
    return uri.toString();
  }

  /// 对需要特定 Referer 的 CDN 图片，通过 Folo 官方代理加载
  static String? toProxiedUrl(String? rawUrl) {
    final normalized = normalizeImageUrl(rawUrl);
    if (normalized == null) return null;

    for (final rule in _proxyRules) {
      if (rule.domainPattern.hasMatch(normalized)) {
        final encoded = Uri.encodeComponent(normalized);
        return '$_proxyBase?url=$encoded&width=&height=';
      }
    }
    return normalized;
  }

  static String appendRetryStamp(String imageUrl, int retryCount) {
    if (retryCount <= 0) return imageUrl;
    final sep = imageUrl.contains('?') ? '&' : '?';
    return '$imageUrl${sep}retry=$retryCount';
  }
}

class _ProxyRule {
  final RegExp domainPattern;
  final String referer;
  final bool force;

  const _ProxyRule({
    required this.domainPattern,
    required this.referer,
    this.force = false,
  });
}
