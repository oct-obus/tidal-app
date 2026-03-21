#!/bin/bash
# Post-build script: Install Python stdlib + packages into app bundle.
# Converts .so files to .framework bundles with ad-hoc signing.
# Run after `flutter build ios --release --no-codesign`.

set -e

APP_BUNDLE="$1"  # e.g., build/ios/iphoneos/Runner.app
PYTHON_XCFW="$2" # e.g., ios/Python.xcframework
INFO_PLIST_TEMPLATE="$PYTHON_XCFW/build/iOS-dylib-Info-template.plist"

if [ -z "$APP_BUNDLE" ] || [ -z "$PYTHON_XCFW" ]; then
    echo "Usage: $0 <app-bundle-path> <python-xcframework-path>"
    exit 1
fi

echo "=== Post-build Python integration ==="
echo "App bundle: $APP_BUNDLE"
echo "Python XCFramework: $PYTHON_XCFW"

# 1. Install stdlib
echo "→ Installing Python stdlib..."
STDLIB_DEST="$APP_BUNDLE/python/lib"
mkdir -p "$STDLIB_DEST"

# Copy shared stdlib (pure Python modules)
if [ -d "$PYTHON_XCFW/lib" ]; then
    rsync -au "$PYTHON_XCFW/lib/" "$STDLIB_DEST/"
    # Copy arch-specific modules (C extensions as .so)
    if [ -d "$PYTHON_XCFW/ios-arm64/lib-arm64" ]; then
        rsync -au "$PYTHON_XCFW/ios-arm64/lib-arm64/" "$STDLIB_DEST/"
    fi
else
    rsync -au "$PYTHON_XCFW/ios-arm64/lib/" "$STDLIB_DEST/" --exclude 'libpython*.dylib'
fi

# Determine Python version
PYTHON_VER=$(ls -1 "$STDLIB_DEST" | head -1)
echo "  Python version: $PYTHON_VER"

# 2. Convert .so → .framework bundles
echo "→ Converting .so files to framework bundles..."

convert_so_to_framework() {
    local SO_FILE="$1"
    local INSTALL_BASE="$2"
    
    local EXT_NAME=$(basename "$SO_FILE")
    local MODULE_NAME=$(echo "$EXT_NAME" | cut -d "." -f 1)
    
    # Build full dotted module name from path
    local RELATIVE_PATH="${SO_FILE#$APP_BUNDLE/}"
    local PYTHON_PATH="${RELATIVE_PATH#$INSTALL_BASE/}"
    local FULL_MODULE_NAME=$(echo "$PYTHON_PATH" | cut -d "." -f 1 | tr "/" ".")
    
    local FRAMEWORK_DIR="$APP_BUNDLE/Frameworks/$FULL_MODULE_NAME.framework"
    
    if [ ! -d "$FRAMEWORK_DIR" ]; then
        mkdir -p "$FRAMEWORK_DIR"
        
        # Create Info.plist
        if [ -f "$INFO_PLIST_TEMPLATE" ]; then
            cp "$INFO_PLIST_TEMPLATE" "$FRAMEWORK_DIR/Info.plist"
        else
            cat > "$FRAMEWORK_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$FULL_MODULE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>org.python.$FULL_MODULE_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>MinimumOSVersion</key>
    <string>13.0</string>
</dict>
</plist>
PLIST
        fi
        
        plutil -replace CFBundleExecutable -string "$FULL_MODULE_NAME" "$FRAMEWORK_DIR/Info.plist"
        plutil -replace CFBundleIdentifier -string "org.python.$(echo $FULL_MODULE_NAME | tr '_' '-')" "$FRAMEWORK_DIR/Info.plist"
    fi
    
    # Move .so into framework
    mv "$SO_FILE" "$FRAMEWORK_DIR/$FULL_MODULE_NAME"
    
    # Create .fwork placeholder
    echo "Frameworks/$FULL_MODULE_NAME.framework/$FULL_MODULE_NAME" > "${SO_FILE%.so}.fwork"
    
    # Create back-reference
    echo "${RELATIVE_PATH%.so}.fwork" > "$FRAMEWORK_DIR/$FULL_MODULE_NAME.origin"
    
    # Ad-hoc sign
    /usr/bin/codesign --force --sign - --timestamp=none "$FRAMEWORK_DIR" 2>/dev/null || true
    
    echo "  ✓ $FULL_MODULE_NAME"
}

# Process stdlib C extensions
SO_COUNT=0
find "$STDLIB_DEST/$PYTHON_VER/lib-dynload" -name "*.so" 2>/dev/null | while read SO_FILE; do
    convert_so_to_framework "$SO_FILE" "python/lib/$PYTHON_VER/lib-dynload"
done

echo "  Stdlib C extensions processed"

# 3. Install app code
echo "→ Installing app code..."
APP_DEST="$APP_BUNDLE/python/app"
mkdir -p "$APP_DEST"

if [ -d "python_app" ]; then
    rsync -au python_app/ "$APP_DEST/"
    echo "  ✓ App code installed"
fi

# 4. Install Python packages
echo "→ Installing Python packages..."
PKG_DEST="$APP_BUNDLE/python/app_packages"
mkdir -p "$PKG_DEST"

if [ -d "python_packages_built" ]; then
    rsync -au python_packages_built/ "$PKG_DEST/"
    echo "  ✓ Packages installed"
fi

# Also install our custom shim packages
if [ -d "python_packages" ]; then
    rsync -au python_packages/ "$PKG_DEST/"
    echo "  ✓ Shim packages installed"
fi

# Process any .so files in packages (remove macOS binaries)
find "$PKG_DEST" -name "*.so" -delete 2>/dev/null || true
find "$PKG_DEST" -name "*.dylib" -delete 2>/dev/null || true
# Remove __pycache__ to save space
find "$PKG_DEST" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
# Remove .dist-info to save space
find "$PKG_DEST" -name "*.dist-info" -type d -exec rm -rf {} + 2>/dev/null || true

# 5. Clean up stdlib test modules to save space
echo "→ Cleaning up..."
rm -rf "$STDLIB_DEST/$PYTHON_VER/test" 2>/dev/null || true
rm -rf "$STDLIB_DEST/$PYTHON_VER/unittest/test" 2>/dev/null || true
rm -rf "$STDLIB_DEST/$PYTHON_VER/idlelib" 2>/dev/null || true
rm -rf "$STDLIB_DEST/$PYTHON_VER/tkinter" 2>/dev/null || true
rm -rf "$STDLIB_DEST/$PYTHON_VER/turtledemo" 2>/dev/null || true
rm -rf "$STDLIB_DEST/$PYTHON_VER/ensurepip" 2>/dev/null || true
find "$STDLIB_DEST" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true

echo "=== Post-build complete ==="
echo "App bundle size: $(du -sh "$APP_BUNDLE" | cut -f1)"
