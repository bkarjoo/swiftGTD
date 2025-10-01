#!/bin/bash

# Find and fix all incorrect logger argument orders
find /Users/behroozkarjoo/dev/swiftGTD/Packages -name "*.swift" -type f | while read -r file; do
    # Fix level before category
    sed -i '' 's/level: \.error, category: /category: "placeholder", level: .error/g' "$file"
    sed -i '' 's/level: \.warning, category: /category: "placeholder", level: .warning/g' "$file"
    sed -i '' 's/level: \.debug, category: /category: "placeholder", level: .debug/g' "$file"
    sed -i '' 's/level: \.info, category: /category: "placeholder", level: .info/g' "$file"

    # Now fix the category placeholders
    sed -i '' 's/category: "placeholder", level: \.error\]/category: \1, level: .error/g' "$file"
    sed -i '' 's/category: "placeholder", level: \.warning\]/category: \1, level: .warning/g' "$file"
    sed -i '' 's/category: "placeholder", level: \.debug\]/category: \1, level: .debug/g' "$file"
    sed -i '' 's/category: "placeholder", level: \.info\]/category: \1, level: .info/g' "$file"
done

echo "Fixed logger argument order issues"