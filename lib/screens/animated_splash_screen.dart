import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'welcome_screen.dart';

class AnimatedSplashScreen extends StatefulWidget {
  const AnimatedSplashScreen({super.key});

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen> {
  late VideoPlayerController _controller;
  bool _isVideoFinished = false;
  bool _navigated = false;
  Timer? _failsafe;

  @override
  void initState() {
    super.initState();

    // 1. The one-shot version of the bus video: it ends on the close-up of the
    //    bus. (The welcome page uses bus_intro.mp4, the seamless loop.)
    _controller = VideoPlayerController.asset('assets/images/bus_intro_splash.mp4');
    _controller.addListener(_onVideoTick);
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {}); // refresh once the video is ready
      _controller.setVolume(0.0); // muted, so Chrome/web allows instant autoplay
      _controller.play();
    }).catchError((_) {
      // the video could not be loaded: do not get stuck on the spinner
      _finish();
    });

    // 2. Safety net: whatever happens, move on after 10 seconds.
    _failsafe = Timer(const Duration(seconds: 10), _finish);
  }

  /// Watches the video and notices the moment it has played to the end.
  void _onVideoTick() {
    final v = _controller.value;
    if (!v.isInitialized || _isVideoFinished) return;
    final atEnd = v.isCompleted ||
        (v.duration > Duration.zero &&
            v.position >= v.duration - const Duration(milliseconds: 120));
    if (atEnd) _finish();
  }

  void _finish() {
    if (_isVideoFinished) return;
    if (mounted) setState(() => _isVideoFinished = true);
    // 3. Short pause, then a smooth cross-fade into the Welcome screen.
    Future.delayed(const Duration(milliseconds: 500), _goToWelcome);
  }

  void _goToWelcome() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const WelcomeScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800), // clean 800 ms cross-fade
      ),
    );
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    _controller.removeListener(_onVideoTick);
    _controller.dispose(); // clean up memory
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // matches the light sky of the video
      body: SizedBox.expand(
        child: _controller.value.isInitialized
            ? AnimatedOpacity(
                opacity: _isVideoFinished ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 500),
                child: FittedBox(
                  // The video is tall (9:16) like the phone, so it fills the screen
                  // with only a small crop, and the bus stays sharp.
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFBB03B)), // amber spinner
                ),
              ),
      ),
    );
  }
}