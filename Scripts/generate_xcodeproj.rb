#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates Lemon.xcodeproj from the source tree.
# Run from the project root:    ruby Scripts/generate_xcodeproj.rb
#
# **WARNING:** This deletes and recreates the .xcodeproj. It does NOT preserve
# Swift Package dependencies (e.g. Firebase). Only run if you need a clean
# project from this script; otherwise edit Lemon.xcodeproj in Xcode.
#
# Requires the `xcodeproj` gem. If you ran `gem install --user-install xcodeproj`,
# the gem lives under ~/.gem/ruby/<version>/gems but is loadable via the standard
# `require`.

require 'xcodeproj'
require 'pathname'
require 'fileutils'

ROOT      = Pathname.new(File.expand_path('..', __dir__))
PROJ_PATH = ROOT.join('Lemon.xcodeproj')
APP_DIR   = ROOT.join('Lemon')
PRODUCT   = 'Lemon'
BUNDLE_ID = 'com.lemonowo.app'

FileUtils.rm_rf(PROJ_PATH)
project = Xcodeproj::Project.new(PROJ_PATH)

# --- App target --------------------------------------------------------------
target = project.new_target(
  :application,
  PRODUCT,
  :ios,
  '17.0',
  project.products_group,
  :swift
)

# Standard build settings
target.build_configurations.each do |config|
  bs = config.build_settings
  bs['PRODUCT_BUNDLE_IDENTIFIER']             = BUNDLE_ID
  bs['PRODUCT_NAME']                          = PRODUCT
  bs['SWIFT_VERSION']                         = '5.0'
  bs['IPHONEOS_DEPLOYMENT_TARGET']            = '17.0'
  bs['TARGETED_DEVICE_FAMILY']                = '1,2'
  bs['MARKETING_VERSION']                     = '1.0'
  bs['CURRENT_PROJECT_VERSION']               = '1'
  bs['INFOPLIST_FILE']                        = 'Lemon/Info.plist'
  bs['GENERATE_INFOPLIST_FILE']               = 'NO'
  bs['DEVELOPMENT_LANGUAGE']                  = 'en'
  bs['ASSETCATALOG_COMPILER_APPICON_NAME']    = 'AppIcon'
  bs['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  bs['DEVELOPMENT_ASSET_PATHS']               = '"Lemon/Preview Content"'
  bs['ENABLE_PREVIEWS']                       = 'YES'
  bs['CODE_SIGN_STYLE']                       = 'Automatic'
  bs['CODE_SIGN_IDENTITY']                    = 'Apple Development'
  bs['SWIFT_EMIT_LOC_STRINGS']                = 'YES'
  bs['ENABLE_USER_SCRIPT_SANDBOXING']         = 'YES'
end

# --- Source / resource files -------------------------------------------------
main_group = project.new_group(PRODUCT, APP_DIR.to_s, '<group>')

# Top-level files at Lemon/
%w[LemonApp.swift Info.plist GoogleService-Info.plist].each do |name|
  path = APP_DIR.join(name)
  next unless path.exist?
  ref = main_group.new_reference(path.to_s)
  if name.end_with?('.swift')
    target.add_file_references([ref])
  elsif name == 'GoogleService-Info.plist'
    target.resources_build_phase.add_file_reference(ref)
  end
end

# Folders that should map 1:1 to groups: each file becomes a build phase entry.
{
  'Theme'    => :source,
  'Models'   => :source,
  'Services' => :source,
  'Views'    => :source
}.each do |folder, _kind|
  dir = APP_DIR.join(folder)
  next unless dir.exist?
  group = main_group.new_group(folder, dir.to_s, '<group>')
  Dir.glob(dir.join('*.swift')).sort.each do |file|
    ref = group.new_reference(file)
    target.add_file_references([ref])
  end
end

# Bundled custom fonts. Each .ttf in Lemon/Fonts/ is copied flat into the
# app bundle so the corresponding entry in Info.plist's UIAppFonts array
# (e.g. <string>Fraunces72pt-Bold.ttf</string>) resolves at runtime.
fonts_dir = APP_DIR.join('Fonts')
if fonts_dir.exist?
  fonts_group = main_group.new_group('Fonts', fonts_dir.to_s, '<group>')
  Dir.glob(fonts_dir.join('*.{ttf,otf}')).sort.each do |file|
    ref = fonts_group.new_reference(file)
    target.resources_build_phase.add_file_reference(ref)
  end
end

# Resources: Assets.xcassets + Preview Content
assets_path = APP_DIR.join('Assets.xcassets')
if assets_path.exist?
  assets_ref = main_group.new_reference(assets_path.to_s)
  assets_ref.last_known_file_type = 'folder.assetcatalog'
  target.resources_build_phase.add_file_reference(assets_ref)
end

preview_path = APP_DIR.join('Preview Content')
if preview_path.exist?
  preview_group = main_group.new_group('Preview Content', preview_path.to_s, '<group>')
  preview_assets = preview_path.join('Preview Assets.xcassets')
  if preview_assets.exist?
    ref = preview_group.new_reference(preview_assets.to_s)
    ref.last_known_file_type = 'folder.assetcatalog'
    target.resources_build_phase.add_file_reference(ref)
  end
end

# --- Save --------------------------------------------------------------------
project.save

puts "Generated #{PROJ_PATH}"
