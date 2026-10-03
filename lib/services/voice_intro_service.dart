import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Handles recording, uploading, and playing back voice intros.
///
/// Voice intros are short audio recordings (up to 30 seconds) stored in the
/// private `voice-intros` Supabase Storage bucket under a per-user folder.
/// The URL is stored in the `profiles.voice_intro_url` column and streamed
/// back to other users through the discovery RPCs.
class VoiceIntroService {
  static final VoiceIntroService _instance = VoiceIntroService._internal();
  factory VoiceIntroService() => _instance;
  VoiceIntroService._internal();

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  /// Maximum recording duration in seconds.
  static const int maxDurationSeconds = 30;

  /// The storage bucket where voice intros live.
  static const String bucket = 'voice-intros';

  /// Start recording a voice intro.
  /// Returns true if recording started successfully.
  Future<bool> startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    const path = '/voice_intro.wav';
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}$path';

    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Stop recording and return the local file path.
  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    if (await file.exists() && await file.length() > 0) {
      return path;
    }
    return null;
  }

  /// Cancel an in-progress recording.
  Future<void> cancelRecording() async {
    await _recorder.stop();
  }

  /// Upload a recorded voice intro to Supabase Storage.
  /// Returns the public URL of the uploaded file.
  Future<String?> uploadVoiceIntro(String localPath) async {
    final client = SupabaseConfig.client;
    if (client == null) return null;

    final userId = SupabaseConfig.currentUserId;
    if (userId.isEmpty || userId == 'unauthenticated' || userId == 'me') {
      return null;
    }

    final file = File(localPath);
    if (!await file.exists()) return null;

    final fileName = '$userId/voice_intro.wav';

    try {
      await client.storage.from(bucket).upload(
            fileName,
            file,
            fileOptions: const FileOptions(upsert: true),
          );

      final url = client.storage.from(bucket).getPublicUrl(fileName);
      return url;
    } catch (e) {
      return null;
    }
  }

  /// Save the voice intro URL to the user's profile.
  Future<bool> saveVoiceIntroUrl(String url) async {
    final client = SupabaseConfig.client;
    if (client == null) return false;

    try {
      await client
          .from('profiles')
          .update({'voice_intro_url': url})
          .eq('user_id', SupabaseConfig.currentUserId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Play a voice intro from a URL.
  Future<void> playVoiceIntro(String url) async {
    try {
      await _player.play(UrlSource(url));
    } catch (e) {
      // ignore
    }
  }

  /// Stop playback.
  Future<void> stopPlayback() async {
    await _player.stop();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    await _player.dispose();
    await _recorder.dispose();
  }

  /// Check if the recorder is currently recording.
  Future<bool> isRecording() => _recorder.isRecording();

  /// Format a duration for display (e.g. "0:15").
  static String formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
