#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status
set -u  # Treat unset variables as an error
set -o pipefail

START_TIME=$(date +%s)

# Default options
BUILD_EDITOR_ONLY=false
PLATFORMS=(linuxbsd windows)
SCONS_ARGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --editor-only)
      BUILD_EDITOR_ONLY=true
      shift
      ;;
    --platforms)
      shift
      IFS=',' read -ra PLATFORMS <<< "$1"
      shift
      ;;
    --scons-args)
      shift
      IFS=' ' read -ra SCONS_ARGS <<< "$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

echo "=== Cleaning output for specified platforms ==="
for PLATFORM in "${PLATFORMS[@]}"; do
  echo "Cleaning bin/*${PLATFORM}*"
  rm -rf bin/*${PLATFORM}*
done

for PLATFORM in "${PLATFORMS[@]}"; do
  echo "=== Building for platform: $PLATFORM ==="

  EDITOR_TARGET=editor
  GODOT_BIN="bin/godot.$PLATFORM.$EDITOR_TARGET.x86_64.mono"
  NUGET_OUTPUT="bin/nuget"

  echo "=== Building Godot editor ==="
  scons platform=$PLATFORM target=$EDITOR_TARGET module_mono_enabled=yes "${SCONS_ARGS[@]}"

  if [ "$BUILD_EDITOR_ONLY" = false ]; then
    echo "=== Building export templates ==="
    scons platform=$PLATFORM target=template_debug module_mono_enabled=yes "${SCONS_ARGS[@]}"
    scons platform=$PLATFORM target=template_release module_mono_enabled=yes "${SCONS_ARGS[@]}"
  fi

  if [ "$PLATFORM" = "linuxbsd" ]; then
    echo "=== Generating Mono glue sources ==="
    $GODOT_BIN --headless --generate-mono-glue modules/mono/glue
  fi

  echo "=== Building Mono assemblies ==="
  ./modules/mono/build_scripts/build_assemblies.py \
    --godot-output-dir=./bin \
    --push-nupkgs-local $NUGET_OUTPUT \
    --godot-platform=$PLATFORM

  echo "=== Organizing output for $PLATFORM ==="
  OUTPUT_DIR="bin/$PLATFORM"
  mkdir -p "$OUTPUT_DIR"

  # Move editor binary
    if [ "$PLATFORM" = "windows" ]; then
      if [ -f "$GODOT_BIN.exe" ]; then
        mv "$GODOT_BIN.exe" "$OUTPUT_DIR/godot.exe"
      fi
      # Move export templates and rename
      mv bin/*.$PLATFORM.template_debug.exe "$OUTPUT_DIR/template_debug.exe" 2>/dev/null || true
      mv bin/*.$PLATFORM.template_release.exe "$OUTPUT_DIR/template_release.exe" 2>/dev/null || true
    else
      # For other platforms (like linuxbsd)
      if [ -f "$GODOT_BIN" ]; then
        mv "$GODOT_BIN" "$OUTPUT_DIR/godot"
      fi
      mv bin/*.$PLATFORM.template_debug* "$OUTPUT_DIR/template_debug" 2>/dev/null || true
      mv bin/*.$PLATFORM.template_release* "$OUTPUT_DIR/template_release" 2>/dev/null || true
    fi


  # Copy GodotSharp and nuget folders
  cp -r bin/GodotSharp "$OUTPUT_DIR/" 2>/dev/null || true
  cp -r bin/nuget "$OUTPUT_DIR/" 2>/dev/null || true

  # Clean up originals
  rm -rf bin/GodotSharp bin/nuget

  echo "=== Packing $PLATFORM folder ==="
  tar -czf "bin/$PLATFORM.tar.gz" -C bin "$PLATFORM"

done

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
MINUTES=$((DURATION / 60))
SECONDS=$((DURATION % 60))

echo "=== Build completed successfully in ${MINUTES}m ${SECONDS}s ==="
