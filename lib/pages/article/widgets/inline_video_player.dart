import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../services/article_image_service.dart';
import 'fullscreen_video_page.dart';

/// 内联视频播放器 — poster → 加载 → 播放（含进度条 + 拖拽定位）
class InlineVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? posterUrl;
  final double aspectRatio;

  const InlineVideoPlayer({
    super.key,
    required this.videoUrl,
    this.posterUrl,
    this.aspectRatio = 16 / 9,
  });

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitializing = false;
  bool _hasError = false;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?..removeListener(_onControllerUpdate)..dispose();
    super.dispose();
  }

  void _onControllerUpdate() => setState(() {});

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_showControls && (_controller?.value.isPlaying ?? false)) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showControls && (_controller?.value.isPlaying ?? false)) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _enterFullscreen() {
    if (_controller == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullscreenVideoPage(controller: _controller!),
      ),
    );
  }

  Future<void> _initAndPlay() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      final uri = Uri.tryParse(widget.videoUrl);
      if (uri == null) {
        setState(() => _hasError = true);
        return;
      }

      final controller = VideoPlayerController.networkUrl(uri);
      _controller = controller;
      await controller.initialize();
      controller.addListener(_onControllerUpdate);
      await controller.play();
      controller.setLooping(true);
      setState(() {});
      _startHideTimer();
    } catch (e) {
      setState(() => _hasError = true);
      _controller?.dispose();
      _controller = null;
    }
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _hideTimer?.cancel();
      _showControls = true;
    } else {
      _controller!.play();
      _startHideTimer();
    }
    setState(() {});
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    _startHideTimer();
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inMinutes}:$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 正在播放或已就绪 → 显示视频
    if (_controller != null && _controller!.value.isInitialized) {
      final pos = _controller!.value.position;
      final dur = _controller!.value.duration;

      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: GestureDetector(
            onTap: _toggleControls,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(_controller!),

                // 控制层
                AnimatedOpacity(
                  opacity: _showControls ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // 顶部渐变条
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.4),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),

                      // 底部控制栏
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.6),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 可拖拽进度条
                            VideoProgressIndicator(
                              _controller!,
                              allowScrubbing: true,
                              colors: VideoProgressColors(
                                playedColor: cs.primary,
                                bufferedColor:
                                    cs.onSurface.withValues(alpha: 0.3),
                                backgroundColor:
                                    cs.onSurface.withValues(alpha: 0.15),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            const SizedBox(height: 6),
                            // 时间 + 播放/暂停
                            Row(
                              children: [
                                // 播放/暂停
                                GestureDetector(
                                  onTap: _togglePlayPause,
                                  child: Icon(
                                    _controller!.value.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                // 时间
                                Text(
                                  '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: _enterFullscreen,
                                  child: const Icon(
                                    Icons.fullscreen,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 中央播放/暂停按钮（仅在控制层隐藏且暂停时显示）
                if (!_showControls && !(_controller!.value.isPlaying))
                  Center(
                    child: GestureDetector(
                      onTap: _togglePlayPause,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _controller!.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // 错误态
    if (_hasError) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: InkWell(
                onTap: () {
                  setState(() {
                    _hasError = false;
                    _isInitializing = false;
                  });
                  _initAndPlay();
                },
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 36),
                    SizedBox(height: 8),
                    Text('播放失败，点击重试', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 待播放态
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.posterUrl != null)
              CachedNetworkImage(
                cacheKey: 'v2_${widget.posterUrl}',
                imageUrl: widget.posterUrl!,
                httpHeaders: ArticleImageService.httpHeaders,
                fit: BoxFit.cover,
                fadeInDuration: const Duration(milliseconds: 80),
                fadeOutDuration: const Duration(milliseconds: 80),
                placeholder: (context, url) =>
                    Container(color: cs.surfaceContainerHighest),
                errorWidget: (context, url, error) =>
                    Container(color: cs.surfaceContainerHighest),
              )
            else
              Container(color: cs.surfaceContainerHighest),
            Container(color: Colors.black.withValues(alpha: 0.2)),
            Center(
              child: GestureDetector(
                onTap: _isInitializing ? null : _initAndPlay,
                child: Container(
                  width: _isInitializing ? 48 : 64,
                  height: _isInitializing ? 48 : 64,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.85),
                    shape: BoxShape.circle,
                  ),
                  child: _isInitializing
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow_rounded,
                          size: 40, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
