#!/usr/bin/env ruby
require 'xcodeproj'

# ShareExtension target'ı Xcode projesinde yoksa ekler (varsa hiçbir şey yapmaz).
# Codemagic'te pre-build adımında çalışır; Mac'e ihtiyaç duymadan
# Share Extension'lı build almayı sağlar.
#
# BUNDLE_ID ve APPLE_TEAM_ID ortam değişkenlerinden okunur;
# yoksa aşağıdaki varsayılanlar kullanılır (tool/rename.dart günceller).
PROJECT_PATH = 'ios/Runner.xcodeproj'
EXTENSION_NAME = 'ShareExtension'
APP_BUNDLE_ID = ENV.fetch('BUNDLE_ID', 'com.example.starter')
BUNDLE_ID = "#{APP_BUNDLE_ID}.ShareExtension"
DEPLOYMENT_TARGET = '13.0'
TEAM_ID = ENV.fetch('APPLE_TEAM_ID', 'F844P9C24K')

project = Xcodeproj::Project.open(PROJECT_PATH)

if project.targets.any? { |t| t.name == EXTENSION_NAME }
  puts "ShareExtension zaten mevcut, atlanıyor."
  exit 0
end

puts "ShareExtension target ekleniyor..."

ext_target = project.new_target(
  :app_extension,
  EXTENSION_NAME,
  :ios,
  DEPLOYMENT_TARGET
)

ext_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = EXTENSION_NAME
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = BUNDLE_ID
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
  config.build_settings['INFOPLIST_FILE'] = "ShareExtension/Info.plist"
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = "ShareExtension/ShareExtension.entitlements"
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/../../Frameworks']
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
  config.build_settings['ENABLE_BITCODE'] = 'NO'
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['DEVELOPMENT_TEAM'] = TEAM_ID
  config.build_settings['USER_SCRIPT_SANDBOXING'] = 'NO'
  config.build_settings['SKIP_INSTALL'] = 'NO'
  config.build_settings['EXECUTABLE_NAME'] = EXTENSION_NAME
end

# Grup oluştur — path olarak 'ShareExtension' klasörünü göster
ext_group = project.main_group.new_group(EXTENSION_NAME, EXTENSION_NAME)

# Dosyaları doğrudan path ile ekle
swift_file = ext_group.new_file('ShareViewController.swift')
ext_target.source_build_phase.add_file_reference(swift_file)

# Info.plist sadece referans — build phase'e ekleme
ext_group.new_file('Info.plist')

runner_target = project.targets.find { |t| t.name == 'Runner' }

embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_phase.name = 'Embed Foundation Extensions'
embed_phase.dst_subfolder_spec = '13'
embed_phase.dst_path = ''

thin_binary_index = runner_target.build_phases.index { |p|
  p.respond_to?(:name) && p.name == 'Thin Binary'
}

if thin_binary_index
  runner_target.build_phases.insert(thin_binary_index, embed_phase)
else
  runner_target.build_phases << embed_phase
end

embed_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
embed_build_file.file_ref = ext_target.product_reference
embed_build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
embed_phase.files << embed_build_file

project.save
puts "✅ ShareExtension başarıyla eklendi!"