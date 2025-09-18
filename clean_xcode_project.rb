#!/opt/homebrew/opt/ruby/bin/ruby

require 'xcodeproj'

# Open the project
project_path = 'SwiftGTD.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Remove all old file references from build phases
removed_count = 0
target.source_build_phase.files.select { |f| 
  path = f.file_ref&.path
  if path
    # Remove if path contains old structure folders or doesn't exist
    should_remove = path.include?('Models/') || 
                   path.include?('Views/') || 
                   path.include?('ViewModels/') || 
                   path.include?('Services/') || 
                   path.include?('Utils/') ||
                   path.include?('TreeView.swift') ||
                   !File.exist?(File.join('SwiftGTD', path))
    
    if should_remove
      puts "Removing from build phase: #{path}"
      removed_count += 1
      true
    else
      false
    end
  else
    false
  end
}.each do |file|
  file.remove_from_project
end

# Clean up file references from project navigator
project.main_group.recursive_children.select { |child|
  if child.is_a?(Xcodeproj::Project::Object::PBXFileReference)
    path = child.path
    if path && (path.include?('Models/') || 
                path.include?('Views/') || 
                path.include?('ViewModels/') || 
                path.include?('Services/') || 
                path.include?('Utils/') ||
                path.include?('TreeView.swift'))
      puts "Removing file reference: #{path}"
      removed_count += 1
      true
    else
      false
    end
  else
    false
  end
}.each do |ref|
  ref.remove_from_project
end

# Save the project
project.save
puts "\n✅ Cleaned up #{removed_count} old file references!"
puts "\nNext steps:"
puts "1. Open SwiftGTD.xcodeproj in Xcode"
puts "2. File → Add Package Dependencies"
puts "3. Add Local → Select the 'Packages' folder"
puts "4. Add all 5 package products (Core, Models, Networking, Services, Features) to the target"
puts "5. Build the project"