import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:weekend/providers/auth_provider.dart';
import 'package:weekend/routing/app_router.dart';

/// Regression guard for the "repeated screens after signup" defect.
///
/// The router provider previously used `ref.watch(authStateProvider)`, so every
/// auth-state emission rebuilt the provider and produced a brand-new GoRouter.
/// A fresh GoRouter starts again at `initialLocation: '/'`, replaying
/// splash → entry screens instead of continuing forward. The state must now be
/// delivered through `refreshListenable`, leaving exactly one router instance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('auth state changes do not rebuild the GoRouter instance', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Keep the provider alive so a dependency change would actually rebuild it.
    final sub = container.listen<GoRouter>(appRouterProvider, (_, __) {});
    addTearDown(sub.close);

    final first = container.read(appRouterProvider);

    // Let the async session check finish; this emits a real auth-state change
    // (isLoading true -> false) that used to recreate the router mid-flow.
    await pumpEventQueue();
    await pumpEventQueue();

    final second = container.read(appRouterProvider);
    expect(identical(first, second), isTrue,
        reason: 'The GoRouter must survive auth-state changes.');

    // A later, routing-relevant transition must not replace it either.
    container.read(authStateProvider.notifier).dismissError();
    await pumpEventQueue();

    expect(identical(first, container.read(appRouterProvider)), isTrue,
        reason: 'Auth transitions must not reset navigation state.');
  });
}
