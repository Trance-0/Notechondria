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
export 'src/utils/format_bytes.dart' show formatBytes;
export 'src/utils/ping_backend.dart' show pingBackend;
export 'src/utils/local_archive.dart'
    show
        kLocalArchivePackageVersion,
        LocalArchiveApp,
        LocalArchiveAppTag,
        LocalArchiveInput,
        LocalArchiveOutput,
        readLocalArchive,
        tryReadLegacyEnvConfig,
        writeLocalArchive;
export 'src/utils/local_attachment_store.dart'
    show
        LocalAttachment,
        LocalAttachmentBackend,
        LocalAttachmentStore,
        LocalAttachmentStoreException;

export 'src/components/auth_dialogs.dart'
    show AuthHub, EmailPasswordDialog, FeedbackText;
export 'src/components/debug_log.dart'
    show
        DebugLogCard,
        DebugLogController,
        DebugLogEntry,
        DebugLogLevel,
        DebugLogLevelLabel,
        PingResult;
export 'src/components/debug_widgets.dart' show ApiDebugCard, ApiDebugSummary;
export 'src/components/error_state.dart' show ErrorStateView;
export 'src/components/navigation.dart' show ConfirmWithDelayDialog, SidebarItem;
export 'src/components/custom_meta_list_editor.dart'
    show CustomMetaController, CustomMetaListEditor;
export 'src/components/mcp_skill_section.dart'
    show GithubSyncExperimentalCard, McpSkillSection;
export 'src/components/note_cover_image.dart' show NoteCoverImage;

export 'src/http/http_client_internals_mixin.dart'
    show HttpClientInternalsMixin;
export 'src/components/phased_status.dart' show PhasedStatusIndicator;
export 'src/components/splash_screen.dart' show SplashScreen;

export 'src/settings/app_preferences_card.dart'
    show AppPreferencesCard, kEditorModes, kThemePresetEntries;

export 'src/app_shell/app_shell_course_helpers_mixin.dart'
    show AppShellCourseHelpersMixin;
export 'src/app_shell/app_shell_draft_helpers_mixin.dart'
    show AppShellDraftHelpersMixin;
export 'src/app_shell/app_shell_local_persist_mixin.dart'
    show AppShellLocalPersistMixin;
export 'src/app_shell/app_shell_log_mixin.dart' show AppShellLogMixin;
export 'src/app_shell/app_shell_auth_actions_mixin.dart'
    show AppShellAuthActionsMixin;
export 'src/app_shell/app_shell_oauth_mixin.dart' show AppShellOAuthMixin;
export 'src/app_shell/app_shell_session_mixin.dart' show AppShellSessionMixin;
export 'src/app_shell/auth_client.dart' show AuthClient;
