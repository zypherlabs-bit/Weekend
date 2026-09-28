import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_provider.dart';
import '../../widgets/intro_video_player.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// One slide per intro clip. The icon is only a fallback: it is shown if the
/// bundled video cannot be decoded, so the slide is never blank.
///
/// Top-level rather than a member of the state so the copy widget below can
/// read the same list without reaching through the state object.
///
/// `final` rather than `const` because `Icons.*` are not compile-time
/// constants in this Flutter version.
final List<OnboardingPage> _kOnboardingPages = [
  OnboardingPage(clip: kIntroClips[0], fallbackIcon: Icons.weekend_rounded),
  OnboardingPage(clip: kIntroClips[1], fallbackIcon: Icons.favorite_rounded),
  OnboardingPage(
    clip: kIntroClips[2],
    fallbackIcon: Icons.calendar_today_rounded,
  ),
];

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  List<OnboardingPage> get _pages => _kOnboardingPages;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      // The clip is the background of the whole slide, edge to edge, with the
      // copy layered on top. A Stack rather than a Column so the video is not
      // squeezed into a panel above the text.
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemCount: _pages.length,
            itemBuilder: (context, index) {
              final page = _pages[index];
              // Only the slide the user is actually looking at is allowed to
              // decode; the other two pause, so a swipe never leaves three
              // video decoders competing.
              return IntroVideoPlayer(
                clip: page.clip,
                active: _currentPage == index,
                fallbackIcon: page.fallbackIcon,
                // Full bleed: no rounded corners, so the clip runs under the
                // status bar and behind the navigation controls.
                borderRadius: 0,
              );
            },
          ),
          // Without a scrim the white copy sits directly on moving footage and
          // becomes unreadable on the brighter frames.
          const _SlideScrim(),
          SafeArea(
            child: Column(
              children: [
                // Pushes the copy to the bottom so the clip owns the upper
                // area, which is where the content in these clips actually is.
                const Spacer(),
                // The copy is decorative, so it must not swallow the horizontal
                // swipe that drives the PageView underneath it. IgnorePointer
                // lets a gesture that starts on the text still turn the page,
                // which is what the full-bleed layout would otherwise break.
                IgnorePointer(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _OnboardingCopy(index: _currentPage),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                _PageDots(count: _pages.length, current: _currentPage),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_currentPage < _pages.length - 1) {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          );
                        } else {
                          // "Get Started" means "create an account": open the
                          // Tinder-style sign-up wizard directly.
                          context.go('/signup');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF4B72),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentPage < _pages.length - 1
                            ? 'Next'
                            : 'Get Started',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
                _OnboardingFooter(
                  onSignIn: () {
                    ref.read(authStateProvider.notifier).dismissError();
                    context.go('/auth');
                  },
                  onGuest: () async {
                    await ref
                        .read(authStateProvider.notifier)
                        .signInAnonymously();
                    if (!context.mounted) return;
                    if (ref.read(authStateProvider).isAuthenticated) {
                      context.go('/home');
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The title and caption of one slide, swapped in by the [AnimatedSwitcher] as
/// the user pages through. Keyed by the page index so the switcher animates.
class _OnboardingCopy extends StatelessWidget {
  const _OnboardingCopy({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final page = _kOnboardingPages[index];
    return Column(
      key: ValueKey<int>(index),
      children: [
        Text(
          page.title,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          page.caption,
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.85),
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// The secondary actions under the primary button. Kept outside the SafeArea
/// column above so they sit at the very bottom of the full-bleed slide.
class _OnboardingFooter extends StatelessWidget {
  const _OnboardingFooter({required this.onSignIn, required this.onGuest});

  final VoidCallback onSignIn;
  final Future<void> Function() onGuest;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          onPressed: onSignIn,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Already have an account? Sign in',
            style: TextStyle(color: Color(0xFFFF4B72), fontSize: 14),
          ),
        ),
        TextButton(
          onPressed: onGuest,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text(
            'Explore as Guest',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

/// Darkens the lower part of a full-bleed slide so the title, caption and
/// button stay legible over any frame of the clip. The top stays clear so the
/// video itself is not muddied.
class _SlideScrim extends StatelessWidget {
  const _SlideScrim();

  @override
  Widget build(BuildContext context) {
    // IgnorePointer is required, not cosmetic: RenderDecoratedBox reports
    // hitTestSelf == true, so an opaque scrim would swallow every gesture
    // meant for the PageView underneath and the slides could not be swiped.
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
            stops: [0.0, 0.35, 0.75],
          ),
        ),
      ),
    );
  }
}

/// The onboarding progress indicator: a pill for the active slide, dots for
/// the rest.
class _PageDots extends StatelessWidget {
  const _PageDots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: current == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: current == index
                ? const Color(0xFFFF4B72)
                : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }
}

/// One onboarding slide: a bundled intro clip, plus the icon to fall back to
/// if that clip cannot be decoded.
class OnboardingPage {
  final IntroClip clip;
  final IconData fallbackIcon;

  const OnboardingPage({required this.clip, required this.fallbackIcon});

  String get title => clip.title;
  String get caption => clip.caption;
}
