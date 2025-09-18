#!/opt/homebrew/opt/ruby/bin/ruby

require 'xcodeproj'

# Open the project
project_path = 'SwiftGTD.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Remove old file references from the main target
main_group = project.main_group
swift_gtd_group = main_group['SwiftGTD']

if swift_gtd_group
  # Remove old groups
  ['Models', 'Views', 'ViewModels', 'Services', 'Utils'].each do |group_name|
    group = swift_gtd_group[group_name]
    if group
      puts "Removing old group: #{group_name}"
      group.remove_from_project
    end
  end
  
  # Remove old files from build phases
  target.source_build_phase.files.select { |f| 
    path = f.file_ref&.path
    path && (path.include?('Models/') || path.include?('Views/') || 
             path.include?('ViewModels/') || path.include?('Services/') || 
             path.include?('Utils/'))
  }.each do |file|
    puts "Removing from build phase: #{file.file_ref.path}"
    file.remove_from_project
  end
end

# Add local Swift package reference
packages_path = File.expand_path('Packages')
package_ref = project.reference_for_path(packages_path)

unless package_ref
  puts "Adding local Swift package: #{packages_path}"
  package_ref = project.new(Xcodeproj::Project::Object::FileReference)
  package_ref.path = 'Packages'
  package_ref.source_tree = '<group>'
  project.main_group << package_ref
end

# Add package products to target
# Note: This part is tricky with xcodeproj gem. 
# It's better to add the package dependencies manually in Xcode

# Save the project
project.save
puts "\n✅ Project cleaned up!"
puts "\n⚠️  IMPORTANT: You need to manually add the Swift Package dependencies in Xcode:"
puts "1. Open SwiftGTD.xcodeproj in Xcode"
puts "2. Select the SwiftGTD target"
puts "3. Go to 'General' tab -> 'Frameworks, Libraries, and Embedded Content'"
puts "4. Click '+' and add these local packages from the Packages folder:"
puts "   - Core"
puts "   - Models"
puts "   - Networking"
puts "   - Services"
puts "   - Features"
puts "5. Build the project"