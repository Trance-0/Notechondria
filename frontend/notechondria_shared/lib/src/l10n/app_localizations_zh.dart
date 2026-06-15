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
