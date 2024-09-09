#!/bin/sh

# Locating file
PROJECT_FILE="../ExcalidrawZ.xcodeproj/project.pbxproj"

if [ -f "$PROJECT_FILE" ]; then
    sed -i '' 's/objectVersion = 70;/objectVersion = 60;/g' "$PROJECT_FILE"
    echo "Modified objectVersion to 60."
else
    echo "Error: Project file does not exist."
    exit 1
fi