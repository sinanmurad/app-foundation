// Şablonu yeni bir uygulamaya dönüştürür.
//
// Kullanım (proje kökünde):
//   dart run tool/rename.dart --name "MyApp" --bundle com.yourcompany.myapp
//   dart run tool/rename.dart --name "MyApp" --bundle com.yourcompany.myapp --team ABCDE12345
//
// Yaptıkları:
//   - com.example.starter → yeni bundle ID (iOS, Share Extension, App Group,
//     Android applicationId/namespace, Kotlin package, Codemagic)
//   - "Starter App" → yeni uygulama adı (iOS/Android görünen ad, ARB appTitle)
//   - starterapp URL scheme → bundle'ın son parçası
//   - pubspec.yaml name → bundle'ın son parçası
//   - Kotlin klasörünü yeni package yoluna taşır
//   - --team verilirse Apple Team ID'yi değiştirir
//
// Script idempotent değildir: şablon bir kez yeniden adlandırılır.
import 'dart:io';

const String kOldBundle = 'com.example.starter';
const String kOldName = 'Starter App';
const String kOldScheme = 'starterapp';
const String kOldTeam = 'ABCDE12345';
const String kOldPackageName = 'app_starter';

const Set<String> kTextExtensions = {
  '.pbxproj',
  '.plist',
  '.swift',
  '.entitlements',
  '.kts',
  '.xml',
  '.kt',
  '.yaml',
  '.rb',
  '.arb',
  '.xcscheme',
};

const Set<String> kSkipDirs = {
  '.git',
  '.dart_tool',
  'build',
  'Pods',
  '.symlinks',
  'tool',
};

void main(List<String> args) {
  final options = _parseArgs(args);
  final name = options['name'];
  final bundle = options['bundle'];
  final team = options['team'];

  if (name == null || bundle == null) {
    _fail('Kullanım: dart run tool/rename.dart --name "Uygulama Adı" '
        '--bundle com.sirket.uygulama [--team APPLETEAMID]');
  }
  final bundleRegex = RegExp(r'^[a-z][a-z0-9]*(\.[a-z][a-z0-9_]*)+$');
  if (!bundleRegex.hasMatch(bundle)) {
    _fail('Geçersiz bundle ID: "$bundle". Örnek: com.yourcompany.myapp '
        '(küçük harf, rakam, nokta; tire kullanma — Android kabul etmez).');
  }
  if (team != null && !RegExp(r'^[A-Z0-9]{10}$').hasMatch(team)) {
    _fail('Geçersiz Apple Team ID: "$team" (10 karakter, büyük harf/rakam).');
  }

  final root = Directory.current;
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    _fail('Bu scripti proje kökünde çalıştır (pubspec.yaml bulunamadı).');
  }

  final pubspec = File('${root.path}/pubspec.yaml');
  if (!pubspec.readAsStringSync().contains('name: $kOldPackageName')) {
    _fail('Şablon zaten yeniden adlandırılmış görünüyor (pubspec name '
        '"$kOldPackageName" değil). İşlem iptal edildi.');
  }

  final lastSegment = bundle.split('.').last;
  final scheme = lastSegment.replaceAll('_', '').toLowerCase();
  final packageName = lastSegment.toLowerCase();

  final replacements = <String, String>{
    kOldBundle: bundle,
    kOldName: name,
    kOldScheme: scheme,
    if (team != null) kOldTeam: team,
  };

  var changedFiles = 0;
  for (final entity in root.listSync(recursive: false)) {
    changedFiles += _walk(entity, replacements);
  }

  // pubspec.yaml: paket adı
  final pubspecText = pubspec.readAsStringSync();
  pubspec.writeAsStringSync(
    pubspecText.replaceFirst('name: $kOldPackageName', 'name: $packageName'),
  );
  changedFiles++;

  // Kotlin klasörünü taşı
  final kotlinRoot = '${root.path}/android/app/src/main/kotlin';
  final oldKotlinDir = Directory('$kotlinRoot/${kOldBundle.replaceAll('.', '/')}');
  final newKotlinDir = Directory('$kotlinRoot/${bundle.replaceAll('.', '/')}');
  if (oldKotlinDir.existsSync()) {
    newKotlinDir.createSync(recursive: true);
    for (final file in oldKotlinDir.listSync().whereType<File>()) {
      final fileName = file.uri.pathSegments.last;
      file.renameSync('${newKotlinDir.path}/$fileName');
    }
    _deleteEmptyParents(oldKotlinDir, Directory(kotlinRoot));
  }

  stdout.writeln('✅ Tamamlandı: $changedFiles dosya güncellendi.');
  stdout.writeln('   Uygulama adı : $name');
  stdout.writeln('   Bundle ID    : $bundle');
  stdout.writeln('   App Group    : group.$bundle');
  stdout.writeln('   URL scheme   : $scheme');
  stdout.writeln('');
  stdout.writeln('Sıradaki adımlar (README > Yeni uygulama kontrol listesi):');
  stdout.writeln('  1. flutter pub get');
  stdout.writeln('  2. App Store Connect: $bundle ve $bundle.ShareExtension '
      'kaydet, ikisine de group.$bundle App Group\'unu ekle');
  stdout.writeln('  3. Uygulama ikonlarını değiştir');
  stdout.writeln('  4. dart run tool/preflight.dart && flutter analyze');
}

int _walk(FileSystemEntity entity, Map<String, String> replacements) {
  final segments = entity.uri.pathSegments.where((s) => s.isNotEmpty);
  final name = segments.isEmpty ? '' : segments.last;

  if (entity is Directory) {
    if (kSkipDirs.contains(name)) return 0;
    var count = 0;
    for (final child in entity.listSync(recursive: false)) {
      count += _walk(child, replacements);
    }
    return count;
  }

  if (entity is! File) return 0;
  final dot = name.lastIndexOf('.');
  if (dot == -1 || !kTextExtensions.contains(name.substring(dot))) return 0;

  final original = entity.readAsStringSync();
  var updated = original;
  replacements.forEach((from, to) {
    updated = updated.replaceAll(from, to);
  });
  if (updated == original) return 0;
  entity.writeAsStringSync(updated);
  return 1;
}

void _deleteEmptyParents(Directory dir, Directory stopAt) {
  var current = dir;
  while (current.path != stopAt.path &&
      current.existsSync() &&
      current.listSync().isEmpty) {
    current.deleteSync();
    current = current.parent;
  }
}

Map<String, String> _parseArgs(List<String> args) {
  final result = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg.startsWith('--') && i + 1 < args.length) {
      result[arg.substring(2)] = args[i + 1];
      i++;
    }
  }
  return result;
}

Never _fail(String message) {
  stderr.writeln('❌ $message');
  exit(1);
}
