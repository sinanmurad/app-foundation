// Build öncesi kontrol — "4 dil senkron" kuralının otomatik hali.
//
// Kullanım (proje kökünde):
//   dart run tool/preflight.dart            → ARB hatası varsa çıkış kodu 1
//   dart run tool/preflight.dart --strict   → hardcoded string de hata sayılır
//
// Ardından: flutter analyze  (sıfır hata olmalı)
//
// Kontroller:
//   1. ARB eşitliği: tüm dillerde app_en.arb ile aynı anahtarlar, boş değer yok
//   2. Hardcoded string taraması: lib/ altında Text('...'), labelText: '...'
//      gibi çevrilmemiş UI metinleri
//   3. Şablon yer tutucusu (com.example.starter) hâlâ duruyor mu
import 'dart:convert';
import 'dart:io';

const String kArbDir = 'lib/l10n';
const String kTemplateArb = 'app_en.arb';

void main(List<String> args) {
  final strict = args.contains('--strict');
  var errors = 0;
  var warnings = 0;

  // ---------------------------------------------------------------- 1. ARB
  stdout.writeln('▶ ARB anahtar eşitliği');
  final arbFiles = Directory(kArbDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.arb'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final template = arbFiles.where((f) => f.path.endsWith(kTemplateArb));
  if (template.isEmpty) {
    stderr.writeln('  ❌ $kArbDir/$kTemplateArb bulunamadı');
    exit(1);
  }
  final templateKeys = _messageKeys(template.first);

  for (final file in arbFiles) {
    final name = file.uri.pathSegments.last;
    final data = _readArb(file);
    final keys = _messageKeys(file);
    final missing = templateKeys.difference(keys);
    final extra = keys.difference(templateKeys);
    final empty = keys
        .where((k) => (data[k]?.toString().trim() ?? '').isEmpty)
        .toList();

    if (missing.isEmpty && extra.isEmpty && empty.isEmpty) {
      stdout.writeln('  ✅ $name (${keys.length} anahtar)');
      continue;
    }
    if (missing.isNotEmpty) {
      stderr.writeln('  ❌ $name eksik: ${missing.join(', ')}');
      errors++;
    }
    if (extra.isNotEmpty) {
      stderr.writeln('  ❌ $name fazla (en\'de yok): ${extra.join(', ')}');
      errors++;
    }
    if (empty.isNotEmpty) {
      stderr.writeln('  ❌ $name boş değer: ${empty.join(', ')}');
      errors++;
    }
  }

  // ------------------------------------------------- 2. Hardcoded string
  stdout.writeln('▶ Hardcoded string taraması (lib/)');
  final patterns = <RegExp>[
    RegExp(r'''Text\(\s*['"]([^'"$]*[A-Za-zÇĞİÖŞÜçğıöşü][^'"$]*)['"]'''),
    RegExp(r'''(?:labelText|hintText|helperText|tooltip|title|semanticLabel)\s*:\s*['"]([^'"$]*[A-Za-zÇĞİÖŞÜçğıöşü][^'"$]*)['"]'''),
  ];
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.replaceAll('\\', '/').contains('lib/l10n/'));

  var hardcoded = 0;
  for (final file in dartFiles) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.contains('preflight:ignore')) {
        continue;
      }
      for (final pattern in patterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          hardcoded++;
          final path = file.path.replaceAll('\\', '/');
          stdout.writeln('  ⚠️  $path:${i + 1}  "${match.group(1)}"');
          break;
        }
      }
    }
  }
  if (hardcoded == 0) {
    stdout.writeln('  ✅ hardcoded UI metni yok');
  } else if (strict) {
    errors++;
  } else {
    warnings++;
  }

  // ------------------------------------------------- 3. Şablon yer tutucusu
  stdout.writeln('▶ Şablon yer tutucusu');
  final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj');
  if (pbxproj.existsSync() &&
      pbxproj.readAsStringSync().contains('com.example.starter')) {
    stdout.writeln('  ⚠️  Bundle ID hâlâ com.example.starter — '
        'dart run tool/rename.dart ile değiştir');
    warnings++;
  } else {
    stdout.writeln('  ✅ bundle ID ayarlanmış');
  }

  stdout.writeln('');
  if (errors > 0) {
    stderr.writeln('❌ Preflight başarısız: $errors hata, $warnings uyarı');
    exit(1);
  }
  stdout.writeln('✅ Preflight geçti ($warnings uyarı). '
      'Sırada: flutter analyze');
}

Map<String, dynamic> _readArb(File file) {
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('  ❌ ${file.path} geçerli bir JSON nesnesi değil');
    exit(1);
  }
  return decoded;
}

Set<String> _messageKeys(File file) =>
    _readArb(file).keys.where((k) => !k.startsWith('@')).toSet();
