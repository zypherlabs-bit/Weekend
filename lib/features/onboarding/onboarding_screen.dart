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

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  /// One slide per intro clip. The icon is only a fallback: it is shown if the
  /// bundled video cannot be decoded, so the slide is never blank.
  ///
  /// `final` rather than `const` because `Icons.*` are not compile-time
  /// constants in this Flutter version.
  static final List<OnboardingPage> _pages = [
    OnboardingPage(
      clip: kIntroClips[0],
      fallbackIcon: Icons.weekend_rounded,
    ),
    OnboardingPage(
      clip: kIntroClips[1],
      fallbackIcon: Icons.favorite_rounded,
    ),
    OnboardingPage(
      clip: kIntroClips[2],
      fallbackIcon: Icons.calendar_today_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF130E20),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Only the slide the user is actually looking at is
                        // allowed to decode; the other two pause, so a swipe
                        // never leaves three video decoders competing.
                        Expanded(
                          child: IntroVideoPlayer(
                            clip: page.clip,
                            active: _currentPage == index,
                            fallbackIcon: page.fallbackIcon,
                          ),
                        ),
                        const SizedBox(height: 28),
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
                            color: Colors.white.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pages.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? const Color(0xFFFF4B72)
                        : Colors.white.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
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
                    _currentPage < _pages.length - 1 ? 'Next' : 'Get Started',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () {
                      ref.read(authStateProvider.notifier).dismissError();
                      context.go('/auth');
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      'Already have an account? Sign in',
                      style: TextStyle(
                        color: Color(0xFFFF4B72),
                        fontSize: 14,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await ref
                          .read(authStateProvider.notifier)
                          .signInAnonymously();
                      if (!context.mounted) return;
                      if (ref.read(authStateProvider).isAuthenticated) {
                        context.go('/home');
                      }
                    },
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
              ),
            ),
          ],
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

