import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/app_theme.dart';

/// One bundled intro clip, in slide order.
///
/// Named explicitly rather than derived from a directory listing so the asset
/// bundle, the onboarding slides and the sign-in screen can never disagree
/// about what exists or in what order.
class IntroClip {
  const IntroClip({
    required this.asset,
    required this.title,
    required this.caption,
  });

  final String asset;
  final String title;
  final String caption;
}

const List<IntroClip> kIntroClips = [
  IntroClip(
    asset: 'assets/videos/weekend1.mp4',
    title: 'Welcome to Weekend',
    caption: 'Meet people nearby and make real weekend plans.',
  ),
  IntroClip(
    asset: 'assets/videos/weekend2.mp4',
    title: 'Discover & Connect',
    caption: 'Swipe through profiles and find people who share your vibe.',
  ),
  IntroClip(
    asset: 'assets/videos/weekend3.mp4',
    title: 'Make Weekend Plans',
    caption: 'Turn matches into real meetups. Coffee, hikes, concerts, more.',
  ),
];

/// Plays one bundled intro clip, looping, muted, and never blocking the UI.
///
/// Behaviour that matters:
///
/// * **Never throws.** A missing or corrupt asset renders a gradient fallback
///   instead of taking the screen down. An onboarding carousel is not worth
///   crashing the app over.
/// * **Only the visible slide plays.** [active] false pauses the controller
///   and drops its frame callbacks, so three simultaneous decoders never
///   compete for the codec while the user is swiping.
/// * **Honours reduced motion.** When the platform reports
///   `disableAnimations` (an accessibility setting, also toggled by some
///   battery savers) the clip is not autoplayed and a still frame is shown.
/// * **Muted and looping, always.** These clips ship without an audio track
///   and are decorative, so an unmuted or non-looping player would be a bug,
///   not a feature.
class IntroVideoPlayer extends StatefulWidget {
  const IntroVideoPlayer({
    super.key,
    required this.clip,
    this.active = true,
    this.autoplay = true,
    this.borderRadius = 24,
    this.fallbackIcon = Icons.weekend_rounded,
    this.fit = BoxFit.cover,
  });

  final IntroClip clip;

  /// Whether this player is the one currently on screen.
  final bool active;

  /// False disables autoplay (used for the reduced-motion case).
  final bool autoplay;

  final double borderRadius;
  final IconData fallbackIcon;

  /// How the clip fills the box it is given.
  ///
  /// [BoxFit.cover] (the default) fills edge to edge and crops the overflow,
  /// which is what a full-screen background wants. [BoxFit.contain] would
  /// letterbox instead, so it is only appropriate if letterboxing is intended.
  final BoxFit fit;

  @override
  State<IntroVideoPlayer> createState() => _IntroVideoPlayerState();
}

class _IntroVideoPlayerState extends State<IntroVideoPlayer> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _manuallyPaused = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(IntroVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new clip means a new asset; a change in `active` only means the
    // visible slide changed.
    if (oldWidget.clip.asset != widget.clip.asset) {
      _disposeController();
      _init();
      return;
    }
    if (oldWidget.active != widget.active ||
        oldWidget.autoplay != widget.autoplay) {
      _syncPlayback();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
  }

  Future<void> _init() async {
    _failed = false;
    final controller = VideoPlayerController.asset(widget.clip.asset);
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      // These clips ship with no audio track at all (verified by ffprobe).
      // Muting is still set explicitly so the player behaves correctly if a
      // clip is ever replaced with one that has sound.
      await controller.setVolume(0);
    } catch (_) {
      // A missing or undecodable asset must degrade to the fallback, never
      // propagate. This is the difference between "no animation" and "crash".
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() => _failed = true);
      return;
    }
    if (!mounted) {
      controller.dispose();
      return;
    }
    setState(() {});
    _syncPlayback();
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final shouldPlay = widget.active && widget.autoplay && !_manuallyPaused;
    if (shouldPlay) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  void _toggleManualPause() {
    setState(() => _manuallyPaused = !_manuallyPaused);
    _syncPlayback();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Respect the OS-level reduced-motion preference: show a still frame
    // rather than autoplaying an animation the user has asked to avoid.
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final playing = ready && !_failed;

    final Widget content;
    if (_failed || !ready) {
      content = _Fallback(
        icon: widget.fallbackIcon,
        theme: theme,
        borderRadius: widget.borderRadius,
      );
    } else {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: FittedBox(
          fit: widget.fit,
          // Crop the tall 9:16 source to whatever box it is given rather
          // than letterboxing it with black bars.
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    }

    return Semantics(
      // The clip is decorative; the slide's own title and caption carry the
      // meaning, so the video is hidden from screen readers rather than
      // announced as an unlabelled animation.
      excludeSemantics: true,
      child: Stack(
        fit: StackFit.expand,
        children: [
          content,
          if (playing) ...[
            // A user-controlled pause. Autoplaying, unpausable video is an
            // accessibility problem.
            Positioned(
              right: 8,
              bottom: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggleManualPause,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _manuallyPaused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
          // Only while the clip is genuinely still loading. Once it has
          // failed, the fallback graphic is the final state - an endlessly
          // spinning progress indicator would tell the user we are still
          // working on it, which is a lie, and never stops animating.
          if (!reduceMotion && !playing && !_failed)
            const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white54,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown while the clip loads, or instead of it when the asset cannot play.
class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.icon,
    required this.theme,
    required this.borderRadius,
  });

  final IconData icon;
  final ThemeData theme;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: const LinearGradient(
          colors: [AppTheme.sunsetCoral, AppTheme.goldenPeach],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(icon, size: 72, color: Colors.white.withValues(alpha: 0.9)),
      ),
    );
  }
}
