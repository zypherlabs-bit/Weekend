import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contract tests between the Dart data layer and the database RPCs it calls.
///
/// The defect this file is written against is specific and expensive:
/// `MatchRepository.fetchMatches` read eleven columns from `get_matches_for_user`
/// while the live function returned a different, smaller set - and referenced two
/// columns (`matches.conversation_id`, `messages.content`) that have never
/// existed. Postgres cannot raise "column does not exist" at CREATE time, so the
/// function compiled, the client compiled, the tests passed, and in production
/// every call raised. `fetchMatches` swallowed the error and returned `[]`, so
/// every user saw "No Matches Yet" forever with no error anywhere.
///
/// Static analysis cannot catch that, and neither can a unit test that mocks the
/// client. These tests read the migration SQL and the Dart source and assert the
/// two agree.
void main() {
  late String migrations;
  late String addedHere;
  late String matchRepositorySource;
  late String safetyRepositorySource;

  /// The functions introduced by the change under test. Used to scope the
  /// search_path assertion to code this change owns, since the pre-existing
  /// ones are fixed at runtime by the sweep loop rather than in source text.
  final namesAddedHere = <String>[
    'enforce_message_rules',
    'enforce_block_unwind',
    'enforce_interaction_rate_limit',
    'notify_on_like',
    'sync_profile_completion',
    'record_like',
    'record_pass',
    'unmatch_match',
    'get_received_likes',
    'get_notifications',
    'mark_all_notifications_read',
    'notification_unread_count',
    'submit_report',
    'ensure_interest',
    'guard_interest_name_change',
    'protect_verification_verdict',
    'get_matches_for_user',
  ];

  /// Strip `--` line comments so a comment explaining a past defect cannot
  /// satisfy - or fail - a code assertion. Migration 026's header comment names
  /// `m.conversation_id` and `mm.content` while explaining that they were
  /// removed; without this, that prose reads as if the columns are still there.
  String stripSqlComments(String sql) =>
      sql.replaceAll(RegExp(r'--[^\n]*'), '');

  setUpAll(() {
    // Concatenate every migration newest-last, so the LAST definition of a
    // function is the one that is actually in force after a full run. This is
    // the same rule `conftest.latest_migration_text` uses on the Python side.
    final dir = Directory('supabase/migrations');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) {
        final an = RegExp(r'(\d+)').firstMatch(a.path)?.group(1) ?? '0';
        final bn = RegExp(r'(\d+)').firstMatch(b.path)?.group(1) ?? '0';
        return an.compareTo(bn);
      });

    final texts = files.map((f) => f.readAsStringSync()).toList();
    migrations = stripSqlComments(texts.join('\n;\n'));
    addedHere = stripSqlComments(texts.last);

    matchRepositorySource =
        File('lib/repositories/match_repository.dart').readAsStringSync();
    safetyRepositorySource =
        File('lib/repositories/safety_repository.dart').readAsStringSync();
});

  /// The text of a function definition: from [matchStart] to the CLOSING `$$`
  /// delimiter.
  ///
  /// Finding the first `$$` would stop at the OPENING delimiter and return only
  /// the signature - which makes every body-level assertion pass vacuously.
  String definitionAt(String source, int matchStart) {
    final rest = source.substring(matchStart);
    final open = rest.indexOf(r'$$');
    if (open == -1) return rest;
    final close = rest.indexOf(r'$$', open + 2);
    if (close == -1) return rest;
    return rest.substring(0, close + 2);
  }

  /// The LAST definition of [name] in [source], or `null` if undefined.
  ///
  /// Matches plain `create function` as well as `create or replace`: Postgres
  /// refuses to change a function's OUT-parameter list in place (42P13), so a
  /// repaired function is dropped and re-created with `create function` - which
  /// a `create or replace` -only pattern would miss entirely, leaving the broken
  /// definition looking like the live one.
  String? lastDefinition(String source, String name) {
    final matches = RegExp(
      'create\\s+(?:or\\s+replace\\s+)?function\\s+(?:public\\.)'
      '${RegExp.escape(name)}\\s*\\(',
      caseSensitive: false,
    ).allMatches(source).toList();
    if (matches.isEmpty) return null;
    return definitionAt(source, matches.last.start);
  }

  /// Return the `returns table (...)` column list of the LAST definition of
  /// [name], or `null` when the function is not defined at all.
  List<String>? returnColumns(String name) {
    final definition = lastDefinition(migrations, name);
    if (definition == null) return null;

    final returnsAt = RegExp(
      r'returns\s+table\s*\(',
      caseSensitive: false,
    ).firstMatch(definition);
    if (returnsAt == null) return null;

    // Walk to the matching close paren of the RETURN TABLE list.
    var depth = 0;
    var i = returnsAt.end - 1;
    for (; i < definition.length; i++) {
      final c = definition[i];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
    }

    final body = definition.substring(returnsAt.end, i);
    return body
        .split(',')
        .map((s) => s.trim().split(RegExp(r'\s')).first.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Every `row['x']` key the repository reads off an RPC result.
  Set<String> rowKeysRead(String source, String rpcName) {
    final call = RegExp(
      "rpc\\(\\s*'$rpcName'",
    ).firstMatch(source);
    expect(call, isNotNull, reason: '$rpcName is not called in this file');

    final from = call!.end;
    final block = source.substring(from, from + 3000);

    final keys = <String>{};
    for (final m in RegExp(r"row\['([a-z_]+)'\]").allMatches(block)) {
      keys.add(m.group(1)!);
    }
    return keys;
  }

  group('get_matches_for_user', () {
    test('is defined', () {
      expect(
        returnColumns('get_matches_for_user'),
        isNotNull,
        reason: 'the matches tab depends on this function existing',
      );
    });

    test('does not reference columns that do not exist', () {
      // `matches` has no `conversation_id`; the link runs the other way, via
      // `conversations.match_id`. `messages` stores its body in `text`. Both
      // mistakes were present simultaneously in migration 022.
      final definition = lastDefinition(migrations, 'get_matches_for_user');
      expect(definition, isNotNull);
      final text = definition!.toLowerCase();

      // Word-boundary anchored: a plain substring test for `m.conversation_id`
      // also matches `cm.conversation_id`, which is a legitimate reference to
      // conversation_members and appears twice in this function.
      expect(
        RegExp(r'(?<![a-z_])m\.conversation_id').hasMatch(text),
        isFalse,
        reason: 'matches has no conversation_id column',
      );
      expect(
        RegExp(r'(?<![a-z_])mm\.content(?![a-z_])').hasMatch(text),
        isFalse,
        reason: 'the messages body column is `text`, not `content`',
      );

      // And it does reach the conversation the way it actually exists.
      expect(
        text.contains('join public.conversations'),
        isTrue,
        reason: 'the match -> conversation link must be a join on '
            'conversations.match_id',
      );
      expect(
        text.contains('c.match_id = m.id'),
        isTrue,
      );
    });

    test('every column MatchRepository reads is actually returned', () {
      final returned = returnColumns('get_matches_for_user');
      expect(returned, isNotNull);
      final returnedSet = returned!.toSet();

      final read = rowKeysRead(matchRepositorySource, 'get_matches_for_user');

      // These are read from the nested/derived shape rather than the RPC row.
      const notFromTheRpc = {'id'};
      final missing = read
          .where((k) => !notFromTheRpc.contains(k))
          .where((k) => !returnedSet.contains(k))
          .toSet();

      expect(
        missing,
        isEmpty,
        reason: 'MatchRepository reads $missing but the RPC does not return '
            'them. Either column silently defaults or the RPC cannot compile.',
      );
    });

    test('the interest and unread columns it depends on are returned', () {
      final returned = returnColumns('get_matches_for_user')!.toSet();

      // These four are what make the matches tab useful rather than a list of
      // blank rows: shared interests drive the conversation starter, and
      // unread_count drives the badge.
      for (final column in const [
        'interests',
        'shared_interests',
        'unread_count',
        'matched_at',
      ]) {
        expect(
          returned,
          contains(column),
          reason: 'the matches card reads $column',
        );
      }
    });
  });

  group('interaction RPCs exist', () {
    for (final fn in const [
      'record_like',
      'record_pass',
      'unmatch_match',
      'get_received_likes',
      'get_notifications',
      'mark_all_notifications_read',
      'notification_unread_count',
      'submit_report',
      'ensure_interest',
    ]) {
      test('$fn is defined and granted to authenticated', () {
        expect(
          migrations.contains('function public.$fn('),
          isTrue,
          reason: '$fn is called by the app but not defined in any migration',
        );
        expect(
          RegExp('grant\\s+execute\\s+on\\s+function\\s+public\\.$fn\\s*\\(',
                  caseSensitive: false)
              .hasMatch(migrations),
          isTrue,
          reason: '$fn must be granted to authenticated or every call fails',
        );
      });

      test('$fn is revoked from anon', () {
        // Without the revoke, `authenticated` inherits execute from PUBLIC and
        // the function is reachable by an unauthenticated caller.
        expect(
          RegExp('revoke\\s+all\\s+on\\s+function\\s+public\\.$fn\\s*\\(',
                  caseSensitive: false)
              .hasMatch(migrations),
          isTrue,
          reason: '$fn must be explicitly revoked from public/anon first',
        );
      });
    }
  });

  group('security invariants', () {
    test('every SECURITY DEFINER function pins pg_temp in its search_path', () {
      // Postgres searches pg_temp FIRST unless it is named explicitly, so
      // `set search_path = public` alone is weaker than it looks. Migration 024
      // fixed the functions that existed then; 022/023/025 added more without it.
      //
      // The remedy in migration 026 is a runtime sweep - a DO block that issues
      // `ALTER FUNCTION ... SET search_path` over every SECURITY DEFINER
      // function - which is self-healing and cannot be expressed as source text
      // for an existing function. So this asserts both halves: that the sweep
      // exists, and that functions DEFINED IN 026 pin it inline, so a new
      // function added to 026 is correct on its own without relying on the loop.
      expect(
        RegExp(r'alter\s+function\s+%s\s+security\s+definer\s+set\s+'
                r'search_path\s*=\s*public\s*,\s*pg_temp', caseSensitive: false)
            .hasMatch(migrations),
        isTrue,
        reason: 'the pg_temp sweep over pre-existing functions is missing',
      );

      final offenders = <String>[];
      final fnPattern = RegExp(
        r'create\s+or\s+replace\s+function\s+([a-z_.]+)\s*\(',
        caseSensitive: false,
      );
      // Scoped to `addedHere`, not the whole corpus: the pre-existing functions
      // are corrected at runtime by the sweep loop rather than in source text,
      // and scanning the corpus would flag their untouched definitions.
      for (final m in fnPattern.allMatches(addedHere)) {
        final name = m.group(1)!;
        if (!namesAddedHere.any((n) => name.endsWith('.$n') || name.endsWith(n))) {
          continue;
        }

        final definition = definitionAt(addedHere, m.start);
        if (!definition.toLowerCase().contains('security definer')) continue;

        if (RegExp(r'set\s+search_path\s*=\s*public(?!\s*,\s*pg_temp)',
                caseSensitive: false)
            .hasMatch(definition)) {
          offenders.add(name);
        }
      }

      expect(offenders, isEmpty, reason: 'these pin only `public`');
    });

    test('the interests master list is no longer world-writable', () {
      // 018 granted UPDATE with `using (auth.uid() is not null)`, so any signed-in
      // user could rewrite any shared interest and change the chip on every
      // profile that used it. Migration 026 drops that policy and revokes the
      // grant.
      expect(
        RegExp(r'drop\s+policy\s+if\s+exists\s+"[^"]*"\s+on\s+public\.interests',
                caseSensitive: false)
            .hasMatch(migrations),
        isTrue,
        reason: 'the unrestricted interests UPDATE policy is never dropped',
      );
      expect(
        RegExp(r'revoke\s+update\s+on\s+public\.interests\s+from\s+authenticated',
                caseSensitive: false)
            .hasMatch(migrations),
        isTrue,
      );
      // And an interest's name can no longer be changed even in principle.
      expect(migrations.contains('guard_interest_name_change'), isTrue);
    });

    test('campaign budgets are not readable by every signed-in user', () {
      // The blanket `using (auth.uid() is not null)` policy on ad_campaigns
      // exposed budget_cents / spent_cents / cpm_cents for every campaign.
      // Migration 026 drops it and replaces it with an advertiser-scoped policy.
      expect(
        RegExp(r'drop\s+policy\s+if\s+exists\s+"[^"]*"\s+on\s+public\.ad_campaigns',
                caseSensitive: false)
            .hasMatch(migrations),
        isTrue,
      );
      expect(
        RegExp(r'create\s+policy\s+"[^"]*"\s+on\s+public\.ad_campaigns\s+for\s+select',
                caseSensitive: false)
            .hasMatch(migrations),
        isTrue,
        reason: 'the replacement SELECT policy must exist',
      );
    });

    test('a self-approving verification request is no longer possible', () {
      expect(
        migrations.contains('protect_verification_verdict'),
        isTrue,
        reason: 'status/confidence_score must be write-protected from the client',
      );
    });

    test('blocking is enforced in both directions for messages', () {
      // Uses the LAST definition, which is the one in force after a full run.
      final definition = lastDefinition(migrations, 'enforce_message_rules');
      expect(definition, isNotNull);
      final window = definition!.toLowerCase();

      // Both branches must be present. 006 only checked
      // `blocker_id = v_other and blocked_id = new.sender_id`, which only fires
      // when the RECIPIENT blocked the sender - so if YOU blocked someone they
      // could still message you.
      expect(
        window.contains('b.blocker_id = new.sender_id'),
        isTrue,
        reason: 'the sender having blocked the recipient must also block',
      );
      expect(
        window.contains('b.blocker_id = v_other'),
        isTrue,
        reason: 'the recipient having blocked the sender must also block',
      );
    });

    test('creating a block unwinds an existing match', () {
      expect(
        migrations.contains('enforce_block_unwind'),
        isTrue,
        reason: 'a block must remove the match and its conversation',
      );
    });

    test('rate limiting covers likes and passes', () {
      expect(
        migrations.contains('enforce_interaction_rate_limit'),
        isTrue,
      );
      expect(
        RegExp('on_pass_rate_limit\\s+on\\s+public\\.passes',
                caseSensitive: false)
            .hasMatch(migrations),
        isTrue,
      );
    });

    test('conversation_members is published for realtime unread counts', () {
      expect(
        RegExp('add\\s+table\\s+public\\.conversation_members',
                caseSensitive: false)
            .hasMatch(migrations),
        isTrue,
        reason: 'unread_count changes could not stream without this',
      );
    });

    test('a message notification carries the id the deep link routes on', () {
      // `/chat/:matchId` is keyed by MATCH id. The trigger originally wrote
      // only `conversation_id`, so every message notification resolved to
      // nothing and opened "Conversation unavailable".
      final definition = lastDefinition(migrations, 'notify_on_message');
      expect(definition, isNotNull);
      final body = definition!.toLowerCase();

      expect(
        body.contains("'match_id', v_match_id"),
        isTrue,
        reason: 'the payload must carry match_id for the deep link to resolve',
      );
      // And it must be resolved from the conversation, not invented.
      expect(
        body.contains('from public.conversations'),
        isTrue,
      );
    });

    test('a match notification already carries a match id', () {
      final definition = lastDefinition(migrations, 'check_mutual_like');
      expect(definition, isNotNull);
      expect(
        definition!.toLowerCase().contains('match_id'),
        isTrue,
      );
    });
  });

  group('report categories', () {
    test('the underage bucket exists in the schema constraint', () {
      // It is the most urgent category in a dating app and had nowhere to go
      // before, so it was filed as impersonation.
      final matches = RegExp(
        r'reports_report_type_check\s+check\s*\([^;]*?underage',
        caseSensitive: false,
        dotAll: true,
      ).allMatches(migrations).toList();
      expect(matches, isNotEmpty);
    });

    test('every category the client can emit is accepted by the constraint', () {
      // allMatches, not firstMatch: migration 001 declares a narrower CHECK and
      // 026 replaces it. Only the last one is in force after a full run, so only
      // the last one matters.
      final constraints = RegExp(
        r'check\s*\(report_type\s+in\s*\(([^)]*)\)\)',
        caseSensitive: false,
      ).allMatches(migrations).toList();
      expect(constraints, isNotEmpty);

      final allowed = constraints.last
          .group(1)!
          .split(',')
          .map((s) => s.trim().replaceAll("'", ''))
          .where((s) => s.isNotEmpty)
          .toSet();

      // Mirrors what SafetyRepository.mapReportType can return.
      for (final emitted in const [
        'underage',
        'unsafe_behavior',
        'spam',
        'scam',
        'harassment',
        'impersonation',
        'photo',
        'message',
        'inappropriate_content',
        'profile',
      ]) {
        expect(
          allowed,
          contains(emitted),
          reason: 'the client can report "$emitted" but the schema rejects it',
        );
      }
    });
  });

  group('the client does not write privileged tables directly any more', () {
    test('SafetyRepository reports through submit_report', () {
      expect(
        safetyRepositorySource.contains("'submit_report'"),
        isTrue,
      );
      expect(
        safetyRepositorySource.contains("from('reports')"),
        isFalse,
        reason: 'a direct INSERT bypasses server-side validation and rate limits',
      );
    });

    test('MatchRepository likes and passes through the RPCs', () {
      expect(matchRepositorySource.contains("'record_like'"), isTrue);
      expect(matchRepositorySource.contains("'record_pass'"), isTrue);
      expect(
        matchRepositorySource.contains("from('likes')"),
        isFalse,
        reason: 'a direct like INSERT bypasses the block check',
      );
    });

    test('the notification screen routes on the id the payload provides', () {
      // Guards the bug where the screen pushed /chat/<conversationId> against a
      // route keyed by match id.
      final screen =
          File('lib/features/notifications/notifications_screen.dart')
              .readAsStringSync();

      expect(
        screen.contains('targetMatchId'),
        isTrue,
        reason: 'the chat route is keyed by match id',
      );
      expect(
        screen.contains('/chat/\$matchId'),
        isTrue,
      );
      expect(
        screen.contains('/chat/\$conversationId'),
        isFalse,
        reason: 'conversation id is not what /chat/:matchId resolves',
      );
    });

    test('account deletion requires a password on both sides of the contract',
        () {
      final repository =
          File('lib/repositories/auth_repository.dart').readAsStringSync();
      final function =
          File('supabase/functions/account-deletion/index.ts').readAsStringSync();

      expect(
        repository.contains("'password': password"),
        isTrue,
        reason: 'the password must actually reach the edge function',
      );
      expect(
        function.contains('signInWithPassword'),
        isTrue,
        reason: 'the password must be verified, not merely read',
      );
      // Not merely accepted-and-ignored, which is the original defect.
      expect(
        RegExp(r"\{\s*error:\s*'Password confirmation required\.'")
            .hasMatch(function),
        isTrue,
        reason: 'a missing password must be rejected with 401, not ignored',
      );
    });

    test('no edge function returns tokens without authenticating the caller',
        () {
      // The passkey endpoints were the violation: `authenticate()` was defined
      // and never called, then the function returned access/refresh tokens.
      //
      // Comments are stripped first: the retired stubs explain in prose that
      // they used to return tokens, and that explanation must not read as
      // code still doing it.
      final dir = Directory('supabase/functions');
      for (final entry in dir.listSync().whereType<Directory>()) {
        final index = File('${entry.path}/index.ts');
        if (!index.existsSync()) continue;

        final source = index
            .readAsStringSync()
            .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
            .replaceAll(RegExp(r'//[^\n]*'), '');

        // A retired stub must contain no token handling at all.
        if (source.contains('has been retired')) {
          expect(
            source.contains('access_token'),
            isFalse,
            reason: '${entry.path} is retired and must not handle tokens',
          );
          continue;
        }

        // Otherwise: any handler that mints a session must authenticate first.
        if (!source.contains('access_token')) continue;

        expect(
            RegExp(r'await\s+authenticate\s*\(').hasMatch(source),
            isTrue,
            reason: '${entry.path} returns a token without authenticating the '
                'caller');
      }
    });
  });
}