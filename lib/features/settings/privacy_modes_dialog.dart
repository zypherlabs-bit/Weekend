import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';

import '../../repositories/privacy_repository.dart';

/// Privacy & availability modes backed by migration 031's server RPCs:
///
///   * Incognito — discoverable only by people already liked or matched
///   * Snooze — temporarily removed from discovery for a chosen duration
///   * Away status — an optional note visible only to existing connections
///   * Travel Mode — a user-chosen approximate destination that expires
///   * Online Now consent — whether the "active in the last 5 minutes" flag
///     may surface to others at all
///
/// Every toggle routes through `PrivacyRepository`, which calls the server
/// RPC and reports only what the server confirmed. A switch never stays in
/// a state the server did not adopt: on failure it snaps back.
class PrivacyModesDialog extends StatefulWidget {
  const PrivacyModesDialog({super.key});

  @override
  State<PrivacyModesDialog> createState() => _PrivacyModesDialogState();
}

class _PrivacyModesDialogState extends State<PrivacyModesDialog> {
  final PrivacyRepository _repository = PrivacyRepository();
  final TextEditingController _awayController = TextEditingController();
  final TextEditingController _travelController = TextEditingController();

  bool _loading = true;

  // Values previously confirmed by the server (fetched on open). Empty
  // maps (failed read / unconfigured backend) render the switches OFF and
  // disabled-honest: turning one on still attempts the RPC.
  bool _incognito = false;
  bool _snooze = false;
  bool _showOnline = true;
  String _awayNote = '';
  String _travelCity = '';

