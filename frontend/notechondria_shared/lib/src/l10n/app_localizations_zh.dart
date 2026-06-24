// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get languageName => '简体中文';

  @override
  String get appName => '记粒体';

  @override
  String get appNameEditor => '记粒体编辑器';

  @override
  String get appNamePlanner => '记粒体规划器';

  @override
  String get appNamePortal => '记粒体门户';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSystem => '跟随系统';

  @override
  String get commonSkip => '跳过';

  @override
  String get commonClose => '关闭';

  @override
  String get commonDone => '完成';

  @override
  String get commonCancel => '取消';

  @override
  String get commonBack => '返回';

  @override
  String get commonNext => '下一步';

  @override
  String get commonSave => '保存';

  @override
  String get commonCreate => '创建';

  @override
  String get commonDelete => '删除';

  @override
  String get commonRetry => '重试';

  @override
  String get commonDismiss => '忽略';

  @override
  String get commonEdit => '编辑';

  @override
  String get commonExport => '导出';

  @override
  String get commonRestore => '恢复';

  @override
  String get commonRemove => '移除';

  @override
  String get commonChange => '更换';

  @override
  String get commonChoose => '选择';

  @override
  String get commonGotIt => '知道了';

  @override
  String get commonLoading => '加载中……';

  @override
  String get splashStartingEditor => '正在启动记粒体编辑器';

  @override
  String get splashStartingPlanner => '正在启动记粒体规划器';

  @override
  String get splashStartingPortal => '正在启动记粒体门户';

  @override
  String get splashLoadingLocalWorkspace => '正在加载本地工作区';

  @override
  String get splashLoadingLocalPlannerData => '正在加载本地规划数据';

  @override
  String get splashLoadingLocalState => '正在加载本地状态';

  @override
  String get splashRestoringSession => '正在恢复会话';

  @override
  String get splashCompletingSignIn => '正在完成登录';

  @override
  String get splashConnectingToServer => '正在连接服务器';

  @override
  String get splashLoadingPublicNotesData => '正在加载公开笔记数据';

  @override
  String get splashLoadingCategories => '正在加载分类';

  @override
  String get splashLoadingNotes => '正在加载笔记';

  @override
  String get localArchiveTypeLabel => '记粒体归档';

  @override
  String get commonCopy => '复制';

  @override
  String get commonSaving => '正在保存……';

  @override
  String get commonUploading => '正在上传……';

  @override
  String get commonUnknown => '未知';

  @override
  String get navNavigation => '导航';

  @override
  String get navAllNotes => '全部笔记';

  @override
  String get navCategories => '分类';

  @override
  String get navNewCategory => '新建分类';

  @override
  String get navSettings => '设置';

  @override
  String get categoryUnsubscribe => '取消订阅';

  @override
  String get categoryEditTitle => '编辑分类';

  @override
  String get categorySubscribedTitle => '已订阅的分类';

  @override
  String get categoryNameLabel => '分类名称';

  @override
  String get categoryIconLabel => '图标：';

  @override
  String get categoryDeleteHelp => '删除会把所有笔记移动到默认分类。';

  @override
  String get categorySubscribedHelp =>
      '此分类由其他用户发布。重命名、更换图标和删除仅对所有者开放。你仍可取消订阅以将其从侧边栏移除。';

  @override
  String get feedSearchLocalDrafts => '搜索本地草稿';

  @override
  String get feedSearchPrivate => '搜索你的私密笔记';

  @override
  String get feedSearchPublic => '搜索你的公开笔记';

  @override
  String get feedSearchNotes => '搜索你的笔记';

  @override
  String get feedYourPrivateNotes => '你的私密笔记';

  @override
  String get feedYourPublicNotes => '你的公开笔记';

  @override
  String get feedRecentNotes => '最近的笔记';

  @override
  String get feedPublicNotes => '公开笔记';

  @override
  String get feedEmptyAnon => '还没有笔记。点击添加按钮创建一篇本地草稿。';

  @override
  String get feedEmptyPrivate => '还没有私密笔记。';

  @override
  String get feedEmptyPublic => '还没有公开笔记。';

  @override
  String get feedEmptyPersonal => '还没有云端笔记。点击添加按钮创建一篇。';

  @override
  String get feedScopePersonal => '个人笔记';

  @override
  String get feedScopePrivate => '私密笔记';

  @override
  String get feedScopePublic => '公开笔记';

  @override
  String get feedScopeLocalOnly => '仅本地草稿';

  @override
  String get feedComposerCreate => '新建笔记';

  @override
  String get feedComposerImport => '导入 Markdown 或 zip';

  @override
  String get feedShowLabel => '显示：';

  @override
  String get feedLocalCategoryWarning => '本地分类只包含本地草稿。切换到已同步的分类以筛选云端笔记。';

  @override
  String get feedUnsyncedDrafts => '未同步的本地草稿';

  @override
  String get feedSyncAll => '全部同步';

  @override
  String get feedSyncHelp => '本地草稿默认保持私密。同步会将它们作为私密云端笔记上传。';

  @override
  String get feedLocalDrafts => '本地草稿';

  @override
  String get feedEmptyCloudMatch => '暂无匹配的云端笔记。同步一篇本地草稿或创建一篇新笔记。';

  @override
  String get feedLoadPublicNotes => '加载公开笔记';

  @override
  String get feedEmptyLocalCategory => '此离线分类中还没有本地草稿。点击添加按钮创建一篇。';

  @override
  String get feedEmptyLocal => '还没有本地草稿。点击添加按钮创建一篇。';

  @override
  String get feedFabImport => '新建笔记。长按可导入 Markdown。';

  @override
  String get feedFabImportLocal => '新建本地草稿。长按可导入 Markdown。';

  @override
  String get feedImportMarkdown => '导入 Markdown';

  @override
  String get feedSearchCloud => '搜索你的云端笔记';

  @override
  String get feedSyncToCloud => '同步到云端';

  @override
  String get feedLoadNotes => '加载笔记';

  @override
  String get feedLocalDraftBadge => '本地草稿';

  @override
  String get feedBadgePublic => '公开';

  @override
  String get feedBadgePrivate => '私密';

  @override
  String get feedEmptyCloudSynced => '还没有已同步的云端笔记。同步一篇本地草稿或新建一篇笔记。';

  @override
  String get feedEmptyLocalLogin => '还没有本地草稿。点击添加按钮创建一篇，登录后再同步。';

  @override
  String get feedCourseMetaHint => '课程信息可在编辑器详情面板中编辑';

  @override
  String get noteUntitled => '无标题笔记';

  @override
  String get noteOptions => '选项';

  @override
  String get noteCopyLink => '复制链接';

  @override
  String get noteLinkCopied => '链接已复制到剪贴板';

  @override
  String get noteExportMarkdown => '导出 Markdown';

  @override
  String get noteMoreActions => '更多操作';

  @override
  String get noteEditMeta => '编辑笔记信息';

  @override
  String get noteSwitchPlainText => '切换编辑器：纯文本';

  @override
  String get noteSwitchLiveMarkdown => '切换编辑器：实时 Markdown';

  @override
  String get noteViewAttachments => '查看附件';

  @override
  String get noteTitleHint => '标题';

  @override
  String get noteWriteHint => '撰写你的笔记……';

  @override
  String get noteAttachFile => '添加附件';

  @override
  String get noteMetaCoverImage => '封面图片';

  @override
  String get noteMetaCoverHasHelp => '在查看模式下显示在笔记上方。';

  @override
  String get noteMetaCoverNoneHelp => '尚无封面——读者会看到根据笔记 URL 生成的条形码。';

  @override
  String get noteMetaCoverSyncFirst => '上传封面图片前，请先将此笔记同步到云端。';

  @override
  String get noteMetaReplace => '替换';

  @override
  String get noteMetaUpload => '上传';

  @override
  String get noteMetaDetails => '笔记详情';

  @override
  String get noteMetaNoCourse => '未指定课程';

  @override
  String get noteMetaAssignedCourse => '所属课程 / 计划';

  @override
  String get noteMetaSection => '章节';

  @override
  String get noteMetaDescription => '简短描述 / 备注';

  @override
  String get noteMetaPublicNote => '公开笔记';

  @override
  String get noteMetaPublicHelp => '公开笔记会出现在推荐流中。';

  @override
  String get noteMetaPublicSyncFirst => '将此笔记设为公开前，请先同步到云端。';

  @override
  String get noteMetaVersionHistory => '版本历史';

  @override
  String get noteMetaNoVersions => '还没有已保存的版本。';

  @override
  String get noteMetaSaving => '正在保存……';

  @override
  String get editorBlockParagraph => '段落';

  @override
  String get editorBlockHeading => '标题';

  @override
  String get editorBlockList => '列表';

  @override
  String get editorBlockCode => '代码';

  @override
  String get editorBlockQuote => '引用';

  @override
  String get editorBlockLink => '链接';

  @override
  String get editorBlockImage => '图片';

  @override
  String get editorBlockDelete => '删除区块';

  @override
  String get editorBold => '加粗';

  @override
  String get editorItalic => '斜体';

  @override
  String get editorStrike => '删除线';

  @override
  String get editorAddParagraph => '添加段落';

  @override
  String get editorAddList => '添加列表';

  @override
  String get editorAddCode => '添加代码';

  @override
  String get editorHeadingTokenHint => '标题标记（## 或 ###）';

  @override
  String get editorBlockContentHint => '撰写区块内容……';

  @override
  String get editorModePlain => '纯文本';

  @override
  String get editorModePreview => '预览';

  @override
  String get editorModeBlocks => '区块';

  @override
  String get editorModeLabel => '编辑模式';

  @override
  String get editorNotSaved => '未保存';

  @override
  String editorSavedAt(String time) {
    return '已于 $time 保存';
  }

  @override
  String get privateNoteTitle => '私密笔记';

  @override
  String privateNoteBody(String link) {
    return '这篇共享笔记是私密的。请在「设置 > 账户」中登录，然后重新打开此链接：\n\n$link';
  }

  @override
  String get privateNoteSignInError =>
      '这篇笔记是私密的。登录后才能查看——打开「设置 → 账户」登录，链接随后即可加载。';

  @override
  String get privateNoteOpenSettings => '打开设置';

  @override
  String noteLoadError(String reason) {
    return '无法加载笔记：$reason';
  }

  @override
  String get prefsDefaultEditor => '默认编辑器';

  @override
  String get prefsEditorPlain => '纯文本编辑器';

  @override
  String get prefsEditorMarkdown => '实时 Markdown 编辑器';

  @override
  String get prefsThemePreset => '主题配色';

  @override
  String get prefsThemeMode => '主题模式';

  @override
  String get prefsThemeModeSystem => '跟随系统';

  @override
  String get prefsThemeModeLight => '浅色';

  @override
  String get prefsThemeModeDark => '深色';

  @override
  String get prefsLanguage => '语言';

  @override
  String get prefsOfflineMode => '离线模式';

  @override
  String get prefsOfflineModeSubtitle =>
      '启动时跳过远程获取。应用仅从本地缓存渲染——登录和手动云端拉取仍可按需使用。';

  @override
  String get prefsViewTutorial => '查看教程';

  @override
  String get prefsViewTutorialSubtitle => '重新播放快速入门导览。';

  @override
  String get prefsApiBaseUrl => 'API 基础地址';

  @override
  String get prefsApiBaseLockTooltip => '更改 API 基础地址前请先登出。已登录的令牌只对其签发的后端有效。';

  @override
  String get prefsApiBaseLocked => '登录期间已锁定。登出后可更改。';

  @override
  String get prefsApiBaseHelper => '请包含 `/api/v1` 后缀。应用会在缺失时自动追加，但直接粘贴完整地址更稳妥。';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsEditorTitle => '编辑器设置';

  @override
  String get settingsEditorSubtitle => '默认编辑模式、主题配色、主题模式。';

  @override
  String get settingsViewTutorial => '查看教程';

  @override
  String get settingsViewTutorialSubtitle => '重新播放快速入门导览。';

  @override
  String get settingsBackendTitle => '后端设置';

  @override
  String get settingsLocalDataTitle => '本地数据';

  @override
  String get settingsLocalDataSubtitle => '下载或恢复本地存档，重置初始分类。';

  @override
  String get settingsRecycleBinTitle => '回收站';

  @override
  String get settingsDeveloperTitle => '开发者';

  @override
  String get settingsDeveloperSubtitle => '仅管理员操作：恢复远端三门课程的模板目录。';

  @override
  String get settingsPersonalInfoTitle => '个人信息';

  @override
  String get settingsSecurityTitle => '登录与安全';

  @override
  String get settingsApiTitle => 'API 设置';

  @override
  String get settingsImmediateSaveCaption => '每项更改都会立即保存——此菜单无需保存按钮。';

  @override
  String get settingsDefaultEditorMode => '默认编辑模式';

  @override
  String get settingsThemePreset => '主题配色';

  @override
  String get settingsThemeMode => '主题模式';

  @override
  String get settingsPortalPreferences => '门户偏好设置';

  @override
  String get settingsPortalPreferencesSubtitle => '主题配色、主题模式、默认编辑器。';

  @override
  String get settingsConnectedAccounts => '已连接的账户';

  @override
  String get settingsPersonalInfoSubtitle => '头像、用户名、签名、社交链接。';

  @override
  String get settingsSecuritySubtitle => '活动会话、修改邮箱、修改密码、智能体技能。';

  @override
  String get settingsApiSubtitle => 'API 基础地址和 MCP 密钥。';

  @override
  String get settingsManageAccountPreferences => '管理你的账户、偏好设置和本地数据。';

  @override
  String get settingsLocalOnlyPreferences => '登录即可同步到云端，或继续使用下方的仅本地偏好设置。';

  @override
  String get settingsCasdoorLinked => 'Casdoor SSO 已关联。';

  @override
  String get settingsNoThirdPartyLinked => '尚未关联第三方账户。';

  @override
  String settingsBackendOnlineSummary(String url) {
    return '在线。API 地址：$url';
  }

  @override
  String settingsBackendOfflineSummary(String url) {
    return '离线模式已开启。API 地址：$url';
  }

  @override
  String settingsLocalDataSummary(int drafts, int courses) {
    return '此设备上有 $drafts 篇草稿、$courses 门课程。';
  }

  @override
  String settingsRecycleBinSummary(int drafts, int notes) {
    return '$drafts 篇已同步草稿可恢复，$notes 篇云端笔记已移入回收站。';
  }

  @override
  String get settingsSignOut => '退出登录';

  @override
  String get settingsChangeAvatar => '更换头像';

  @override
  String get settingsUsername => '用户名';

  @override
  String get settingsMotto => '签名';

  @override
  String get settingsSocialLink => '社交链接';

  @override
  String get settingsSocialLinkInvalid => '必须是有效网址（https://...）';

  @override
  String get settingsAccountCasdoorNotice =>
      '账户创建、密码修改、邮箱修改和各设备会话管理都在 Casdoor 用户门户中完成。Casdoor 绑定 / 解绑控件位于账户页面。';

  @override
  String get settingsApiBaseLockedTooltip =>
      '登录期间已锁定。退出登录后可切换门户连接的后端。';

  @override
  String get settingsApiBaseTooltip => '将门户指向另一个记粒体后端。';

  @override
  String get settingsEditorApiBaseTooltip =>
      '将编辑器指向另一个记粒体后端。握手探测会在保存前验证 URL。';

  @override
  String get settingsApiBaseApplyCaption =>
      '按 Enter 应用 URL 更改。它会保存在本地，并在登录时同步到个人资料。';

  @override
  String get settingsApiBaseApplyLockedCaption =>
      '按 Enter 应用 URL 更改。它会保存在本地，并在登录时同步到个人资料。登录期间已锁定——退出登录后可切换后端。';

  @override
  String get settingsMcpKeyCaption =>
      'MCP 密钥用于认证后端 Model Context Protocol 桥接。如果怀疑泄露，请轮换它。';

  @override
  String get settingsConnectedAccountsCaption =>
      'Casdoor 代理第三方身份（Google、GitHub 等）——请在 Casdoor 应用的 Providers 标签页中配置。';

  @override
  String get settingsThemeModeMatchSystem => '跟随系统';

  @override
  String get settingsEditorModePickerHelp =>
      '选择新笔记默认打开的编辑模式。仍可在单篇笔记的编辑器工具栏中切换模式。';

  @override
  String get settingsThemePresetPickerHelp => '每个预设使用不同种子色生成 Material 3 配色。';

  @override
  String get settingsThemeModePickerHelp =>
      '跟随系统会使用设备级浅色 / 深色设置。浅色和深色会覆盖系统选择。';

  @override
  String get settingsOfflineModeSubtitleShort => '启动时跳过所有远程获取；完全从本地缓存渲染。';

  @override
  String settingsLocalDataCounts(int drafts, int courses) {
    return '$drafts 篇本地草稿，$courses 门本地课程。';
  }

  @override
  String get settingsDownloadLocalData => '下载本地数据';

  @override
  String get settingsDownloadLocalDataSubtitle => '将草稿、课程、设置和日志导出为 .nchron 存档。';

  @override
  String get settingsRestoreLocalArchive => '从本地存档恢复';

  @override
  String get settingsRestoreLocalArchiveSubtitle =>
      '导入之前导出的 .nchron 存档。确认后会替换现有本地数据。';

  @override
  String get settingsPushLocalCloud => '本地 → 云端';

  @override
  String get settingsPushLocalCloudSubtitle => '将本地草稿和课程上传到你的云端账户。需要登录。';

  @override
  String get settingsPullCloudLocal => '云端 → 本地';

  @override
  String get settingsPullCloudLocalSubtitle => '将云端笔记和课程下载到此设备。';

  @override
  String get settingsClearLocalCache => '清除本地缓存';

  @override
  String get settingsClearLocalCacheSubtitle => '删除缓存的 API 响应，但保留磁盘上的草稿和课程。';

  @override
  String get settingsRemoveLocalData => '移除本地数据';

  @override
  String get settingsRemoveLocalDataSubtitle =>
      '从此设备清除草稿、课程、设置和日志。云端副本不受影响。';

  @override
  String get settingsRestoreTemplateCourses => '恢复模板课程';

  @override
  String get settingsRestoreTemplateCoursesSubtitle =>
      '仅管理员可用。重新种入三门课程模板目录（收件箱 / 示例 / 模板）。';

  @override
  String get settingsRestoreTemplateCoursesCaption =>
      '需要已登录的管理员账户。非管理员会在上方横幅中看到服务器端错误，不会更改任何数据。';

  @override
  String get settingsSyncedLocalDrafts => '已同步的本地草稿';

  @override
  String settingsLocalRecycleCount(int count) {
    return '本地回收站中有 $count 项等待处理。';
  }

  @override
  String get settingsCloudRecycleBin => '云端回收站';

  @override
  String settingsCloudRecycleCount(int count) {
    return '服务器上有 $count 篇软删除笔记。';
  }

  @override
  String get settingsCloudRecycleSignIn => '登录以管理已删除的云端笔记。';

  @override
  String get settingsRecycleBinEmpty => '回收站为空。';

  @override
  String get settingsEmptyRecycleBin => '清空回收站';

  @override
  String get apiKeyTitle => 'API 密钥';

  @override
  String get apiKeyNoKey => '（还没有 API 密钥——点击“生成”创建一个）';

  @override
  String get apiKeyRotate => '轮换';

  @override
  String get apiKeyGenerate => '生成';

  @override
  String get apiKeyCopyNow => '现在复制此密钥——之后不会再次显示：';

  @override
  String get apiKeySavedIt => '我已保存';

  @override
  String get apiKeyCopied => 'API 密钥已复制到剪贴板。';

  @override
  String get apiKeyMcpEndpointCopied => 'MCP 端点已复制到剪贴板。';

  @override
  String apiKeyRotateFailed(String error) {
    return '无法轮换 API 密钥：Portal.Settings/api_key.rotate — $error';
  }

  @override
  String get apiKeyHelp =>
      '在 MCP 客户端（例如 Claude Desktop）中使用此密钥，将 Authorization 请求头设为 "Bearer ntc_<key>"。';

  @override
  String get apiKeyMcpEndpoint => 'MCP 端点：';

  @override
  String get apiKeyCopyMcpEndpoint => '复制 MCP 端点';

  @override
  String get connectedAccountsTitle => '已连接的账户';

  @override
  String get connectedAccountsShadow => '此后端的 Casdoor 处于影子模式；无法关联第三方账户。';

  @override
  String get connectedAccountsManageCasdoor => '管理 Casdoor 账户';

  @override
  String get connectedAccountsUnavailableHelp =>
      '如果无法登录，请联系你的记粒体管理员（Casdoor 后端可能已关闭）。';

  @override
  String get connectedAccountsCasdoorSso => 'Casdoor SSO';

  @override
  String get connectedAccountsLinked => '已关联';

  @override
  String get connectedAccountsNotLinked => '未关联';

  @override
  String get connectedAccountsSwitch => '切换';

  @override
  String get connectedAccountsUnlink => '解绑';

  @override
  String get connectedAccountsLinkCasdoor => '关联 Casdoor';

  @override
  String get debugLogTitle => '调试日志';

  @override
  String get debugCopyLogs => '复制日志';

  @override
  String get debugFilters => '筛选';

  @override
  String get debugAllSources => '全部来源';

  @override
  String get debugNoLogs => '尚未捕获前端日志。';

  @override
  String debugNoEntriesAtLevel(String level) {
    return '没有 $level 及以上级别的条目。';
  }

  @override
  String get logLevelError => '错误';

  @override
  String get logLevelWarning => '警告';

  @override
  String get logLevelInfo => '信息';

  @override
  String get logLevelDebug => '调试';

  @override
  String get storageUsageTitle => '存储用量';

  @override
  String get storageBackend => '后端';

  @override
  String get storageBackendStorage => '后端存储';

  @override
  String get storageLocalDataUsed => '本地数据用量';

  @override
  String get storageBrowserStorage => '浏览器存储';

  @override
  String get storageSpaceLeft => '剩余空间';

  @override
  String get storageNotReported => '此平台未提供';

  @override
  String get storageBreakdown => '明细';

  @override
  String get storageNoLocalData => '尚未存储任何本地数据。';

  @override
  String get storageSuggestions => '建议';

  @override
  String get storageAttachments => '附件';

  @override
  String get storageOffline => '离线';

  @override
  String storageQuotaUsed(String used, String quota) {
    return '已用 $used / $quota';
  }

  @override
  String storageFree(String amount) {
    return '剩余 $amount';
  }

  @override
  String storageSuggestQuota(int percent) {
    return '你已使用本站点在此浏览器中 $percent% 的存储空间。可清理缓存，或导出并删除旧的本地笔记来释放空间。';
  }

  @override
  String storageSuggestAttachments(String size) {
    return '附件占用了 $size。登录并推送到云端后，可清除本地数据以回收空间，或先导出一份备份。';
  }

  @override
  String storageSuggestLocalTotal(String size) {
    return '本地数据为 $size。建议导出一份备份，并清理已同步到云端的数据。';
  }

  @override
  String get installBannerAtRisk =>
      '你的笔记仅保存在此浏览器中，约一周不活动后可能被清除。请登录以备份，或将记粒体添加到主屏幕以获得持久存储。';

  @override
  String get installBannerTip =>
      '提示：将记粒体添加到主屏幕，可获得类似应用的体验和不会被浏览器清除的存储。在 iPhone 上：分享 → 添加到主屏幕。';

  @override
  String whatsNewTitle(String appTitle) {
    return '$appTitle 新功能';
  }

  @override
  String get authAccount => '账户';

  @override
  String get authDescPrimary =>
      '通过记粒体 SSO 登录。账户创建和密码重置由 Casdoor 端处理；可使用下方链接注册，若需要重置密码请联系管理员。';

  @override
  String get authDescFallback =>
      '使用你现有的账户登录。账户创建和密码重置已迁移到 Casdoor SSO；如无法登录请联系管理员。';

  @override
  String get authContinueCasdoor => '使用 Casdoor SSO 继续';

  @override
  String get authSignUpCasdoor => '还没有账户？通过 Casdoor 注册';

  @override
  String get authHideFallback => '隐藏邮箱 / 密码备用登录';

  @override
  String get authUseEmailPassword => '改用邮箱 / 密码登录';

  @override
  String get authLogin => '登录';

  @override
  String get authForgotPassword => '忘记密码？请联系管理员重置。对于已迁移的账户，自助密码重置已迁移到 Casdoor。';

  @override
  String get authEmailOrUsername => '邮箱或用户名';

  @override
  String get authEmailLabel => '邮箱';

  @override
  String get authPasswordLabel => '密码';

  @override
  String authSigningInTo(String host) {
    return '正在登录到 $host';
  }

  @override
  String get authWorking => '处理中……';

  @override
  String get authPhaseSending => '正在向后端发送请求';

  @override
  String get authPhaseWaiting => '正在等待后端响应';

  @override
  String get authPhaseApplying => '正在应用响应';

  @override
  String get linkTitle => '关联 Casdoor 身份';

  @override
  String get linkSignedInAs => 'Casdoor 已将你登录为：';

  @override
  String get linkChooseIntro => '此 Casdoor 身份尚未关联到记粒体账户。请选择如何继续：';

  @override
  String get linkBindButton => '绑定到我已有的账户';

  @override
  String get linkBindDesc =>
      '你已经有一个记粒体账户。使用你原有的用户名/邮箱 + 密码登录一次，即可将此 Casdoor 身份关联到它。关联后，今后的 Casdoor 登录都会进入同一个账户。';

  @override
  String get linkCreateButton => '创建新的记粒体账户';

  @override
  String get linkCreateDesc =>
      '没有已有的记粒体账户。设置一个密码——将使用上方显示的用户名和邮箱创建你的新账户。当 Casdoor 不可用时，同一密码可用于邮箱/密码备用登录。';

  @override
  String get linkBindPaneDesc =>
      '请使用你已有的记粒体账户登录一次，以便我们将其关联到此 Casdoor 身份。用户名或邮箱 + 你之前设置的密码。';

  @override
  String get linkUsernameOrEmailLabel => '记粒体用户名或邮箱';

  @override
  String get linkPasswordLabel => '记粒体密码';

  @override
  String get linkCreatePaneDesc =>
      '为你的新记粒体账户设置一个密码。Casdoor 仍负责 SSO；此密码用于旧的邮箱/密码备用登录（当 auth.trance-0.com 不可用时）。';

  @override
  String get linkNewPasswordLabel => '新密码';

  @override
  String get linkConfirmPasswordLabel => '确认密码';

  @override
  String get linkBindAction => '绑定账户';

  @override
  String get linkCreateAction => '创建账户';

  @override
  String get linkErrBindRequired => '绑定需要同时填写用户名/邮箱和密码。';

  @override
  String get linkErrPasswordShort => '请设置至少 8 个字符的密码。';

  @override
  String get linkErrPasswordMismatch => '两次输入的密码不一致。请在两个字段中输入相同的密码。';

  @override
  String get clearAllLocalDataTile => '清除所有本地数据';

  @override
  String get clearAllLocalDataTileSubtitle => '从此设备清除草稿、分类、设置和日志。云端副本不受影响。';

  @override
  String get clearAllLocalDataTitle => '清除所有本地数据？';

  @override
  String get clearAllLocalDataMessage => '这将从此设备移除每一篇本地草稿和本地分类。已同步到云端的笔记不受影响。';

  @override
  String get clearAllLocalDataConfirm => '全部清除';

  @override
  String get tourEditorWelcomeTitle => '欢迎使用记粒体编辑器';

  @override
  String get tourEditorWelcomeBody => '撰写支持离线的 Markdown 笔记，登录后即可同步到云端。';

  @override
  String get tourEditorCategoriesTitle => '用分类整理';

  @override
  String get tourEditorCategoriesBody => '在侧边栏中将笔记归入分类。没有分类的笔记会留在收件箱中。';

  @override
  String get tourEditorSyncTitle => '随身在每台设备';

  @override
  String get tourEditorSyncBody => '笔记会在你输入时保存到此设备。登录即可备份并在多台设备间同步。';

  @override
  String get tourEditorToolsTitle => '设置与工具';

  @override
  String get tourEditorToolsBody => '主题、同步、导入/导出和调试日志都在设置中。在手机上，从左上角打开菜单。';

  @override
  String get tourPlannerWelcomeTitle => '欢迎使用记粒体规划器';

  @override
  String get tourPlannerWelcomeBody => '在一个地方追踪课程、截止日期和你的学习活动。';

  @override
  String get tourPlannerCoursesTitle => '课程与截止日期';

  @override
  String get tourPlannerCoursesBody => '添加课程和规划事件；即将到来的截止日期会显示在你的仪表盘上。';

  @override
  String get tourPlannerAnywhereTitle => '随处规划';

  @override
  String get tourPlannerAnywhereBody => '支持离线使用。登录即可在多台设备间同步你的计划。';

  @override
  String get tourPlannerToolsTitle => '设置与工具';

  @override
  String get tourPlannerToolsBody => '主题、同步和工具都在设置中。在手机上，从左上角打开菜单。';

  @override
  String get tourPortalWelcomeTitle => '欢迎使用记粒体';

  @override
  String get tourPortalWelcomeBody => '你的笔记、规划和公开课程中心。';

  @override
  String get tourPortalExploreTitle => '探索公开笔记';

  @override
  String get tourPortalExploreBody => '直接从首页浏览公开课程和笔记。';

  @override
  String get tourPortalAppsTitle => '打开各应用';

  @override
  String get tourPortalAppsBody => '随时进入编辑器或规划器。登录即可同步你自己的内容。';

  @override
  String get errorNetwork => '无法连接到服务器。请检查你的网络连接后重试。';

  @override
  String get errorTimeout => '服务器响应超时。请重试。';

  @override
  String get errorServer => '服务器出错了。请稍后重试。';

  @override
  String get versionUpdateAvailable => '有新版本可用。刷新以更新。';

  @override
  String get versionDeploying => '新版本正在发布——部分功能可能暂时不可用。';

  @override
  String get versionUnsupported => '此应用版本已不再受支持。请刷新以更新。';

  @override
  String get versionRefresh => '刷新';

  @override
  String get errorWorkOffline => '离线使用';

  @override
  String frontWelcomeBack(String name) {
    return '欢迎回来，$name';
  }

  @override
  String get frontWelcomeGuest => '欢迎使用记粒体';

  @override
  String get frontGreetingGuest => '访客';

  @override
  String get frontHeroAuth => '一览你的笔记、课程和日程。在下方选择一门课程，或进入学习/规划工作区。';

  @override
  String get frontHeroAnon => '探索公开课程和笔记，或登录以解锁你的学习仪表盘和活动热力图。';

  @override
  String get frontRecentCourses => '最近的公开课程';

  @override
  String get frontNoCourses => '还没有公开课程。';

  @override
  String get frontActivityHeatmap => '活动热力图';

  @override
  String get frontHeatmapLegend => '过往活动（蓝色）与即将到来的规划负载（青色）。';

  @override
  String get frontRecentNotes => '最近的公开笔记';

  @override
  String get courseCreateLocal => '创建本地课程';

  @override
  String get courseTitleLabel => '课程标题';

  @override
  String get courseDescriptionLabel => '描述';

  @override
  String get courseSyncLocalData => '同步本地数据';

  @override
  String courseBackTo(String title) {
    return '返回到 $title';
  }

  @override
  String get courseModuleDiscussion => '模块讨论';

  @override
  String get courseBackToResults => '返回课程结果';

  @override
  String get courseSubscribe => '订阅';

  @override
  String get courseNoModules => '此课程尚未映射任何模块。';

  @override
  String get courseDiscussion => '课程讨论';

  @override
  String get courseListTitle => '课程列表';

  @override
  String get courseLoadMore => '加载更多';

  @override
  String get activitySignInPrompt => '登录以查看你的截止日期、已同步的学习时段和每周日历。';

  @override
  String get activityNoWeekEvents => '当前视图暂无每周事件。';

  @override
  String get activityThisWeek => '本周';

  @override
  String get activityPrevWeek => '上一周';

  @override
  String get activityNextWeek => '下一周';

  @override
  String get activityCreateEvent => '创建事件';

  @override
  String get activityImportIcal => '导入 iCal';

  @override
  String get activitySubscribeCalendar => '订阅日历';

  @override
  String get activityFabHint => '点击创建新事件。长按或右键点击可导入 iCal 或订阅。';

  @override
  String get activityNoDeadlines => '还没有有效的截止日期。点击添加按钮创建一个。';

  @override
  String get activityNoUrgent => '当前视图中没有紧急的截止日期。';

  @override
  String get activityWeekCalendar => '周历';

  @override
  String get activityNewEvent => '新建事件';

  @override
  String get activityEventTitle => '事件标题';

  @override
  String get activityDifficulty => '难度';

  @override
  String activityWeightN(int n) {
    return '权重 $n';
  }

  @override
  String get activitySubscribeToCalendar => '订阅日历';

  @override
  String get activityIcalUrl => 'iCal 网址';

  @override
  String get activitySubscribedCalendar => '已订阅的日历';

  @override
  String get mcpSkillCopied => 'skill.md 已复制到剪贴板。';

  @override
  String get mcpSkillTitle => '智能体技能（skill.md）';

  @override
  String get mcpSkillDescription =>
      '供 MCP 连接的智能体使用的个人操作手册。可在这里说明从哪里拉取笔记（例如 notenextra.trance-0.com 等外部站点）、如何格式化导入、导出哪些文件，以及发布到哪里。它会原样作为 MCP initialize 响应中的 `instructions` 字段发送。';

  @override
  String get mcpSkillHint =>
      '# 导入\n- 每天从 notenextra.trance-0.com 拉取一次笔记……\n\n# 导出\n- 以 YAML+Markdown 镜像到 GitHub Gist。\n\n# 格式\n- 用 \$...\$ 包裹数学公式。用 #deadline 标记截止日期。';

  @override
  String get mcpSkillUnsavedChanges => '有未保存的更改';

  @override
  String get githubSyncTitle => '实验功能 — GitHub 同步';

  @override
  String get githubSyncDescription =>
      '将你的完整账户（个人资料、设置、MCP 技能、课程、笔记、自定义元数据、规划事件）推送到你拥有的 GitHub 仓库，以便服务器数据丢失时恢复。我们托管的静态资源（头像、附件、封面图片）会以 URL 引用，不会提交到仓库。完整流程见 docs/integrations/github-sync.md。';

  @override
  String get githubSyncInstall => '安装记粒体 GitHub App';

  @override
  String get githubSyncInstallHelp =>
      '批准安装后，GitHub 会重定向回这里，我们会自动保存你的安装 ID。应用会保持安装，直到你从 GitHub 设置中移除它。';

  @override
  String get githubSyncInstalled => 'GitHub App 已安装。';

  @override
  String githubSyncInstalledOn(String account) {
    return 'GitHub App 已安装到 @$account。';
  }

  @override
  String get githubSyncNoRepos =>
      '此安装看不到任何仓库。请打开 GitHub 设置 → Applications → 记粒体 data sync，并授予仓库访问权限。';

  @override
  String get githubSyncTargetRepo => '同步目标仓库';

  @override
  String get githubSyncIncludeAssets => '包含资源文件';

  @override
  String get githubSyncIncludeAssetsOn =>
      '头像、封面图片和附件会内联到 assets/ 下。受单文件 50 MB、单次推送 200 MB 上限限制。';

  @override
  String get githubSyncIncludeAssetsOff =>
      '静态资源仅保留 URL 引用。推送更快，但全新服务器无法恢复这些文件内容。';

  @override
  String get githubSyncPushNow => '立即推送';

  @override
  String get githubSyncDisconnect => '断开连接';

  @override
  String githubSyncLastPush(String sha) {
    return '上次推送：$sha';
  }

  @override
  String githubSyncLastPushAt(String time) {
    return '上次推送时间：$time。';
  }

  @override
  String get githubSyncSignIn => '登录以启用 GitHub 同步。';

  @override
  String githubSyncLoadStatusFailed(String error) {
    return '无法加载 GitHub 同步状态：Frontend.GithubSync/status — $error';
  }

  @override
  String githubSyncSelectRepositoryFailed(String error) {
    return '无法选择仓库：Frontend.GithubSync/repository.select — $error';
  }

  @override
  String githubSyncPushFailed(String error) {
    return 'GitHub 同步推送失败：Frontend.GithubSync/push — $error';
  }

  @override
  String githubSyncPushed(String sha) {
    return '已推送到 GitHub：Frontend.GithubSync/push — 提交 $sha。';
  }

  @override
  String githubSyncDisconnectFailed(String error) {
    return '无法断开 GitHub 同步：Frontend.GithubSync/disconnect — $error';
  }

  @override
  String get githubSyncInstallMissingUrl =>
      '无法安装 GitHub App：Frontend.GithubSync/install — 未配置 install_url。';

  @override
  String get githubSyncInstallInvalidUrl =>
      '无法安装 GitHub App：Frontend.GithubSync/install — install_url 不是有效的 http(s) URL。';

  @override
  String githubSyncInstallCompleteFailed(String error) {
    return '无法完成 GitHub App 安装：Frontend.GithubSync/install.callback — $error';
  }

  @override
  String get githubSyncInstallUrlMissingHelp =>
      '运维提示：此后端未配置 GITHUB_DATA_SYNC_APP_INSTALL_URL。请参阅 docs/integrations/github-sync.md 中的环境变量约定。';

  @override
  String get courseObjectives => '学习目标';

  @override
  String get courseAssignments => '作业';

  @override
  String get courseModule => '模块';

  @override
  String get courseModulesHeader => '模块';

  @override
  String get courseModuleNoNotes => '此模块暂无公开笔记。';

  @override
  String get courseNoDiscussion => '此课程暂无公开讨论笔记。';

  @override
  String courseNoteCount(int count) {
    return '$count 篇笔记';
  }
}
