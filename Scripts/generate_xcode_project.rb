#!/usr/bin/env ruby
# frozen_string_literal: true

require "xcodeproj"
require "fileutils"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "NuFinder.xcodeproj")
FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path)

app = project.new_target(:application, "NuFinder", :osx, "15.0")
extension = project.new_target(:app_extension, "NuFinderFinderSync", :osx, "15.0")

sources_group = project.main_group.new_group("Sources", "Sources/NuFinder")
Dir.glob(File.join(root, "Sources/NuFinder/**/*.swift")).sort.each do |path|
  ref = sources_group.new_file(path.delete_prefix("#{root}/Sources/NuFinder/"))
  app.source_build_phase.add_file_reference(ref)
end

extension_group = project.main_group.new_group("FinderSyncExtension", "FinderSyncExtension")
extension_ref = extension_group.new_file("FinderSyncExtension.swift")
extension.source_build_phase.add_file_reference(extension_ref)

config_group = project.main_group.new_group("Config", "Config")
%w[App-Info.plist NuFinder.entitlements FinderSync-Info.plist FinderSync.entitlements].each do |name|
  config_group.new_file(name)
end

[app, extension].each do |target|
  target.build_configurations.each do |config|
    config.build_settings["SWIFT_VERSION"] = "6.0"
    config.build_settings["MACOSX_DEPLOYMENT_TARGET"] = "15.0"
    config.build_settings["CODE_SIGN_STYLE"] = "Automatic"
    config.build_settings["DEVELOPMENT_TEAM"] = "FLJNW3455S"
    config.build_settings["ENABLE_HARDENED_RUNTIME"] = "YES"
  end
end

app.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.miguelrodriguez.NuFinder"
  config.build_settings["INFOPLIST_FILE"] = "Config/App-Info.plist"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "Config/NuFinder.entitlements"
  config.build_settings["PRODUCT_NAME"] = "NuFinder"
end

extension.build_configurations.each do |config|
  config.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.miguelrodriguez.NuFinder.FinderSync"
  config.build_settings["INFOPLIST_FILE"] = "Config/FinderSync-Info.plist"
  config.build_settings["CODE_SIGN_ENTITLEMENTS"] = "Config/FinderSync.entitlements"
  config.build_settings["PRODUCT_NAME"] = "NuFinderFinderSync"
  config.build_settings["SKIP_INSTALL"] = "YES"
end

copy_extensions = app.new_copy_files_build_phase("Embed App Extensions")
copy_extensions.symbol_dst_subfolder_spec = :plug_ins
copy_extensions.add_file_reference(extension.product_reference)
app.add_dependency(extension)

project.recreate_user_schemes
project.save
