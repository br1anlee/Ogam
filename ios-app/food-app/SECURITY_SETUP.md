# 🔐 Security Setup - IMPORTANT!

## ⚠️ Your API Key is Currently Exposed!

Your `Config.swift` file contains a real Google Places API key. To protect it:

## Quick Fix (Do This Now!)

### Option 1: If you haven't committed yet (Recommended)

```bash
# 1. The .gitignore is already set up
# 2. If you haven't run 'git add' yet, you're safe!
# 3. Just make sure Config.swift is listed when you run:
git status

# If Config.swift appears in "Untracked files" or "Changes not staged" - you're good!
# Just never add it:
# ❌ Don't run: git add Config.swift
```

### Option 2: If you already committed Config.swift

```bash
# 1. Remove from Git history (keeps local file)
git rm --cached Config.swift

# 2. Commit the removal
git commit -m "Remove Config.swift from version control"

# 3. Verify .gitignore is working
git status
# Config.swift should NOT appear now

# 4. Push changes
git push
```

### Option 3: If you pushed to GitHub (URGENT!)

**Your API key is public! You must:**

1. **Revoke the old key immediately:**
   - Go to: https://console.cloud.google.com/apis/credentials
   - Find your API key
   - Click the 3 dots → Delete
   - Confirm deletion

2. **Create a new API key:**
   - Follow the setup guide in `GOOGLE_PLACES_SETUP.md`
   - Create new restricted key
   - Update `Config.swift` locally

3. **Remove from Git:**
   ```bash
   git rm --cached Config.swift
   git commit -m "Remove exposed API key"
   git push
   ```

4. **Optional: Clean Git history:**
   ```bash
   # This removes the key from ALL commit history
   # WARNING: Rewrites history, requires force push
   git filter-branch --force --index-filter \
     "git rm --cached --ignore-unmatch Config.swift" \
     --prune-empty --tag-name-filter cat -- --all
   
   git push origin --force --all
   ```

---

## ✅ Proper Setup for New Contributors

If someone else clones this project:

### 1. Copy the template
```bash
cp Config.swift.template Config.swift
```

### 2. Add your API keys
Open `Config.swift` and replace:
```swift
static let googlePlacesAPIKey = "YOUR_GOOGLE_PLACES_API_KEY_HERE"
```

With your actual key:
```swift
static let googlePlacesAPIKey = "AIzaSy..."
```

### 3. Verify it's ignored
```bash
git status
# Config.swift should NOT appear
```

---

## 🔍 How to Check if You're Safe

### Before committing:
```bash
git status
```
**Config.swift should NOT appear in the list**

### Before pushing:
```bash
git log --all -- Config.swift
```
**Should show "No commits" or only the removal commit**

### Check .gitignore is working:
```bash
git check-ignore Config.swift
```
**Should output:** `Config.swift` (means it's ignored)

---

## 📋 Checklist

- [ ] `.gitignore` file created (includes `Config.swift`)
- [ ] `Config.swift.template` committed (safe, no real keys)
- [ ] `Config.swift` is in `.gitignore`
- [ ] `Config.swift` never added to Git
- [ ] If exposed: Old API key revoked
- [ ] If exposed: New API key created
- [ ] Verified with `git status` (Config.swift not showing)

---

## 🎯 What's Safe to Commit

✅ **Safe to commit:**
- `.gitignore`
- `Config.swift.template`
- All other source files
- `GoogleService-Info.plist` is also in `.gitignore` (Firebase config)

❌ **Never commit:**
- `Config.swift` (has real API keys)
- `GoogleService-Info.plist` (Firebase credentials)
- Any files with secrets/passwords

---

## 💡 Best Practices Going Forward

### For this project:
1. Always use `Config.swift` locally (ignored by Git)
2. Share `Config.swift.template` with team
3. Each developer gets their own API keys
4. Keep API keys restricted to your bundle ID

### For production apps:
Consider these alternatives:
- **Environment variables** (CI/CD)
- **Secret management service** (AWS Secrets Manager, etc.)
- **Backend proxy** (Firebase Functions calls Google API)
- **Xcode schemes** (different configs per scheme)

---

## 🆘 Emergency: Key Was Exposed

**If your API key was pushed to GitHub:**

1. ✅ **Immediately revoke** in Google Cloud Console
2. ✅ **Create new key** with restrictions
3. ✅ **Remove from Git** (see Option 3 above)
4. ✅ **Monitor billing** for unusual activity
5. ✅ **Set budget alerts** at $5, $10, $20

**GitHub will likely auto-detect and send you a warning email!**

---

## 📞 Questions?

- Setup guide: `GOOGLE_PLACES_SETUP.md`
- Security best practices: Search "securing API keys iOS"
- Git help: https://git-scm.com/docs

---

**Your current API key in Config.swift is:**
```
AIzaSyA0Z1I5q9yrgSDBVzW0iGkpDBOBbHwjoAM
```

**Status:** ⚠️ Currently in your local file  
**Next step:** Make sure `.gitignore` is working before committing!

Run: `git status` and verify Config.swift doesn't appear.
