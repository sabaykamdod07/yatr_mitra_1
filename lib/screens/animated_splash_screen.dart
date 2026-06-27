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

  @override
  void initState() {
    super.initState();
    
    // 1. Initialize the video file from your assets folder
    _controller = VideoPlayerController.asset('assets/images/bus_intro.mp4')
      ..initialize().then((_) {
        setState(() {}); // Refresh frame once video metadata is ready
        
        _controller.setVolume(0.0); // Mutes the video so Chrome/Web allows instant autoplay
        _controller.play();         // Start playing the bus video entry animation
      });

    // 2. Listen for the exact moment the video finishes playing
    _controller.addListener(() {
      if (_controller.value.isInitialized && 
          _controller.value.position >= _controller.value.duration && 
          !_isVideoFinished) {
        setState(() {
          _isVideoFinished = true;
        });
        
        // 3. Smoothly slide/fade into your Welcome Screen layout code screen
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const WelcomeScreen(),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
                transitionDuration: const Duration(milliseconds: 800), // Clean 800ms cross-fade
              ),
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose(); // Clean up memory to avoid app memory leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Matches the clean app canvas background
      body: SizedBox.expand( // Forces the layout container to stretch to 100% phone width & height
        child: _controller.value.isInitialized
            ? AnimatedOpacity(
                opacity: _isVideoFinished ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 500),
                child: FittedBox(
                  fit: BoxFit.cover, // Centers the video and stretches it to fill the screen without leaving black bars
                  child: SizedBox(
                    width: _controller.value.size.width,
                    height: _controller.value.size.height,
                    child: VideoPlayer(_controller),
                  ),
                ),
              )
            : const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFBB03B)), // Yellow loading spinner
                ),
              ),
      ),
    );
  }
}
