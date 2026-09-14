import 'dart:async';import 'package:flutter/widgets.dart';import 'package:flutter_riverpod/flutter_riverpod.dart';import '../models/models.dart';import '../repositories/ad_repository.dart';class AdService extends ChangeNotifier {  final AdRepository _repository;  final AdConfig config;  bool _adTimerStarted = false;  int _activeDiscoverySeconds = 0;  bool _adEligible = false;  bool _adDisplayed = false;  String? _adId;  String? _adImpressionId;  bool _adLoading = false;  String? _adError;  bool _paused = false;  Timer? _timer;  bool get adTimerStarted => _adTimerStarted;  int get activeDiscoverySeconds => _activeDiscoverySeconds;  bool get adEligible => _adEligible;  bool get adDisplayed => _adDisplayed;  String? get adId => _adId;  bool get adLoading => _adLoading;  String? get adError => _adError;  bool get shouldShowAd => !_adDisplayed && _adEligible && _adTimerStarted;  AdService({    required AdRepository repository,    this.config = const AdConfig(),  }) : _repository = repository;  
/// Start the active discovery timer. This begins counting active seconds.
  
/// Only call when the user is actively browsing the discovery feed.
  void startActiveDiscoveryTimer() {    if (_adTimerStarted && _timer?.isActive == true) return;    _adTimerStarted = true;    _paused = false;    _activeDiscoverySeconds = 0;    _adEligible = false;    _adDisplayed = false;    _adId = null;    _adLoading = false;    _adError = null;    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {      if (_paused) return;      _activeDiscoverySeconds++;      if (_activeDiscoverySeconds >= config.adIntervalSeconds) {        _adEligible = true;        _timer?.cancel();        notifyListeners();      } else {        notifyListeners();      }    });    notifyListeners();  }  
/// Pause the timer. Called when:
  
/// - App goes to background
  
/// - User leaves discovery screen
  
/// - Device becomes inactive
  void pauseTimer() {    if (!_paused) {      _paused = true;      notifyListeners();    }  }  
/// Resume the timer. Called when user returns to active discovery.
  void resumeTimer() {    if (_paused && _adTimerStarted) {      _paused = false;      if (_timer?.isActive != true && !_adEligible) {        _timer = Timer.periodic(const Duration(seconds: 1), (timer) {          if (_paused) return;          _activeDiscoverySeconds++;          if (_activeDiscoverySeconds >= config.adIntervalSeconds) {            _adEligible = true;            _timer?.cancel();            notifyListeners();          } else {            notifyListeners();          }        });      }      notifyListeners();    }  }  
/// Stop the timer entirely (e.g., user closes Discover screen)
  void stopTimer() {    _timer?.cancel();    _timer = null;    _adTimerStarted = false;    _paused = false;    notifyListeners();  }  
/// Mark ad as displayed and reset the active-ad interval
  void markAdDisplayed(Advertisement ad) {    _adDisplayed = true;    _adEligible = false;    _adId = ad.id;    _adLoading = false;    _adError = null;    notifyListeners();  }  
/// Fetch an advertisement from the server. Returns the ad if one is eligible.
  Future<Advertisement?> fetchAd(String userId) async {    if (!_adEligible || _adDisplayed || _adLoading) return null;    if (!config.isAdvertisingEnabled) return null;    _adLoading = true;    _adError = null;    notifyListeners();    try {      final (ad, fetchedConfig) = await _repository.fetchAd(userId);      if (ad != null) {        _adId = ad.id;        _adLoading = false;        _adError = null;        notifyListeners();        return ad;      } else {        _adLoading = false;        _adError = 'No ad available';        notifyListeners();        return null;      }    } catch (e) {      _adLoading = false;      _adError = e.toString();      notifyListeners();      return null;    }  }  
/// Reset ad state after an ad has been displayed or skipped/hidden.
  
/// Restarts the active discovery timer for the next cycle.
  void resetAdInterval() {    _adDisplayed = false;    _adEligible = false;    _adId = null;    _adLoading = false;    _adError = null;    _activeDiscoverySeconds = 0;    _adTimerStarted = true;    if (!_paused && _timer?.isActive != true) {      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {        if (_paused) return;        _activeDiscoverySeconds++;        if (_activeDiscoverySeconds >= config.adIntervalSeconds) {          _adEligible = true;          _timer?.cancel();          notifyListeners();        } else {          notifyListeners();        }      });    }    notifyListeners();  }  
/// Record an ad impression (server-side validated)
  Future<void> recordImpression(String userId, String adId) async {    try {      await _repository.recordEvent(userId, adId, 'impression');    } catch (e) {      
// Server-side: client records event but validation happens server-side
    }  }  
/// Record an ad click (server-side validated)
  Future<void> recordClick(String userId, String adId) async {    try {      await _repository.recordEvent(userId, adId, 'click');    } catch (e) {      
// ignore - server-side validation
    }  }  
/// Record ad report
  Future<void> recordReport(String userId, String adId, {String? reason}) async {    try {      await _repository.recordEvent(userId, adId, 'report', metadata: {'reason': reason});    } catch (e) {      
// ignore
    }  }  
/// Record ad hide
  Future<void> recordHide(String userId, String adId) async {    try {      await _repository.recordEvent(userId, adId, 'hide');    } catch (e) {      
// ignore
    }  }  @override  void dispose() {    stopTimer();    super.dispose();  }}final adServiceProvider = ChangeNotifierProvider<AdService>((ref) {  final adRepo = AdRepository();  return AdService(repository: adRepo);});