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
  double _dragScale = 1.0;
  double _bgOpacity = 1.0;
  bool _isAnimatingBack = false;

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

  // ─── 沉浸式下拉退出手势逻辑 ───

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isZoomed) return;
    setState(() {
      _isAnimatingBack = false;
    });
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isZoomed) return;
    setState(() {
      _dragOffset += details.delta.dy;
      // 计算缩放比例 (滑动越远，图片越小，最小缩放至 0.7)
      _dragScale = (1.0 - (_dragOffset.abs() / 1000)).clamp(0.7, 1.0);
      // 计算背景透明度 (滑动越远，背景越透明)
      _bgOpacity = (1.0 - (_dragOffset.abs() / 600)).clamp(0.0, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isZoomed) return;
    // 如果滑动距离超过屏幕的 15%，或者滑动速度极快，则触发退出
    if (_dragOffset.abs() > MediaQuery.of(context).size.height * 0.15 ||
        details.velocity.pixelsPerSecond.dy.abs() > 800) {
      Navigator.of(context).pop();
    } else {
      // 否则顺滑回弹到中心位置
      setState(() {
        _isAnimatingBack = true;
        _dragOffset = 0;
        _dragScale = 1.0;
        _bgOpacity = 1.0;
      });
    }
  }

  // ─── 现代化的长按悬浮菜单 ───

  void _showImageMenu(String imageUrl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E).withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.white),
                title: const Text('分享图片', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _shareImage(imageUrl);
                },
              ),
              const Divider(height: 1, color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.save_alt_rounded, color: Colors.white),
                title: const Text('保存到相册', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveImage(imageUrl);
                },
              ),
              const Divider(height: 1, color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.link_rounded, color: Colors.white),
                title: const Text('复制链接', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                onTap: () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: imageUrl));
                  AppFeedback.success('已复制', '图片链接已复制到剪贴板');
                },
              ),
            ],
          ),
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light, // 强制状态栏在暗色沉浸下使用白色图标
      child: Scaffold(
        backgroundColor: Colors.transparent, // 背景设为透明，颜色交由 AnimatedContainer 控制
        body: AnimatedContainer(
          duration: _isAnimatingBack ? const Duration(milliseconds: 250) : Duration.zero,
          curve: Curves.easeOut,
          color: Colors.black.withValues(alpha: _bgOpacity),
          child: GestureDetector(
            onVerticalDragStart: _onVerticalDragStart,
            onVerticalDragUpdate: _onVerticalDragUpdate,
            onVerticalDragEnd: _onVerticalDragEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 核心图片轮播区 (附带拖拽缩放与位移)
                AnimatedContainer(
                  duration: _isAnimatingBack
                      ? const Duration(milliseconds: 250)
                      : Duration.zero,
                  curve: Curves.easeOut,
                  transform: Matrix4.identity()
                    ..translate(0.0, _dragOffset)
                    ..scale(_dragScale, _dragScale),
                  transformAlignment: Alignment.center,
                  child: PageView.builder(
                    controller: _controller,
                    physics: _isZoomed
                        ? const NeverScrollableScrollPhysics()
                        : const BouncingScrollPhysics(),
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
                ),
                
                // 顶部的现代控制栏 (包含返回按钮和进度指示器)
                Positioned(
                  top: topPadding + 12,
                  left: 16,
                  right: 16,
                  child: AnimatedOpacity(
                    opacity: _bgOpacity,
                    duration: _isAnimatingBack
                        ? const Duration(milliseconds: 250)
                        : Duration.zero,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // 居中的页面指示器
                        if (widget.imageUrls.length > 1)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '${_currentIndex + 1} / ${widget.imageUrls.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        // 左侧圆润的关闭按钮
                        Align(
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            onTap: () => Navigator.of(context).pop(),
                            customBorder: const CircleBorder(),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  color: Colors.white, size: 20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            fadeInDuration: const Duration(milliseconds: 250),
            fadeOutDuration: const Duration(milliseconds: 80),
            placeholder: (context, url) => const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            ),
            errorWidget: (context, url, error) => GestureDetector(
              onTap: () => setState(() => _retryCount++),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image_rounded, color: Colors.white70, size: 42),
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