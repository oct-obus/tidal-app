#!/usr/bin/env ruby
# Modifies the Flutter-generated Xcode project to include Python.xcframework
# and adds the PythonBridge.swift file to the Runner target.

require 'xcodeproj'

project_path = File.join(__dir__, '..', 'ios', 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |t| t.name == 'Runner' }

# --- Add Python.xcframework ---

# The framework is expected at ios/Python.xcframework
fw_path = 'Python.xcframework'
fw_ref = project.frameworks_group.new_file(fw_path, :project)

# Add to "Link Binary With Libraries" build phase
target.frameworks_build_phase.add_file_reference(fw_ref)

# Add to "Embed Frameworks" build phase (create if missing)
embed_phase = target.build_phases.find { |p| p.is_a?(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase) && p.symbol_dst_subfolder_spec == :frameworks }
unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed Frameworks'
  embed_phase.symbol_dst_subfolder_spec = :frameworks
  target.build_phases << embed_phase
end
build_file = embed_phase.add_file_reference(fw_ref)
build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }

# --- Add PythonBridge.swift ---

runner_group = project.main_group.find_subpath('Runner', true)
bridge_ref = runner_group.new_file('PythonBridge.swift')
target.source_build_phase.add_file_reference(bridge_ref)

# --- Add AudioBridge.swift ---

audio_ref = runner_group.new_file('AudioBridge.swift')
target.source_build_phase.add_file_reference(audio_ref)

# --- Add Run Script build phase for Python stdlib installation ---
# NOTE: Stdlib installation is now done post-build by scripts/post_build.sh
# The Xcode build phase is no longer needed for this.
# We only keep the app code/packages copy for the build to reference.

# --- Add header search path for Python headers ---

target.build_configurations.each do |config|
  settings = config.build_settings

  # Framework search paths
  existing_fw = settings['FRAMEWORK_SEARCH_PATHS'] || ['$(inherited)']
  existing_fw = [existing_fw] unless existing_fw.is_a?(Array)
  unless existing_fw.include?('$(PROJECT_DIR)/Python.xcframework/ios-arm64')
    existing_fw << '$(PROJECT_DIR)/Python.xcframework/ios-arm64'
    existing_fw << '$(PROJECT_DIR)/Python.xcframework/ios-arm64_x86_64-simulator'
  end
  settings['FRAMEWORK_SEARCH_PATHS'] = existing_fw

  # Header search paths (for #include <Python/Python.h>)
  existing_hdr = settings['HEADER_SEARCH_PATHS'] || ['$(inherited)']
  existing_hdr = [existing_hdr] unless existing_hdr.is_a?(Array)
  unless existing_hdr.include?('$(PROJECT_DIR)/Python.xcframework/ios-arm64/include')
    existing_hdr << '$(PROJECT_DIR)/Python.xcframework/ios-arm64/include'
  end
  settings['HEADER_SEARCH_PATHS'] = existing_hdr

  # Other linker flags
  existing_ld = settings['OTHER_LDFLAGS'] || ['$(inherited)']
  existing_ld = [existing_ld] unless existing_ld.is_a?(Array)
  unless existing_ld.include?('-lpython3.13')
    existing_ld << '-framework'
    existing_ld << 'Python'
  end
  settings['OTHER_LDFLAGS'] = existing_ld
end

project.save
puts "✅ Xcode project updated: Python.xcframework + PythonBridge.swift added"