  bool _busyIncognito = false;
  bool _busySnooze = false;
  bool _busyAway = false;
  bool _busyTravel = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentState();
  }

  @override
  void dispose() {
    _awayController.dispose();
    _travelController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentState() async {
    final toggles = await _repository.fetchPrivacyToggles();
    final travel = await _repository.fetchTravelConfig();
    if (!mounted) return;
    setState(() {
      _incognito = toggles?['incognito_mode'] == true;
      _snooze = toggles?['snooze_mode'] == true;
      _showOnline = toggles?['show_online_now'] is bool
          ? toggles!['show_online_now'] as bool
          : true;
      _travelCity = (travel?['travel_city'] as String?) ?? '';
      _awayController.text = _awayNote;
      _travelController.text = _travelCity;
      _loading = false;
    });
  }

  void _notify(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red : const Color(0xFF4CAF50),
      ),
    );
  }

  Future<void> _toggleIncognito(bool value) async {
    setState(() => _busyIncognito = true);
    // Optimistic only for the spinner; the switch itself adopts the server's
    // answer. A snapshot underneath must not lie about visibility.
    final ok = await _repository.setPrivacyMode('incognito', enabled: value);
    if (!mounted) return;
    setState(() {
      _busyIncognito = false;
      if (ok) _incognito = value;
    });
    if (!ok) {
      _notify(
        value
            ? 'Incognito could not be enabled. Try again.'
            : 'Incognito could not be disabled. Try again.',
        isError: true,
      );
    }
  }

  Future<void> _toggleSnooze(bool value) async {
    if (value) {
      final hours = await _chooseSnoozeDuration();
      if (hours == null || !mounted) return;
      setState(() => _busySnooze = true);
      final ok = await _repository.setPrivacyMode(
        'snooze',
        enabled: true,
        snoozeHours: hours,
      );
      if (!mounted) return;
      setState(() {
        _busySnooze = false;
        if (ok) _snooze = true;
      });
      _notify(ok
          ? 'Snoozing until the server-enabled window ends.'
          : 'Snooze could not be enabled. Try again.', isError: !ok);
      return;
    }
    setState(() => _busySnooze = true);
    final ok = await _repository.setPrivacyMode('snooze', enabled: false);
    if (!mounted) return;
    setState(() {
      _busySnooze = false;
      if (ok) _snooze = false;
    });
    if (!ok) _notify('Snooze could not be disabled. Try again.', isError: true);
  }

  Future<int?> _chooseSnoozeDuration() {
    return showModalBottomSheet<int>(
      context: context,
      backgroundColor: const Color(0xFF22202A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Take a break for how long?',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            for (final (hours, label) in const [
              (2, '2 hours'),
              (24, '24 hours'),
              (72, '3 days'),
              (168, '7 days'),
            ])
              ListTile(
                title: Text(label, style: const TextStyle(color: Colors.white)),
                onTap: () => Navigator.of(context).pop(hours),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAway() async {
    final text = _awayController.text.trim();
    setState(() => _busyAway = true);
    final result = await _repository.setAwayStatus(
      text.isEmpty ? null : text,
      hours: 24,
    );
    if (!mounted) return;
    setState(() {
      _busyAway = false;
      if (result != null) _awayNote = text.isNotEmpty ? result : '';
    });
    if (result != null) {
      _notify('Away status is now what the server stored.');
    } else {
      _notify(
        'The away note was rejected. Keep it under 140 characters and '
        'without links or social handles.',
        isError: true,
      );
    }
  }

  /// Enable Travel Mode for the entered city.
  ///
  /// Geocoding happens on-device with the `geocoding` package the app
  /// already uses: the coarse city coordinates the user picked are stored as
  /// their own travel destination. The real GPS location is never moved; the
  /// destination expires server-side after 7 days.
  Future<void> _enableTravel() async {
    final city = _travelController.text.trim();
    if (city.isEmpty) return;
    setState(() => _busyTravel = true);
    ({double lat, double lon})? coords;
    try {
      final locations = await locationFromAddress(city);
      if (locations.isNotEmpty) {
        coords = (
          lat: locations.first.latitude,
          lon: locations.first.longitude,
        );
      }
    } catch (_) {
      // fall through: no geocode result means no destination.
    }
    if (coords == null) {
      if (!mounted) return;
      setState(() => _busyTravel = false);
      _notify(
        'Could not find "$city" as a location. Try a different spelling.',
        isError: true,
      );
      return;
    }
    final ok = await _repository.setTravelLocation(
      city: city,
      latitude: coords.lat,
      longitude: coords.lon,
    );
    if (!mounted) return;
    setState(() {
      _busyTravel = false;
      if (ok) _travelCity = city;
    });
    _notify(ok
        ? 'Travel Mode on — your profile may appear around $city for 7 days.'
        : 'Travel Mode is not available for this account on the server.',
        isError: !ok);
  }

  Future<void> _disableTravel() async {
    setState(() => _busyTravel = true);
    final ok = await _repository.setTravelLocation();
    if (!mounted) return;
    setState(() {
      _busyTravel = false;
      if (ok) {
        _travelCity = '';
        _travelController.clear();
      }
    });
    if (!ok) _notify('Travel Mode could not be disabled. Try again.', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1C162E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Privacy & Availability',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else ...[
              SwitchListTile(
                title:
                    const Text('Incognito', style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _incognito
                      ? 'Visible only to people you already liked or matched'
                      : 'Shown in normal discovery',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _incognito,
                onChanged: _busyIncognito ? null : _toggleIncognito,
                activeThumbColor: const Color(0xFFFF4B72),
              ),
              SwitchListTile(
                title: const Text(
                  'Snooze',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  _snooze
                      ? 'You are hidden from discovery until the window ends'
                      : 'Temporarily leave discovery without deleting anything',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _snooze,
                onChanged: _busySnooze ? null : _toggleSnooze,
                activeThumbColor: const Color(0xFFFF4B72),
              ),
              SwitchListTile(
                title: const Text('Hide my online status',
                    style: TextStyle(color: Colors.white)),
                subtitle: Text(
                  _showOnline
                      ? 'People can see the Online Now dot on your cards'
                      : 'Your activity is never surfaced to others',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: !_showOnline,
                onChanged: _busySnooze ? null : (v) => _toggleOnline(quiet: v),
                activeThumbColor: const Color(0xFFFF4B72),
              ),
              const Divider(color: Colors.white10),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Away note (only existing connections see it)',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _awayController,
                      maxLength: 140,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        counterStyle: TextStyle(color: Colors.white38),
                        hintText: 'Gone hiking this weekend!',
                        filled: true,
                        fillColor: Color(0xFF2E244A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_awayNote.isNotEmpty)
                          TextButton(
                            onPressed: _busyAway ? null : _saveAway,
                            // An empty field + save = the server-confirmed clear.
                            child: const Text('Clear',
                                style: TextStyle(color: Colors.white54)),
                          ),
                        TextButton(
                          onPressed: _busyAway ? null : _saveAway,
                          child: _busyAway
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : Text(
                                  _awayNote.isEmpty ? 'Set away note' : 'Save',
                                  style:
                                      const TextStyle(color: Color(0xFFFF9966)),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(color: Colors.white10),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Travel Mode (destination expires after 7 days)',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (_busyTravel)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (_travelCity.isNotEmpty) ...[
                      Text(
                        'Currently sampling: $_travelCity',
                        style:
                            const TextStyle(color: Color(0xFFFF9966), fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        onPressed: _disableTravel,
                        child: const Text('Turn Travel Mode off',
                            style: TextStyle(color: Colors.white54)),
                      ),
                    ] else
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _travelController,
                              textInputAction: TextInputAction.done,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Destination city',
                                filled: true,
                                fillColor: Color(0xFF2E244A),
                                border: OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _enableTravel,
                            child: const Text('Enable',
                                style: TextStyle(color: Color(0xFFFF9966))),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child:
                    const Text('Close', style: TextStyle(color: Colors.white54)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Toggle the Online Now consent. The server-side effect comes from the
  /// `show_online_now` user_settings column, which discovery reads with a
  /// safe default; the write follows the same upsert path as push settings.
  Future<void> _toggleOnline({required bool quiet}) async {
    // `quiet` == "hide me" == store show_online_now = !quiet.
    final newValue = !quiet;
    setState(() => _showOnline = newValue);
    if (!await _repository.setShowOnlineNow(newValue)) {
      if (!mounted) return;
      setState(() => _showOnline = !newValue);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That preference could not be saved. Try again.'),
        ),
      );
    }
  }
}
