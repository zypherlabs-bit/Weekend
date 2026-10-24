import 'dart:math' as math;

import 'package:flutter/material.dart';

enum SwipeDirection { like, pass }

class SwipeProfile {
  const SwipeProfile({
    required this.id,
    required this.name,
    required this.age,
    required this.photoUrls,
    this.subtitle,
  });

  final String id;
  final String name;
  final int age;
  final List<String> photoUrls;
  final String? subtitle;
}

class SwipeDeck extends StatefulWidget {
  const SwipeDeck({
    super.key,
    required this.profiles,
    required this.onAction,
    this.onProfileTap,
    this.onEmpty,
  });

  final List<SwipeProfile> profiles;

  final Future<bool> Function(SwipeProfile profile, SwipeDirection direction)
      onAction;

  final ValueChanged<SwipeProfile>? onProfileTap;
  final VoidCallback? onEmpty;

  @override
  State<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<SwipeDeck>
    with SingleTickerProviderStateMixin {
  static const double _swipeThreshold = 110;
  static const double _velocityThreshold = 700;

  late final AnimationController _controller;
  Animation<Offset>? _positionAnimation;

  List<SwipeProfile> _queue = [];
  Offset _dragOffset = Offset.zero;

  bool _busy = false;
  bool _actionInProgress = false;
  String? _error;

  SwipeProfile? get _active => _queue.isEmpty ? null : _queue.first;

  @override
  void initState() {
    super.initState();
    _queue = List.of(widget.profiles);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_handleAnimation);

    _controller.addStatusListener(_handleAnimationStatus);
  }

  @override
  void didUpdateWidget(covariant SwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldIds = oldWidget.profiles.map((p) => p.id).toList();
    final newIds = widget.profiles.map((p) => p.id).toList();

    if (!_busy && !_actionInProgress && !_sameIds(oldIds, newIds)) {
      _queue = List.of(widget.profiles);
      _error = null;
      _dragOffset = Offset.zero;
    }
  }

  void _animateTo(Offset target) {
    _positionAnimation = Tween<Offset>(
      begin: _dragOffset,
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward(from: 0);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_busy || _actionInProgress) return;

    setState(() {
      _dragOffset += details.delta;
      _error = null;
    });
  }

  void _onPanEnd(DragEndDetails details) {
    if (_busy || _actionInProgress || _active == null) return;

    final velocity = details.velocity.pixelsPerSecond.dx;
    final dx = _dragOffset.dx;

    SwipeDirection? direction;

    if (dx.abs() >= _swipeThreshold ||
        velocity.abs() >= _velocityThreshold) {
      final intendedDx = dx.abs() > 20 ? dx : velocity;
      direction = intendedDx > 0
          ? SwipeDirection.like
          : SwipeDirection.pass;
    }

    if (direction == null) {
      _animateTo(Offset.zero);
      return;
    }

    _performAction(direction);
  }

  Future<void> _performAction(SwipeDirection direction) async {
    final profile = _active;
    if (profile == null || _busy || _actionInProgress) return;

    _actionInProgress = true;
    _busy = true;
    _error = null;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final target = Offset(
      direction == SwipeDirection.like
          ? screenWidth * 1.5
          : -screenWidth * 1.5,
      _dragOffset.dy + 60,
    );

    _animateTo(target);
    await _controller.forward(from: 0);

    bool succeeded = false;

    try {
      succeeded = await widget.onAction(profile, direction);
    } catch (_) {
      succeeded = false;
    }

    if (!mounted) return;

    if (succeeded) {
      setState(() {
        if (_queue.isNotEmpty && _queue.first.id == profile.id) {
          _queue.removeAt(0);
        }

        _dragOffset = Offset.zero;
        _positionAnimation = null;
        _error = null;
        _busy = false;
        _actionInProgress = false;
      });

      if (_queue.isEmpty) {
        widget.onEmpty?.call();
      }
    } else {
      setState(() {
        _busy = false;
        _error = 'Could not save your action. Please try again.';
      });

      _animateTo(Offset.zero);
      await _controller.forward(from: 0);

      if (mounted) {
        setState(() {
          _positionAnimation = null;
          _actionInProgress = false;
        });
      }
    }
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _handleAnimation() {
    final animation = _positionAnimation;
    if (mounted && animation != null) {
      setState(() {
        _dragOffset = animation.value;
      });
    }
  }

  void _handleAnimationStatus(AnimationStatus status) {
    // The swipe transaction is completed in _performAction.
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_handleAnimation)
      ..removeStatusListener(_handleAnimationStatus)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_outlined, size: 56),
            const SizedBox(height: 12),
            const Text(
              'That’s everyone for now',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text('Check back later for more profiles.'),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  if (_queue.length > 1)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: 10,
                          left: 8,
                          right: 8,
                          bottom: 0,
                        ),
                        child: _ProfileCard(
                          profile: _queue[1],
                          onTap: null,
                        ),
                      ),
                    ),

                  Positioned.fill(
                    child: GestureDetector(
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      onTap: () => widget.onProfileTap?.call(_active!),
                      child: Transform.translate(
                        offset: _dragOffset,
                        child: Transform.rotate(
                          angle: (_dragOffset.dx /
                                  math.max(constraints.maxWidth, 1)) *
                              0.32,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: _ProfileCard(
                                  profile: _active!,
                                  onTap: null,
                                ),
                              ),

                              if (_dragOffset.dx.abs() > 18)
                                Positioned(
                                  top: 36,
                                  left: _dragOffset.dx > 0 ? 24 : null,
                                  right: _dragOffset.dx < 0 ? 24 : null,
                                  child: Transform.rotate(
                                    angle: _dragOffset.dx > 0
                                        ? -0.15
                                        : 0.15,
                                    child: _SwipeLabel(
                                      label: _dragOffset.dx > 0
                                          ? 'LIKE'
                                          : 'PASS',
                                      color: _dragOffset.dx > 0
                                          ? Colors.greenAccent
                                          : Colors.redAccent,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ),

        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              icon: Icons.close_rounded,
              color: Colors.redAccent,
              size: 60,
              onPressed: _busy
                  ? null
                  : () => _performAction(SwipeDirection.pass),
            ),
            const SizedBox(width: 28),
            _ActionButton(
              icon: Icons.favorite_rounded,
              color: Colors.pinkAccent,
              size: 72,
              onPressed: _busy
                  ? null
                  : () => _performAction(SwipeDirection.like),
            ),
          ],
        ),

        const SizedBox(height: 12),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.onTap,
  });

  final SwipeProfile profile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        profile.photoUrls.isEmpty ? null : profile.photoUrls.first;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const _PhotoPlaceholder(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const _PhotoPlaceholder(
                    loading: true,
                  );
                },
              )
            else
              const _PhotoPlaceholder(),

            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Color(0x11000000),
                    Color(0xDD000000),
                  ],
                  stops: [0.35, 0.62, 1],
                ),
              ),
            ),

            Positioned(
              left: 22,
              right: 22,
              bottom: 24,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${profile.name}, ${profile.age}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 29,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (profile.subtitle?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      profile.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({this.loading = false});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        loading ? Icons.image_outlined : Icons.person_outline,
        size: 64,
      ),
    );
  }
}

class _SwipeLabel extends StatelessWidget {
  const _SwipeLabel({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 28,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.color,
    required this.size,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: icon == Icons.close_rounded ? 'Pass profile' : 'Like profile',
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          shape: const CircleBorder(),
          elevation: 5,
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon, color: color, size: size * 0.48),
            tooltip: icon == Icons.close_rounded ? 'Pass' : 'Like',
          ),
        ),
      ),
    );
  }
}