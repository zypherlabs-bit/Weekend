# Weekend Component Inventory

## lib/widgets/
- ad_card.dart — AdCard (in-feed ad rendering + event recording)
- date_ideas_widget.dart — DateIdeasWidget
- discovery_card.dart — DiscoveryCard / SwipeDeck support
- filter_controls.dart — filter controls
- icebreaker_widget.dart — IcebreakerWidget
- intro_video_player.dart — IntroVideoPlayer
- location_radius_filter.dart — LocationRadiusFilter
- match_celebration_dialog.dart — MatchCelebrationDialog
- safety_dialogs.dart — safety dialogs
- weekend_design_system.dart — WeekendTokens, WeekendCard, WeekendGlass, WeekendGlassCard,
  WeekendGlassButton, WeekendGlassIconButton, WeekendGlassTextField, WeekendGlassChip,
  WeekendGlassDialog, WeekendGlassBottomSheet, WeekendGlassNavigationBar, WeekendAtmosphere,
  WeekendLogo
- weekend_empty_state.dart — WeekendEmptyState
- weekend_states.dart — WeekendErrorState

## lib/features/* (screen-level)
auth, chat, discovery, home, likes, notifications, onboarding, plans, profile, qr, safety,
security, settings.

## lib/models, providers, repositories, services — data/state layer (unchanged by redesign).

Total Dart files: 107. All screens consume the shared design system.
