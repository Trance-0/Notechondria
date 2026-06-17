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
}
