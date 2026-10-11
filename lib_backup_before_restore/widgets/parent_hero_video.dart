import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The soft, animated picture at the top of the parent's "Your child" card:
/// a parent following the bus on their phone, with a bobbing location pin.
///
/// Shows the still picture straight away, then fades the video in once it is
/// ready. If the video can't play for any reason, the still picture stays, so
/// the card never looks broken. The video is muted and loops forever.
class ParentHeroVideo extends StatefulWidget {
  const ParentHeroVideo({super.key});

  /// width / height of the video (and of the still picture)
  static const double ratio = 1200 / 444;

  @override
  State<ParentHeroVideo> createState() => _ParentHeroVideoState();
}

class _ParentHeroVideoState extends State<ParentHeroVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _c;
  bool _ready = false;
  Timer? _watch;
  Duration _last = Duration.zero;
  int _stuck = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      final c = VideoPlayerController.asset(
        'assets/images/parent_hero.mp4',
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _ready = true;
      });
      // if the picture freezes (it can on some phones), restart it
      _watch = Timer.periodic(const Duration(seconds: 4), (_) {
        final v = _c;
        if (v == null || !v.value.isInitialized) return;
        if (v.value.isPlaying && v.value.position == _last) {
          _stuck++;
        } else {
          _stuck = 0;
        }
        _last = v.value.position;
        if (_stuck >= 2) {
          _stuck = 0;
          v.seekTo(Duration.zero);
          v.play();
        }
      });
    } catch (_) {
      // keep the still picture
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.resumed) {
      c.play();
    } else if (state == AppLifecycleState.paused) {
      c.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return AspectRatio(
      aspectRatio: ParentHeroVideo.ratio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/parent_hero.png', fit: BoxFit.cover),
          if (c != null)
            AnimatedOpacity(
              opacity: _ready ? 1 : 0,
              duration: const Duration(milliseconds: 500),
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
            ),
        ],
      ),
    );
  }
}