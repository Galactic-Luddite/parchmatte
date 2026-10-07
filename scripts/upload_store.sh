#!/bin/bash
# Archive the Store build from the current checkout and upload it to App
# Store Connect. Uploading adds a build; it never submits for review and
# never changes which build a version has selected.
#
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=/path/AuthKey_<id>.p8 \
#     scripts/upload_store.sh              # archive, export, upload
#     scripts/upload_store.sh --export-only  # signed .pkg in the work dir, no upload
#
# The same three variables drive scripts/asc_api.py. The key needs a role
# that may manage certificates (Admin), because the export asks Xcode to
# create the distribution certificate and profile on demand.
#
# Run it from the commit being released, with a clean tree: the archive is
# evidence only for the commit it was built from.
set -euo pipefail

cd "$(dirname "$0")/.."

dest=upload
[ "${1:-}" = "--export-only" ] && dest=export

for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
    [ -n "${!v:-}" ] || { echo "missing environment variable $v" >&2; exit 2; }
done
key="$ASC_KEY_PATH"; case $key in "~"*) key="$HOME${key#\~}" ;; esac
[ -r "$key" ] || { echo "cannot read $key" >&2; exit 2; }

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "working tree has uncommitted changes; commit or stash first" >&2
    exit 2
fi

# The team is the certificate's organizational unit and the project's
# DEVELOPMENT_TEAM. It is not the suffix in the certificate's display name;
# that one fails with "No App Store Connect access for the team".
team=$(sed -n 's/^ *DEVELOPMENT_TEAM: *//p' project.yml | head -1)
[ -n "$team" ] || { echo "no DEVELOPMENT_TEAM in project.yml" >&2; exit 2; }

work="${PARCHMATTE_UPLOAD_DIR:-$(mktemp -d)}"
mkdir -p "$work"
auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$key"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

cat > "$work/export-options.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$dest</string>
<key>teamID</key><string>$team</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
EOF

xcodegen generate >/dev/null
rm -rf "$work/Parchmatte.xcarchive" "$work/export"
if ! xcodebuild -project Parchmatte.xcodeproj -scheme Parchmatte \
        -configuration Release archive \
        -archivePath "$work/Parchmatte.xcarchive" "${auth[@]}" \
        > "$work/archive.log" 2>&1; then
    tail -30 "$work/archive.log"; echo "archive failed; log: $work/archive.log" >&2; exit 1
fi

app="$work/Parchmatte.xcarchive/Products/Applications/Parchmatte.app"
echo "commit:       $(git rev-parse HEAD)"
echo "version:      $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist") ($(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist"))"
echo "entitlements: $(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - | grep -c '=>') key(s)"
codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p - | grep '=>'
echo "executable:   $(shasum -a 256 "$app/Contents/MacOS/Parchmatte" | cut -c1-64)"

if ! xcodebuild -exportArchive -archivePath "$work/Parchmatte.xcarchive" \
        -exportPath "$work/export" \
        -exportOptionsPlist "$work/export-options.xml" "${auth[@]}" \
        > "$work/export.log" 2>&1; then
    grep -v -F "$ASC_ISSUER_ID" "$work/export.log" | tail -30
    echo "export failed; log: $work/export.log" >&2; exit 1
fi

if [ "$dest" = upload ]; then
    echo "uploaded; Apple processes the build for a few minutes before it is selectable"
else
    echo "exported to $work/export"
fi
echo "work dir:     $work"
