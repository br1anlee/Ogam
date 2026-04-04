#!/bin/bash

# Security Check Script
# Run this before committing to ensure no sensitive data is exposed

echo "🔐 Running Security Check..."
echo ""

# Check if .gitignore exists
if [ ! -f ".gitignore" ]; then
    echo "❌ .gitignore not found!"
    echo "   Run: Create .gitignore file first"
    exit 1
else
    echo "✅ .gitignore exists"
fi

# Check if Config.swift is in .gitignore
if grep -q "Config.swift" .gitignore; then
    echo "✅ Config.swift is in .gitignore"
else
    echo "❌ Config.swift NOT in .gitignore!"
    echo "   Add 'Config.swift' to .gitignore"
    exit 1
fi

# Check if GoogleService-Info.plist is in .gitignore
if grep -q "GoogleService-Info.plist" .gitignore; then
    echo "✅ GoogleService-Info.plist is in .gitignore"
else
    echo "⚠️  GoogleService-Info.plist not in .gitignore"
fi

# Check if Config.swift would be committed
if git check-ignore Config.swift > /dev/null 2>&1; then
    echo "✅ Config.swift is properly ignored by Git"
else
    echo "❌ Config.swift is NOT ignored by Git!"
    echo "   This means it would be committed!"
    exit 1
fi

# Check if Config.swift.template exists
if [ -f "Config.swift.template" ]; then
    echo "✅ Config.swift.template exists (safe to commit)"
else
    echo "⚠️  Config.swift.template not found"
    echo "   Create it for team members"
fi

# Check if any secrets are staged
echo ""
echo "📋 Checking staged files..."
STAGED_FILES=$(git diff --cached --name-only)

if echo "$STAGED_FILES" | grep -q "Config.swift"; then
    echo "❌ DANGER! Config.swift is staged for commit!"
    echo "   Run: git reset Config.swift"
    exit 1
else
    echo "✅ No Config.swift in staged files"
fi

if echo "$STAGED_FILES" | grep -q "GoogleService-Info.plist"; then
    echo "❌ DANGER! GoogleService-Info.plist is staged!"
    echo "   Run: git reset GoogleService-Info.plist"
    exit 1
else
    echo "✅ No GoogleService-Info.plist in staged files"
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Security Check PASSED!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Safe to commit! 🚀"
echo ""
echo "Files that will be committed:"
if [ -z "$STAGED_FILES" ]; then
    echo "   (none - stage your files with 'git add')"
else
    echo "$STAGED_FILES" | sed 's/^/   /'
fi

exit 0
