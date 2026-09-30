import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../providers/weekend_provider.dart';
import '../../widgets/weekend_empty_state.dart';
import 'chat_screen.dart';

/// Resolves a match id to its conversation and hands off to [ChatScreen].
///
/// `ChatScreen` takes a fully-populated `MatchItem`, but every entry point into
/// a conversation (a notification deep link, a shared link, a cold-start route)
/// only has an id. This screen bridges the two, and is the reason
/// `/chat/:matchId` can be a real route rather than a stub.
///
/// The match is looked up from already-loaded state rather than re-fetched: the
/// matches list is loaded when home initialises, and a refetch here would be a
/// second identical round trip on the common path. If it is genuinely absent -
/// an unmatch happened, or a block removed it - the user gets an explanation
/// rather than an endless spinner.
class MatchConversationScreen extends ConsumerWidget {
  final String matchId;

  const MatchConversationScreen({super.key, required this.matchId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = ref.watch(weekendProvider.select((s) => s.matches));

    MatchItem? match;
    for (final m in matches) {
      if (m.id == matchId) {
        match = m;
        break;
      }
    }

    final found = match;
    if (found != null) {
      return ChatScreen(match: found);
    }

    // Distinguish "still loading" from "no longer available" by checking whether
    // any matches are loaded at all. An empty list with nothing fetched yet is
    // the loading case; a populated list that simply does not contain this id is
    // the gone case.
    if (matches.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Conversation')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Conversation')),
      body: WeekendEmptyState(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Conversation unavailable',
        subtitle:
            'This conversation is no longer available. It may have been ended '
            'by either person.',
        actionLabel: 'Back to matches',
        onAction: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        },
      ),
    );
  }
}