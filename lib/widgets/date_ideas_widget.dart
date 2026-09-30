import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/weekend_provider.dart';

/// Button that fetches and surfaces AI-generated date ideas for a match.
///
/// Tapped from the chat screen's app bar. On first press it calls
/// `generateDateIdeas` on the provider and reveals a sheet of idea cards.
/// Subsequent presses re-fetch with fresh prompts.
class DateIdeasButton extends ConsumerStatefulWidget {
  /// The match partner's interests, used to seed the Gemini prompt.
  final List<String> partnerInterests;

  /// The city to localise the suggestions.
  final String city;

  const DateIdeasButton({
    super.key,
    required this.partnerInterests,
    required this.city,
  });

  @override
  ConsumerState<DateIdeasButton> createState() => _DateIdeasButtonState();
}

class _DateIdeasButtonState extends ConsumerState<DateIdeasButton> {
  bool _sheetOpen = false;

  void _toggle() {
    if (_sheetOpen) {
      setState(() => _sheetOpen = false);
      if (mounted) Navigator.of(context).pop();
    } else {
      setState(() => _sheetOpen = true);
      _showSheet();
    }
  }

  void _showSheet() {
    final height = MediaQuery.of(context).size.height;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (context) => _DateIdeasSheet(
        partnerInterests: widget.partnerInterests,
        city: widget.city,
        onClosed: () => setState(() => _sheetOpen = false),
        maxHeight: height * 0.6,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Suggest date ideas',
      icon: const Icon(Icons.lightbulb_rounded, color: Colors.white),
      onPressed: _toggle,
    );
  }

  @override
  void dispose() {
    if (_sheetOpen && mounted) {
      Navigator.of(context).pop();
    }
    super.dispose();
  }
}

class _DateIdeasSheet extends ConsumerStatefulWidget {
  final List<String> partnerInterests;
  final String city;
  final VoidCallback onClosed;
  final double maxHeight;

  const _DateIdeasSheet({
    required this.partnerInterests,
    required this.city,
    required this.onClosed,
    this.maxHeight = 400,
  });

  @override
  ConsumerState<_DateIdeasSheet> createState() => _DateIdeasSheetState();
}

class _DateIdeasSheetState extends ConsumerState<_DateIdeasSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(weekendProvider.notifier).generateDateIdeas(
            partnerInterests: widget.partnerInterests,
            city: widget.city,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(weekendProvider);
    final ideas = state.dateIdeas;
    final isGenerating = state.isGeneratingDateIdeas;
    final hasContent = ideas.isNotEmpty;

    return Container(
      height: widget.maxHeight,
      decoration: const BoxDecoration(
        color: Color(0xFF1C162E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHandle(),
          _buildHeader(),
          Expanded(
            child: isGenerating && !hasContent
                ? const _LoadingContent()
                : hasContent
                    ? _IdeasList(ideas: ideas)
                    : const _EmptyContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Date Ideas',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextButton(
            onPressed: () {
              ref.read(weekendProvider.notifier).generateDateIdeas(
                    partnerInterests: widget.partnerInterests,
                    city: widget.city,
                  );
            },
            child: const Text(
              'Refresh',
              style: TextStyle(color: Color(0xFFFF9966)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingContent extends StatelessWidget {
  const _LoadingContent();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF4B72)),
          ),
          SizedBox(height: 16),
          Text(
            'Crafting date ideas...',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _EmptyContent extends StatelessWidget {
  const _EmptyContent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lightbulb_outline_rounded,
              size: 48,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            const Text(
              'No date ideas right now',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _IdeasList extends StatelessWidget {
  final List<DateIdea> ideas;

  const _IdeasList({required this.ideas});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: ideas.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _DateIdeaCard(idea: ideas[index]);
      },
    );
  }
}

class _DateIdeaCard extends StatelessWidget {
  final DateIdea idea;

  const _DateIdeaCard({required this.idea});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF23212B), Color(0xFF282534)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  idea.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  idea.venueType,
                  style: const TextStyle(
                    color: Color(0xFFFF9966),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  idea.description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (idea.estimatedBudget.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.attach_money_rounded,
                    color: Color(0xFFFF9966),
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    idea.estimatedBudget,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
