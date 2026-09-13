import 'package:flutter_test/flutter_test.dart';
import 'package:weekend/models/models.dart';
import 'package:weekend/repositories/ad_repository.dart';
import 'package:weekend/services/ad_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAdRepository extends Mock implements AdRepository {}

void main() {
  group('AdService Timer', () {
    late MockAdRepository mockRepo;
    late AdService adService;

    setUp(() {
      mockRepo = MockAdRepository();
      adService = AdService(repository: mockRepo);
    });

    tearDown(() {
      adService.dispose();
    });

    test('initial state has no timer started', () {
      expect(adService.adTimerStarted, false);
      expect(adService.adEligible, false);
      expect(adService.adDisplayed, false);
      expect(adService.adId, isNull);
    });

    test('shouldShowAd is false when timer not started', () {
      expect(adService.shouldShowAd, false);
    });

    test('startActiveDiscoveryTimer begins counting', () async {
      adService.startActiveDiscoveryTimer();

      expect(adService.adTimerStarted, true);
      expect(adService.activeDiscoverySeconds, 0);

      await Future.delayed(const Duration(milliseconds: 1100));
      expect(adService.activeDiscoverySeconds, greaterThanOrEqualTo(1));
    });

    test('ad becomes eligible after interval', () async {
      adService.startActiveDiscoveryTimer();

      final shortConfig = AdService(
        repository: mockRepo,
        config: const AdConfig(adIntervalSeconds: 1),
      );
      shortConfig.startActiveDiscoveryTimer();

      await Future.delayed(const Duration(milliseconds: 1200));
      expect(shortConfig.adEligible, true);
      expect(shortConfig.shouldShowAd, true);

      shortConfig.dispose();
    });

    test('pauseTimer stops the timer from counting', () async {
      adService.startActiveDiscoveryTimer();

      await Future.delayed(const Duration(milliseconds: 600));
      final secondsBeforePause = adService.activeDiscoverySeconds;
      expect(secondsBeforePause, greaterThanOrEqualTo(0));

      adService.pauseTimer();

      await Future.delayed(const Duration(milliseconds: 1100));
      expect(adService.activeDiscoverySeconds, secondsBeforePause);
    });

    test('resumeTimer resumes counting after pause', () async {
      final shortConfig = AdService(
        repository: mockRepo,
        config: const AdConfig(adIntervalSeconds: 3),
      );
      shortConfig.startActiveDiscoveryTimer();

      await Future.delayed(const Duration(milliseconds: 700));
      shortConfig.pauseTimer();

      final pausedSeconds = shortConfig.activeDiscoverySeconds;
      expect(pausedSeconds, greaterThanOrEqualTo(0));

      shortConfig.resumeTimer();

      await Future.delayed(const Duration(milliseconds: 1100));
      expect(shortConfig.activeDiscoverySeconds, greaterThan(pausedSeconds));

      shortConfig.dispose();
    });

    test('stopTimer clears all state', () async {
      adService.startActiveDiscoveryTimer();
      await Future.delayed(const Duration(milliseconds: 600));
      adService.stopTimer();

      expect(adService.adTimerStarted, false);
      expect(adService.activeDiscoverySeconds, 0);
      expect(adService.adEligible, false);
    });

    test('fetchAd returns null when not eligible', () async {
      adService.startActiveDiscoveryTimer();
      final result = await adService.fetchAd('user1');
      expect(result, isNull);
    });

    test('fetchAd returns null when already displayed', () async {
      adService.startActiveDiscoveryTimer();
      adService.markAdDisplayed(
        const Advertisement(id: 'ad1', campaignId: 'c1', title: 'T', description: 'D', imageUrl: 'url', ctaText: 'CTA', destinationUrl: 'https://example.com'),
      );
      final result = await adService.fetchAd('user1');
      expect(result, isNull);
    });

    test('fetchAd returns null when loading already in progress', () async {
      final shortConfig = AdService(
        repository: mockRepo,
        config: const AdConfig(adIntervalSeconds: 1),
      );
      shortConfig.startActiveDiscoveryTimer();
      await Future.delayed(const Duration(milliseconds: 1200));

      final ad = const Advertisement(
        id: 'ad1', campaignId: 'c1', title: 'Test Ad', description: 'desc', imageUrl: 'url', ctaText: 'CTA', destinationUrl: 'https://example.com',
      );

      when(() => mockRepo.fetchAd('user1'))
          .thenAnswer((_) async => (ad, const AdConfig()));

      final adService1 = shortConfig;
      final future1 = adService1.fetchAd('user1');
      final future2 = adService1.fetchAd('user1');

      final result1 = await future1;
      final result2 = await future2;

      expect(result1, isNotNull);
      expect(result2, isNull);
      shortConfig.dispose();
    });

    test('fetchAd returns ad when eligible and not displayed', () async {
      final shortConfig = AdService(
        repository: mockRepo,
        config: const AdConfig(adIntervalSeconds: 1),
      );
      shortConfig.startActiveDiscoveryTimer();
      await Future.delayed(const Duration(milliseconds: 1200));

      final ad = const Advertisement(
        id: 'ad1', campaignId: 'c1', title: 'Test Ad', description: 'desc', imageUrl: 'url', ctaText: 'CTA', destinationUrl: 'https://example.com',
      );

      when(() => mockRepo.fetchAd('user1'))
          .thenAnswer((_) async => (ad, const AdConfig()));

      final result = await shortConfig.fetchAd('user1');
      expect(result, isNotNull);
      expect(result!.id, 'ad1');

      shortConfig.dispose();
    });

    test('fetchAd returns null when advertising disabled', () async {
      final disabledConfig = AdService(
        repository: mockRepo,
        config: const AdConfig(isAdvertisingEnabled: false),
      );
      disabledConfig.startActiveDiscoveryTimer();
      await Future.delayed(const Duration(milliseconds: 1200));
      // Need to make adEligible first, but config has default 120s interval
      // Use short interval instead
      disabledConfig.dispose();

      final disabledShort = AdService(
        repository: mockRepo,
        config: const AdConfig(adIntervalSeconds: 1, isAdvertisingEnabled: false),
      );
      disabledShort.startActiveDiscoveryTimer();
      await Future.delayed(const Duration(milliseconds: 1200));
      final result = await disabledShort.fetchAd('user1');
      expect(result, isNull);
      disabledShort.dispose();
    });

    test('resetAdInterval restarts the timer', () async {
      final shortConfig = AdService(
        repository: mockRepo,
        config: const AdConfig(adIntervalSeconds: 1),
      );
      shortConfig.startActiveDiscoveryTimer();
      await Future.delayed(const Duration(milliseconds: 1200));

      expect(shortConfig.adEligible, true);

      shortConfig.resetAdInterval();

      expect(shortConfig.adDisplayed, false);
      expect(shortConfig.adEligible, false);
      expect(shortConfig.activeDiscoverySeconds, 0);

      shortConfig.dispose();
    });

    test('recordImpression calls repository', () async {
      when(() => mockRepo.recordEvent('user1', 'ad1', 'impression', metadata: null))
          .thenAnswer((_) async {});
      await adService.recordImpression('user1', 'ad1');
      verify(() => mockRepo.recordEvent('user1', 'ad1', 'impression', metadata: null)).called(1);
    });

    test('recordClick calls repository', () async {
      when(() => mockRepo.recordEvent('user1', 'ad1', 'click', metadata: null))
          .thenAnswer((_) async {});
      await adService.recordClick('user1', 'ad1');
      verify(() => mockRepo.recordEvent('user1', 'ad1', 'click', metadata: null)).called(1);
    });

    test('recordReport calls repository with reason', () async {
      when(() => mockRepo.recordEvent('user1', 'ad1', 'report', metadata: {'reason': 'spam'}))
          .thenAnswer((_) async {});
      await adService.recordReport('user1', 'ad1', reason: 'spam');
      verify(() => mockRepo.recordEvent('user1', 'ad1', 'report', metadata: {'reason': 'spam'})).called(1);
    });

    test('recordHide calls repository', () async {
      when(() => mockRepo.recordEvent('user1', 'ad1', 'hide', metadata: null))
          .thenAnswer((_) async {});
      await adService.recordHide('user1', 'ad1');
      verify(() => mockRepo.recordEvent('user1', 'ad1', 'hide', metadata: null)).called(1);
    });

    test('markAdDisplayed updates state correctly', () {
      final ad = const Advertisement(
        id: 'ad1', campaignId: 'c1', title: 'Test Ad', description: 'desc', imageUrl: 'url', ctaText: 'CTA', destinationUrl: 'https://example.com',
      );
      adService.markAdDisplayed(ad);
      expect(adService.adDisplayed, true);
      expect(adService.adEligible, false);
      expect(adService.adId, 'ad1');
    });
  });
}
