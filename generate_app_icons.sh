#!/bin/bash

# Generate all required app icon sizes for iOS and macOS

SOURCE_ICON="Minimalist Checkmark Icon Design.png"
IOS_ICONSET="SwiftGTD/Assets.xcassets/AppIcon.appiconset"
MACOS_ICONSET="SwiftGTD-macOS/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SOURCE_ICON" ]; then
    echo "❌ Icon file not found: $SOURCE_ICON"
    exit 1
fi

echo "🎨 Generating app icons from: $SOURCE_ICON"

# Create directories if they don't exist
mkdir -p "$IOS_ICONSET"
mkdir -p "$MACOS_ICONSET"

# iOS Icons
echo "📱 Generating iOS icons..."

# iPhone icons
sips -z 40 40 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-20@2x.png" > /dev/null
sips -z 60 60 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-20@3x.png" > /dev/null
sips -z 58 58 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-29@2x.png" > /dev/null
sips -z 87 87 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-29@3x.png" > /dev/null
sips -z 80 80 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-40@2x.png" > /dev/null
sips -z 120 120 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-40@3x.png" > /dev/null
sips -z 120 120 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-60@2x.png" > /dev/null
sips -z 180 180 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-60@3x.png" > /dev/null

# iPad icons
sips -z 20 20 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-20.png" > /dev/null
sips -z 29 29 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-29.png" > /dev/null
sips -z 40 40 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-40.png" > /dev/null
sips -z 76 76 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-76.png" > /dev/null
sips -z 152 152 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-76@2x.png" > /dev/null
sips -z 167 167 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-83.5@2x.png" > /dev/null

# App Store
sips -z 1024 1024 "$SOURCE_ICON" --out "$IOS_ICONSET/icon-1024.png" > /dev/null

# Create Contents.json for iOS
cat > "$IOS_ICONSET/Contents.json" << 'EOF'
{
  "images" : [
    {
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "20x20",
      "filename" : "icon-20@2x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "20x20",
      "filename" : "icon-20@3x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "29x29",
      "filename" : "icon-29@2x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "29x29",
      "filename" : "icon-29@3x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "40x40",
      "filename" : "icon-40@2x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "40x40",
      "filename" : "icon-40@3x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "2x",
      "size" : "60x60",
      "filename" : "icon-60@2x.png"
    },
    {
      "idiom" : "iphone",
      "scale" : "3x",
      "size" : "60x60",
      "filename" : "icon-60@3x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "20x20",
      "filename" : "icon-20.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "20x20",
      "filename" : "icon-20@2x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "29x29",
      "filename" : "icon-29.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "29x29",
      "filename" : "icon-29@2x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "40x40",
      "filename" : "icon-40.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "40x40",
      "filename" : "icon-40@2x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "1x",
      "size" : "76x76",
      "filename" : "icon-76.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "76x76",
      "filename" : "icon-76@2x.png"
    },
    {
      "idiom" : "ipad",
      "scale" : "2x",
      "size" : "83.5x83.5",
      "filename" : "icon-83.5@2x.png"
    },
    {
      "idiom" : "ios-marketing",
      "scale" : "1x",
      "size" : "1024x1024",
      "filename" : "icon-1024.png"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

# macOS Icons
echo "💻 Generating macOS icons..."

sips -z 16 16 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-16.png" > /dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-16@2x.png" > /dev/null
sips -z 32 32 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-32.png" > /dev/null
sips -z 64 64 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-32@2x.png" > /dev/null
sips -z 128 128 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-128.png" > /dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-128@2x.png" > /dev/null
sips -z 256 256 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-256.png" > /dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-256@2x.png" > /dev/null
sips -z 512 512 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-512.png" > /dev/null
sips -z 1024 1024 "$SOURCE_ICON" --out "$MACOS_ICONSET/icon-512@2x.png" > /dev/null

# Create Contents.json for macOS
cat > "$MACOS_ICONSET/Contents.json" << 'EOF'
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16",
      "filename" : "icon-16.png"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16",
      "filename" : "icon-16@2x.png"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32",
      "filename" : "icon-32.png"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32",
      "filename" : "icon-32@2x.png"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128",
      "filename" : "icon-128.png"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128",
      "filename" : "icon-128@2x.png"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256",
      "filename" : "icon-256.png"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256",
      "filename" : "icon-256@2x.png"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512",
      "filename" : "icon-512.png"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512",
      "filename" : "icon-512@2x.png"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "✅ Icons generated successfully!"
echo "📁 iOS icons: $IOS_ICONSET"
echo "📁 macOS icons: $MACOS_ICONSET"
echo ""
echo "🔄 Now rebuild your apps to see the new icon!"