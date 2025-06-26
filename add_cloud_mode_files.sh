#!/bin/bash

# Script to add Cloud Mode files to Xcode project

echo "Adding Cloud Mode files to Xcode project..."

# Navigate to project directory
cd "/Users/rowanbradley/Documents/Voice Note v2/Voice Note v2"

# Open Xcode and add files
cat << EOF

Please follow these steps in Xcode:

1. Open the Voice Note v2 project in Xcode

2. Right-click on the "Services" group and select "Add Files to Voice Note v2..."
   Add these files:
   - TranscriptionSettings.swift
   - SpeechTranscribing.swift
   - TranscriptionService_CloudMode.swift

3. Right-click on the project root and create a new group called "TestSupport"
   Then add:
   - TestLaunchHandler.swift

4. For the test target, right-click on "Voice Note v2Tests" and add:
   - CloudModeTests.swift

5. For the UI test target, right-click on "Voice Note v2UITests" and add:
   - CloudModeUITests.swift

6. Make sure all files are added to the correct targets:
   - Main app files → Voice Note v2 target
   - Test files → Respective test targets

7. Build the project (Cmd+B)

Alternative: Command Line Approach
You can also try using ruby to add files programmatically:

EOF

# Create a Ruby script to add files
cat > add_files_to_project.rb << 'RUBY_EOF'
#!/usr/bin/env ruby

require 'xcodeproj'

# Open the project
project_path = 'Voice Note v2.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get main target
main_target = project.targets.find { |t| t.name == 'Voice Note v2' }
test_target = project.targets.find { |t| t.name == 'Voice Note v2Tests' }
ui_test_target = project.targets.find { |t| t.name == 'Voice Note v2UITests' }

# Get main group
main_group = project.main_group

# Find or create groups
services_group = main_group.find_subpath('Services', true)
test_support_group = main_group.new_group('TestSupport')
tests_group = main_group.find_subpath('Voice Note v2Tests', true)
ui_tests_group = main_group.find_subpath('Voice Note v2UITests', true)

# Add service files
['TranscriptionSettings.swift', 'SpeechTranscribing.swift', 'TranscriptionService_CloudMode.swift'].each do |file|
  file_ref = services_group.new_reference("Services/#{file}")
  main_target.add_file_references([file_ref])
end

# Add test support files
file_ref = test_support_group.new_reference('TestSupport/TestLaunchHandler.swift')
main_target.add_file_references([file_ref])

# Add test files
if test_target && tests_group
  file_ref = tests_group.new_reference('Voice Note v2Tests/CloudModeTests.swift')
  test_target.add_file_references([file_ref])
end

# Add UI test files
if ui_test_target && ui_tests_group
  file_ref = ui_tests_group.new_reference('Voice Note v2UITests/CloudModeUITests.swift')
  ui_test_target.add_file_references([file_ref])
end

# Save the project
project.save

puts "Files added successfully!"
RUBY_EOF

echo "Ruby script created. To use it:"
echo "1. Install xcodeproj gem: gem install xcodeproj"
echo "2. Run: ruby add_files_to_project.rb"
echo ""
echo "Or manually add the files in Xcode as described above."