// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../../../common/widgets/feedback_toast.dart';
import '../../../services/article_image_service.dart';

class ImageGalleryPage extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const ImageGalleryPage({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  @override
  State<ImageGalleryPage> createState() => _ImageGalleryPageState();
}

class _ImageGalleryPageState extends State<ImageGalleryPage> {
  late final PageController _controller;
  late int _currentIndex;
  bool _isZoomed = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onZoomChanged(bool zoomed) {
    if (_isZoomed != zoomed) setState(() => _isZoomed = zoomed);
  }

  void _showImageMenu(String imageUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white70),
              title: const Text('分享', style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.pop(ctx);
                _shareImage(imageUrl);
              },
            ),
            ListTile(
              leading: const Icon(Icons.save_alt, color: Colors.white70),
              title:
                  const Text('保存图片', style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.pop(ctx);
                _saveImage(imageUrl);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.white70),
              title:
                  const Text('复制链接', style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: imageUrl));
                AppFeedback.success('已复制', '图片链接已复制到剪贴板');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareImage(String url) async {
    try {
      final file = await _downloadToTemp(url);
      if (file != null) {
        await Share.shareXFiles([XFile(file.path)]);
      } else {
        await Share.share(url);
      }
    } catch (e) {
      AppFeedback.error('分享失败', e.toString());
    }
  }

  Future<void> _saveImage(String url) async {
    try {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        AppFeedback.warning('权限不足', '请授予存储权限后重试');
        return;
      }
      final bytes = await _downloadBytes(url);
      if (bytes != null) {
        final result = await ImageGallerySaverPlus.saveImage(bytes);
        if (result != null && result['isSuccess'] == true) {
          AppFeedback.success('已保存', '图片已保存到相册');
        } else {
          AppFeedback.error('保存失败', '请稍后重试');
        }
      }
    } catch (e) {
      AppFeedback.error('保存失败', e.toString());
    }
  }

  Future<File?> _downloadToTemp(String url) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/share_img_${url.hashCode}.jpg');
      if (!file.existsSync()) {
        final bytes = await _downloadBytes(url);
        if (bytes != null) await file.writeAsBytes(bytes);
      }
      return file.existsSync() ? file : null;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null) {
        return Uint8List.fromList(response.data!);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragStart: _isZoomed ? null : (_) {},
        onVerticalDragUpdate: _isZoomed
            ? null
            : (details) {
                setState(() => _dragOffset += details.delta.dy);
              },
        onVerticalDragEnd: _isZoomed
            ? null
            : (details) {
                if (_dragOffset.abs() > MediaQuery.of(context).size.height * 0.2) {
                  Navigator.of(context).pop();
                } else {
                  setState(() => _dragOffset = 0);
                }
              },
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              physics:
                  _isZoomed ? const NeverScrollableScrollPhysics() : null,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemCount: widget.imageUrls.length,
              itemBuilder: (context, index) {
                return _ZoomableImage(
                  imageUrl: widget.imageUrls[index],
                  onZoomChanged: _onZoomChanged,
                  onLongPress: () =>
                      _showImageMenu(widget.imageUrls[index]),
                );
              },
            ),
            Positioned(
              top: topPadding + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 28),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (!_isZoomed && widget.imageUrls.length > 1)
              Positioned(
                bottom: bottomPadding + 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_currentIndex + 1} / ${widget.imageUrls.length}',
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  final String imageUrl;
  final void Function(bool zoomed)? onZoomChanged;
  final VoidCallback? onLongPress;

  const _ZoomableImage({
    required this.imageUrl,
    this.onZoomChanged,
    this.onLongPress,
  });

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transform = TransformationController();
  int _retryCount = 0;
  bool _isZoomed = false;
  AnimationController? _zoomAnim;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
    _zoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _zoomAnim?.dispose();
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transform.value.getMaxScaleOnAxis();
    final zoomed = scale > 1.01;
    if (zoomed != _isZoomed) {
      _isZoomed = zoomed;
      widget.onZoomChanged?.call(zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth = (MediaQuery.of(context).size.width * dpr).round();

    return InteractiveViewer(
      transformationController: _transform,
      minScale: 1,
      maxScale: 5,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onDoubleTapDown: (details) {
          final current = _transform.value.getMaxScaleOnAxis();
          final target = current > 1.1 ? 1.0 : 3.2;
          final fp = details.localPosition;

          final targetMatrix = Matrix4.identity()
            ..translate(fp.dx, fp.dy)
            ..scale(target)
            ..translate(-fp.dx, -fp.dy);

          final beginMatrix = Matrix4.copy(_transform.value);
          final tween = Matrix4Tween(begin: beginMatrix, end: targetMatrix);

          _zoomAnim!
            ..reset()
            ..animateTo(1.0, curve: Curves.easeOut).then((_) {
              _transform.value = targetMatrix;
            });
          _zoomAnim!.addListener(() {
            _transform.value = tween.transform(_zoomAnim!.value);
          });
          widget.onZoomChanged?.call(target > 1.1);
        },
        onLongPress: widget.onLongPress,
        child: Center(
          child: CachedNetworkImage(
            cacheKey: 'v2_${widget.imageUrl}',
            imageUrl: ArticleImageService.appendRetryStamp(
                widget.imageUrl, _retryCount),
            fit: BoxFit.contain,
            httpHeaders: ArticleImageService.httpHeaders,
            memCacheWidth: cacheWidth,
            maxWidthDiskCache: cacheWidth * 2,
            fadeInDuration: const Duration(milliseconds: 80),
            fadeOutDuration: const Duration(milliseconds: 80),
            placeholder: (context, url) => const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            errorWidget: (context, url, error) => GestureDetector(
              onTap: () => setState(() => _retryCount++),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, color: Colors.white70, size: 42),
                  SizedBox(height: 8),
                  Text('加载失败，点击重试',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
