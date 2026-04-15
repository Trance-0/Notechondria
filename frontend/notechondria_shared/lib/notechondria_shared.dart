/// Shared UI building blocks for Notechondria's three Flutter apps
/// (editor, planner, portal).
///
/// Each app's `lib/main.dart` imports this barrel once at the library level,
/// which makes the exported symbols available to every `part of
/// notechondria_frontend;` file in that app.
library notechondria_shared;

export 'src/models/action_feedback.dart' show ActionFeedback;
export 'src/models/api_debug_snapshot.dart' show ApiDebugSnapshot;

export 'src/utils/blur_dialog.dart' show showBlurDialog;
export 'src/utils/compact_timestamp.dart' show formatCompactTimestamp;

export 'src/components/debug_widgets.dart' show ApiDebugCard, ApiDebugSummary;
export 'src/components/error_state.dart' show ErrorStateView;
export 'src/components/navigation.dart' show ConfirmWithDelayDialog, SidebarItem;
export 'src/components/splash_screen.dart' show SplashScreen;
