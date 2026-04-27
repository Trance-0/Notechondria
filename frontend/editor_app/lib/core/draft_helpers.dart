part of notechondria_frontend;

/// `_storeLocalDraft` and `_buildOfflineFallbackDraft` moved into
/// the shared `AppShellDraftHelpersMixin` (notechondria_shared
/// 0.1.80). Call sites use the public `storeLocalDraft()` /
/// `buildOfflineFallbackDraft()` names. This file now only exists
/// to anchor the (currently empty) extension and keep the
/// `core/draft_helpers.dart` import path stable across the parts
/// list — it can be deleted entirely once a future round
/// regenerates the parts manifest.
