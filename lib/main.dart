import 'package:flutter/material.dart';
import 'package:device_apps/device_apps.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data'; // Uint8List
import 'dart:io';        // File, Platform
import 'package:csv/csv.dart'; // CSV
import 'dart:convert';     // Required for utf8 encoding/decoding
// import 'package:path_provider/path_provider.dart'; // Not directly used now
import 'package:file_picker/file_picker.dart';     // File Picker
import 'package:permission_handler/permission_handler.dart'; // For openAppSettings

// ソート順序の定義
enum SortOrder { nameAsc, packageNameAsc, importedFirst, importedLast }

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Installed Apps Lister',
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      home: const InstalledAppsScreen(),
    );
  }
}

class InstalledAppsScreen extends StatefulWidget {
  const InstalledAppsScreen({super.key});

  @override
  State<InstalledAppsScreen> createState() => _InstalledAppsScreenState();
}

class _InstalledAppsScreenState extends State<InstalledAppsScreen> {
  List<Application> _originalApps = []; // ソート前のオリジナルリスト
  List<Application> _displayedApps = []; // 表示用のリスト (ソート後)
  bool _isLoading = true;
  String? _errorMessage;

  Set<String> _lastImportedPackageNames = {}; // 最後にインポートされたパッケージ名
  SortOrder _sortOrder = SortOrder.nameAsc;    // 現在のソート順 (デフォルトは名前昇順)

  @override
  void initState() {
    super.initState();
    _checkAndLoadApps();
  }

  // アプリリストのロードと初期ソート
  Future<void> _checkAndLoadApps() async {
    await _loadInstalledApps();
  }

  // インストール済みアプリの情報を取得
  Future<void> _loadInstalledApps() async {
    if (mounted) { setState(() { _originalApps = []; _displayedApps = []; _isLoading = true; _errorMessage = null; }); }
    try {
      List<Application> apps = await DeviceApps.getInstalledApplications( includeAppIcons: true, includeSystemApps: true, onlyAppsWithLaunchIntent: true );
      _originalApps = apps;
      _sortApps();
    } catch (e, stacktrace) {
      print("Error loading apps: $e"); print(stacktrace);
      if (mounted) { setState(() { _errorMessage = "アプリ一覧の取得に失敗しました: $e"; _isLoading = false; });}
    }
  }

  // アプリリストをソートする関数
  void _sortApps() {
    List<Application> sortedList = List.from(_originalApps);
    switch (_sortOrder) {
      case SortOrder.nameAsc: sortedList.sort((a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase())); break;
      case SortOrder.packageNameAsc: sortedList.sort((a, b) => a.packageName.toLowerCase().compareTo(b.packageName.toLowerCase())); break;
      case SortOrder.importedFirst: sortedList.sort((a, b) { final aImported = _lastImportedPackageNames.contains(a.packageName); final bImported = _lastImportedPackageNames.contains(b.packageName); if (aImported && !bImported) return -1; if (!aImported && bImported) return 1; return a.appName.toLowerCase().compareTo(b.appName.toLowerCase()); }); break;
      case SortOrder.importedLast: sortedList.sort((a, b) { final aImported = _lastImportedPackageNames.contains(a.packageName); final bImported = _lastImportedPackageNames.contains(b.packageName); if (aImported && !bImported) return 1; if (!aImported && bImported) return -1; return a.appName.toLowerCase().compareTo(b.appName.toLowerCase()); }); break;
    }
    if (mounted) { setState(() { _displayedApps = sortedList; _isLoading = false; });}
    print("Apps sorted by: $_sortOrder");
  }

