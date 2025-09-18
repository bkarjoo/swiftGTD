#!/opt/homebrew/opt/ruby/bin/ruby

require 'xcodeproj'
require 'pathname'

# Open the project
project_path = 'SwiftGTD.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Get the main target
target = project.targets.first

# Create a package reference
packages_group = project.main_group['Packages']
if packages_group.nil?
  puts "Adding Packages reference to project..."
  
  # Create file reference for Packages
  packages_ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
  packages_ref.path = 'Packages'
  packages_ref.source_tree = '<group>'
  packages_ref.last_known_file_type = 'folder'
  
  # Add to main group
  project.main_group << packages_ref
end

# Add package product dependencies to target
# This is the tricky part - we need to add package product dependencies

# First, ensure the project has package references
package_refs = project.root_object.package_references
if package_refs.empty?
  puts "Creating package reference..."
  
  # Create a local package reference
  package_ref = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
  package_ref.relative_path = 'Packages'
  
  project.root_object.package_references << package_ref
  
  # Create package product dependencies
  products = ['Core', 'Models', 'Networking', 'Services', 'Features']
  
  products.each do |product_name|
    puts "Adding #{product_name} to target dependencies..."
    
    # Create package product dependency
    product_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    product_dep.product_name = product_name
    product_dep.package = package_ref
    
    # Add to target
    target.package_product_dependencies << product_dep
  end
end

# Save the project
project.save

puts "\n✅ Package references added!"
puts "\n⚠️  IMPORTANT: After running this script:"
puts "1. Close Xcode completely"
puts "2. Open SwiftGTD.xcodeproj again"
puts "3. Wait for package resolution to complete"
puts "4. Build the project (Cmd+B)"
puts "\nIf you still see 'No such module' errors:"
puts "1. Clean build folder (Cmd+Shift+K)"
puts "2. Quit Xcode"
puts "3. Delete DerivedData:"
puts "   rm -rf ~/Library/Developer/Xcode/DerivedData/SwiftGTD-*"
puts "4. Open Xcode and try again"