#!/opt/homebrew/opt/ruby/bin/ruby

require 'xcodeproj'

# Open the project
project_path = 'SwiftGTD.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Get the main group (root group)
main_group = project.main_group

# Find or create the SwiftGTD group
swift_gtd_group = main_group['SwiftGTD']
if swift_gtd_group.nil?
  puts "Creating SwiftGTD group..."
  swift_gtd_group = main_group.new_group('SwiftGTD', 'SwiftGTD')
end

# Define the folder structure
folders = {
  'Models' => ['Node.swift', 'Tag.swift', 'User.swift'],
  'Views' => ['CreateNodeView.swift', 'LoginView.swift', 'MainTabView.swift', 
              'NodeDetailView.swift', 'NodesListView.swift', 'ProjectsView.swift', 
              'SettingsView.swift', 'TagsView.swift'],
  'ViewModels' => ['AuthManager.swift', 'DataManager.swift'],
  'Services' => ['APIClient.swift'],
  'Utils' => []
}

# Add root level files
root_files = ['ContentView.swift', 'SwiftGTDApp.swift']

# Add root level files first
root_files.each do |file_name|
  file_path = "SwiftGTD/#{file_name}"
  
  if File.exist?(file_path)
    # Check if file is already in project
    existing_ref = swift_gtd_group.files.find { |f| f.path&.end_with?(file_name) }
    
    unless existing_ref
      # Add file reference with relative path
      file_ref = swift_gtd_group.new_reference(file_name)
      file_ref.set_path(file_name)
      # Add to target
      target.add_file_references([file_ref])
      puts "Added: #{file_name}"
    else
      puts "Already exists: #{file_name}"
    end
  else
    puts "File not found: #{file_path}"
  end
end

# Add files in folders
folders.each do |folder_name, files|
  # Get or create the group
  group = swift_gtd_group[folder_name]
  if group.nil?
    group = swift_gtd_group.new_group(folder_name, folder_name)
    puts "Created group: #{folder_name}"
  end
  
  files.each do |file_name|
    file_path = "SwiftGTD/#{folder_name}/#{file_name}"
    
    # Check if file exists
    if File.exist?(file_path)
      # Check if file is already in project
      existing_ref = group.files.find { |f| f.path&.end_with?(file_name) }
      
      unless existing_ref
        # Add file reference with just the filename
        file_ref = group.new_reference(file_name)
        file_ref.set_path(file_name)
        # Add to target
        target.add_file_references([file_ref])
        puts "Added: #{folder_name}/#{file_name}"
      else
        puts "Already exists: #{folder_name}/#{file_name}"
      end
    else
      puts "File not found: #{file_path}"
    end
  end
end

# Save the project
project.save
puts "\n✅ Project updated successfully!"
puts "Please restart Xcode if it's currently open to see the changes."