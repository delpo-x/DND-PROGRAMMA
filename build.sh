#!/bin/sh
# Builds the Windows and Android apps into build/.
# Needs the Godot 4.5.2 editor in .tools/godot and a JDK 17 in .tools/jdk17.
# The Android signing key is read from environment variables, never from git:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH, GODOT_ANDROID_KEYSTORE_RELEASE_USER,
#   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
set -e
cd "$(dirname "$0")"
GODOT=$(ls .tools/godot/*console*.exe | head -1)
export JAVA_HOME="$PWD/.tools/jdk17"
"$GODOT" --headless --path . --export-release "Windows Desktop" build/DnD_Tavolo_Master.exe
"$GODOT" --headless --path . --export-release "Android" build/DnD_Tavolo_Master.apk