  // Google Play ストアのURLを開く
  Future<void> _launchPlayStore(String bundleId) async {
    final Uri url = Uri.parse('https://play.google.com/store/apps/details?id=$bundleId');
    try {
      final bool launched = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!launched && mounted) { _showSnackBar('Playストアを開けませんでした: $url'); }
    } catch (e) { _showSnackBar('Playストアを開けませんでした: $e'); print('Could not launch $url: $e'); }
  }

  // SnackBar表示用のヘルパー関数
  void _showSnackBar(String message) {
    if (mounted) { ScaffoldMessenger.of(context).hideCurrentSnackBar(); ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text(message)),); }
  }

  // --- CSVエクスポート機能 (変更なし) ---
  Future<void> _exportToCsv() async {
    if (_originalApps.isEmpty) { _showSnackBar('エクスポートするアプリがありません。'); return; }
    List<List<dynamic>> rows = []; rows.add(['AppName', 'PackageName', 'VersionName', 'VersionCode']);
    for (var app in _originalApps) { rows.add([ app.appName, app.packageName, app.versionName ?? '', app.versionCode ]);}
    String csvData = const ListToCsvConverter().convert(rows); Uint8List csvBytes = utf8.encode(csvData);
    try {
      print("Calling FilePicker.platform.saveFile with bytes...");
      String? outputFile = await FilePicker.platform.saveFile( dialogTitle: 'CSVファイルを保存', fileName: 'installed_apps_${DateTime.now().toIso8601String()}.csv', bytes: csvBytes,);
      print("FilePicker.platform.saveFile result: $outputFile");
      if (outputFile != null) { _showSnackBar('CSVファイルが保存されました。'); print("CSV data successfully processed by saveFile.");
      } else { _showSnackBar('CSVエクスポートがキャンセルされました、または失敗しました。'); print("CSV export cancelled by user or failed (saveFile returned null)."); }
    } catch (e, stacktrace) { print("Error exporting CSV: $e"); print(stacktrace); _showSnackBar('CSVエクスポートに失敗しました: ${e.toString()}'); }
  }


  // --- CSVインポート機能 (変更なし) ---
  Future<void> _importFromCsv() async {
    try {
      print("Calling FilePicker.platform.pickFiles...");
      FilePickerResult? result = await FilePicker.platform.pickFiles( type: FileType.custom, allowedExtensions: ['csv'], withData: true,);
      print("FilePicker.platform.pickFiles result received.");
      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!; final fileName = result.files.single.name; print("Attempting to read CSV from picked file: $fileName");
        final csvString = utf8.decode(fileBytes); print("CSV file bytes converted to string successfully.");
        List<List<dynamic>> csvTable = const CsvToListConverter().convert(csvString); print("CSV data converted to list. Row count: ${csvTable.length}");
        if (csvTable.isNotEmpty) {
          final Set<String> installedPackageNames = _originalApps.map((app) => app.packageName).toSet(); List<Map<String, dynamic>> importedAppsForDialog = []; Set<String> currentImportedSet = {};
          List<dynamic> header = csvTable[0]; int appNameIndex = header.indexWhere((h) => h.toString().toLowerCase() == 'appname'); int packageNameIndex = header.indexWhere((h) => h.toString().toLowerCase() == 'packagename');
          if (appNameIndex == -1 || packageNameIndex == -1) { _showSnackBar("CSVファイルに 'AppName' または 'PackageName' の列が見つかりません。"); return;}
          for (int i = 1; i < csvTable.length; i++) {
            final row = csvTable[i];
            if (row.length > appNameIndex && row.length > packageNameIndex) {
              final String importedPackageName = row[packageNameIndex]?.toString() ?? 'IDなし';
              if (importedPackageName != 'IDなし') { final bool isInstalled = installedPackageNames.contains(importedPackageName); currentImportedSet.add(importedPackageName); importedAppsForDialog.add({ 'name': row[appNameIndex]?.toString() ?? '名前なし', 'id': importedPackageName, 'isInstalled': isInstalled,}); }
            }
          }
          if (importedAppsForDialog.isEmpty) { _showSnackBar('CSVファイルに有効なデータ行が見つかりませんでした。'); return;}
          if (mounted) { setState(() { _lastImportedPackageNames = currentImportedSet; }); _sortApps(); }
          if (mounted) { showDialog( context: context, builder: (context) => AlertDialog( title: Text('インポート結果 (${importedAppsForDialog.length}件)'), content: SizedBox( width: double.maxFinite, height: MediaQuery.of(context).size.height * 0.6, child: ListView.builder( shrinkWrap: true, itemCount: importedAppsForDialog.length, itemBuilder: (context, index) { final item = importedAppsForDialog[index]; final bool installed = item['isInstalled'] as bool; return ListTile( leading: Icon( installed ? Icons.check_circle : Icons.help_outline, color: installed ? Colors.green : Colors.grey,), title: Text(item['name']!), subtitle: Text(item['id']!), trailing: Text( installed ? "(端末内にあり)" : "(端末内になし)", style: TextStyle( fontSize: 11, color: installed ? Colors.green : Colors.grey, fontStyle: FontStyle.italic,),), onTap: () { if (item['id'] != 'IDなし') { _launchPlayStore(item['id']!);}},);},),), actions: [ TextButton( onPressed: () => Navigator.of(context).pop(), child: const Text('閉じる'),),],),); }
        } else { _showSnackBar('CSVファイルが空か、ヘッダー行のみです。');}
      } else { _showSnackBar('CSVインポートがキャンセルされました、またはファイルデータが取得できませんでした。');}
    } catch (e, stacktrace) { print("Error importing CSV: $e"); print(stacktrace); _showSnackBar('CSVインポートに失敗しました: ${e.toString()}');}
  }

  // --- 文字列短縮ヘルパー関数 (変更なし) ---
  String _truncateString(String? text, int maxLength) {
    // (変更なし)
    if (text == null || text.isEmpty) { return ""; }
    if (text.length <= maxLength) { return text; }
    return '${text.substring(0, maxLength)}...';
  }

  // --- アプリ設定画面を開くための関数 (変更なし、未使用) ---
  Future<bool> _requestStoragePermission() async {
    // (変更なし、未使用)
    if (!Platform.isAndroid) { return true; } Permission targetPermission = Permission.storage; print("--- Requesting Storage Permission (Legacy Check - Unused) ---"); var status = await targetPermission.status; print("Initial permission status for $targetPermission: $status"); if (status.isPermanentlyDenied) { print("Permission is permanently denied. Prompting to open settings."); if (mounted) { showDialog( context: context, builder: (context) => AlertDialog( title: const Text('権限が必要です'), content: const Text('ファイルのエクスポート/インポートにはストレージへのアクセス権限が必要です。アプリ設定画面から手動で権限を許可してください。'), actions: [ TextButton( onPressed: () => Navigator.of(context).pop(), child: const Text('キャンセル'),), TextButton( onPressed: () { print("Opening app settings..."); openAppSettings(); Navigator.of(context).pop(); }, child: const Text('設定を開く'),), ],),); } return false; } if (!status.isGranted) { print("Permission not granted. Status: $status"); _showSnackBar('ストレージへのアクセス権限がありません。設定画面から許可してください。'); return false; } print("Permission $targetPermission already granted."); return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('インストール済みアプリ一覧'),
        actions: [
          PopupMenuButton<SortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: "並び替え",
            onSelected: (SortOrder result) {
              if (_sortOrder != result) {
                setState(() { _sortOrder = result; });
                _sortApps();
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<SortOrder>>[
              const PopupMenuItem<SortOrder>(
                value: SortOrder.nameAsc,
                child: Text('名前順 (昇順)'),
              ),
              const PopupMenuItem<SortOrder>(
                value: SortOrder.packageNameAsc,
                child: Text('パッケージ名順 (昇順)'),
              ),
              const PopupMenuDivider(),
              // ★★★ ここのテキストラベルを変更 ★★★
              const PopupMenuItem<SortOrder>(
                value: SortOrder.importedFirst,
                child: Text('端末にあるアプリから表示'), // 新しい表示名
              ),
              // ★★★ ここのテキストラベルを変更 ★★★
              const PopupMenuItem<SortOrder>(
                value: SortOrder.importedLast,
                child: Text('端末にないアプリから表示'), // 新しい表示名
              ),
            ],
          ),
          IconButton( icon: const Icon(Icons.file_upload), tooltip: 'CSVからインポート', onPressed: _importFromCsv,),
          IconButton( icon: const Icon(Icons.file_download), tooltip: 'CSVへエクスポート', onPressed: _displayedApps.isEmpty ? null : _exportToCsv,),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton( onPressed: _checkAndLoadApps, tooltip: 'リストを更新', child: const Icon(Icons.refresh),),
    );
  }

  Widget _buildBody() {
    // (変更なし)
    if (_isLoading) { return const Center(child: CircularProgressIndicator()); }
    if (_errorMessage != null) { return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ const Icon(Icons.error_outline, color: Colors.red, size: 48), const SizedBox(height: 16), Text( _errorMessage!, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.red), textAlign: TextAlign.center, ), const SizedBox(height: 24), ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text("再試行"), onPressed: _checkAndLoadApps,),],),),); }
    if (_displayedApps.isEmpty) { return const Center(child: Text('アプリが見つかりませんでした。')); }

    return ListView.builder(
      itemCount: _displayedApps.length,
      itemBuilder: (context, index) {
        Application app = _displayedApps[index];
        ImageProvider? iconImageProvider;
        Uint8List? iconData;
        if (app is ApplicationWithIcon) {
          if (app.icon is Uint8List) {
            iconData = app.icon as Uint8List;
            if (iconData.isNotEmpty) { iconImageProvider = MemoryImage(iconData); }
          }
        }
        final bool wasImported = _lastImportedPackageNames.contains(app.packageName);
        return ListTile(
          tileColor: wasImported ? Colors.teal.withOpacity(0.1) : null,
          leading: CircleAvatar(
            backgroundImage: iconImageProvider,
            backgroundColor: iconImageProvider == null ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
            child: iconImageProvider == null ? const Icon(Icons.apps) : null,
          ),
          title: Text(app.appName),
          subtitle: Text(app.packageName),
          trailing: Text( // バージョン名表示 (短縮適用済み)
            _truncateString(app.versionName, 20),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: const TextStyle(fontSize: 12),
          ),
          onTap: () { _launchPlayStore(app.packageName); },
          onLongPress: wasImported ? () { _showSnackBar('${app.appName} は最後にインポートしたリストに含まれています。'); } : null,
        );
      },
    );
  }
} // End of _InstalledAppsScreenState