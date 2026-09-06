class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  static const String storageBucket = 'profile-photos';
  
  static bool get isConfigured => url.isNotEmpty && anonKey.isNotEmpty && 
      url != 'https://your-project-ref.supabase.co' && 
      anonKey != 'public-anon-key-here';
}
