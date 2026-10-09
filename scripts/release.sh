#!/usr/bin/env bash
# scripts/release.sh — decide the next version from CHANGELOG.md and apply it.
#
# The `## Unreleased` section is the release's input. Its `###` headings say
# how far the version moves:
#
#   ### Breaking   → major
#   ### Added      → minor
#   anything else  → patch      (### Changed, ### Fixed, or loose bullets)
#   empty          → patch      (a lockstep bump: the note says so)
#
# Usage:
#   scripts/release.sh --bump auto|major|minor|patch [--version <x.y.z>]
#        [--app-sha <sha>] [--changed true|false] [--note "<bullet>"]...
#        [--notes-out <file>] [--dry-run]
#   scripts/release.sh --notes-for <version> [--notes-out <file>]
#        (print the changelog entry of an already-bumped version; used when a
#         previous run merged the bump but failed before releasing)
#
# What it writes (unless --dry-run): CHANGELOG.md (Unreleased → the new
# version), pubspec.yaml's version and ios/revnix_flutter.podspec's s.version.
# Each --note becomes a bullet under `### Changed` in the new entry. In
# Actions it sets current / next / level / lockstep / summary on
# $GITHUB_OUTPUT.

set -euo pipefail

PUBSPEC="pubspec.yaml"
PODSPEC="ios/revnix_flutter.podspec"
CHANGELOG="CHANGELOG.md"

bump="auto"
wanted=""
app_sha=""
changed=""
notes_out=""
notes_for=""
dry_run=""
extra_notes=()

while [ $# -gt 0 ]; do
  case "$1" in
    --bump) bump="$2"; shift 2 ;;
    --version) wanted="$2"; shift 2 ;;
    --app-sha) app_sha="$2"; shift 2 ;;
    --changed) changed="$2"; shift 2 ;;
    --note) extra_notes+=("$2"); shift 2 ;;
    --notes-out) notes_out="$2"; shift 2 ;;
    --notes-for) notes_for="$2"; shift 2 ;;
    --dry-run) dry_run=1; shift ;;
    *) echo "release.sh: unknown argument $1" >&2; exit 1 ;;
  esac
done

fail() { echo "release.sh: $*" >&2; exit 1; }

pubspec_version() { sed -n 's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$PUBSPEC"; }
podspec_version() { sed -n "s/^[[:space:]]*s\.version[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p" "$PODSPEC"; }

# Print the body of a "## <version>" entry, stopping at the next "## ".
entry_for() {
  awk -v want="## $1" '
    $0 == want { found = 1; next }
    found && /^## / { exit }
    found { print }
  ' "$CHANGELOG" | sed -e '/./,$!d' | awk 'BEGIN { blank = 0 }
    /^[[:space:]]*$/ { blank++; next }
    { while (blank-- > 0) print ""; blank = 0; print }'
}

release_notes() {
  printf '%s\n' "$1" | sed \
    -e 's/^### Breaking$/## ⚠️ Breaking/' \
    -e 's/^### Removed$/## 🗑️ Removed/' \
    -e 's/^### Added$/## ✨ Added/' \
    -e 's/^### Changed$/## 🔧 Changed/' \
    -e 's/^### Fixed$/## 🐛 Fixed/'
  if [ -n "$2" ] && git rev-parse -q --verify "refs/tags/v$2" >/dev/null 2>&1; then
    printf '\n**Full Changelog**: https://github.com/Oth-tech/RevnixSDK-Flutter/compare/v%s...v%s\n' "$2" "$3"
  fi
}

previous_version() {
  awk -v want="$1" '
    found && /^## [0-9]/ { sub(/^## /, ""); sub(/ .*/, ""); print; exit }
    index($0, "## " want) == 1 { found = 1 }
  ' "$CHANGELOG"
}

# --notes-for: an earlier run already bumped and landed; just re-read its entry.
if [ -n "$notes_for" ]; then
  [ -f "$CHANGELOG" ] || fail "no $CHANGELOG"
  heading=$(grep -m1 "^## $notes_for\( \|$\)" "$CHANGELOG" || true)
  [ -n "$heading" ] || fail "$CHANGELOG has no \"## $notes_for\" entry"
  body=$(entry_for "${heading#\#\# }")
  notes=$(release_notes "$body" "$(previous_version "$notes_for")" "$notes_for")
  [ -n "$notes_out" ] && printf '%s\n' "$notes" > "$notes_out"
  printf '%s\n' "$notes"
  exit 0
fi

case "$bump" in
  auto|major|minor|patch) ;;
  *) fail "--bump must be auto|major|minor|patch, got $bump" ;;
esac
if [ -n "$wanted" ]; then
  echo "$wanted" | grep -qE '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' \
    || fail "--version must be x.y.z, got $wanted"
fi

[ -f "$PUBSPEC" ] || fail "no $PUBSPEC"
[ -f "$PODSPEC" ] || fail "no $PODSPEC"
[ -f "$CHANGELOG" ] || fail "no $CHANGELOG"
grep -q '^## Unreleased$' "$CHANGELOG" || fail "$CHANGELOG has no \"## Unreleased\" heading"

current=$(pubspec_version)
[ -n "$current" ] || fail "could not read version from $PUBSPEC"
echo "$current" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || fail "$PUBSPEC version $current is not x.y.z"

# The podspec must already agree with the pubspec, or the bump would silently
# paper over a drift that shipped in the last release.
pod_version=$(podspec_version)
[ "$pod_version" = "$current" ] \
  || fail "$PODSPEC says $pod_version but $PUBSPEC says $current — reconcile them first"

unreleased=$(entry_for "Unreleased")

count_under() {
  printf '%s\n' "$unreleased" | awk -v want="### $1" '
    $0 ~ "^### " { active = ($0 == want); next }
    active && /^[[:space:]]*-/ { n++ }
    END { print n + 0 }'
}
total_bullets=$(printf '%s\n' "$unreleased" | grep -cE '^[[:space:]]*-' || true)
breaking=$(count_under "Breaking")
added=$(count_under "Added")

if [ "$bump" != "auto" ]; then
  level="$bump"
elif [ "$breaking" -gt 0 ]; then
  level="major"
elif [ "$added" -gt 0 ]; then
  level="minor"
else
  level="patch"
fi

major=${current%%.*}
rest=${current#*.}
minor=${rest%%.*}
patch=${rest#*.}
case "$level" in
  major) next="$((major + 1)).0.0" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  patch) next="$major.$minor.$((patch + 1))" ;;
esac

if [ -n "$wanted" ]; then
  highest=$(printf '%s\n%s\n' "$current" "$wanted" | sort -V | tail -1)
  [ "$wanted" != "$current" ] && [ "$highest" = "$wanted" ] \
    || fail "--version $wanted is not above $current"
  IFS=. read -r wmajor wminor _ <<< "$wanted"
  if [ "$wmajor" != "$major" ]; then level="major"
  elif [ "$wminor" != "$minor" ]; then level="minor"
  else level="patch"; fi
  next="$wanted"
fi

# A release with nothing recorded under Unreleased is a lockstep bump: the
# SDKs track revnix-app releases even when their own code did not move.
lockstep=false
body=$(printf '%s\n' "$unreleased" | sed -e '/./,$!d')
if [ "$total_bullets" -eq 0 ] && [ ${#extra_notes[@]} -eq 0 ]; then
  lockstep=true
  if [ "$changed" = "true" ]; then
    body="Changes since $current were not recorded here; see the commit log."
  else
    ride=""
    [ -n "$app_sha" ] && ride=" ${app_sha:0:7}"
    body="No SDK changes. Version moved in lockstep with revnix-app release${ride}; the package contents are identical to $current."
  fi
fi

if [ ${#extra_notes[@]} -gt 0 ]; then
  bullets=$(printf -- '- %s\n' "${extra_notes[@]}")
  body=$(printf '%s\n' "$body" | add="$bullets" awk '
    { line[NR] = $0 }
    /^### / { active = ($0 == "### Changed") }
    active && NF { at = NR }
    END {
      for (i = 1; i <= NR; i++) { print line[i]; if (i == at) print ENVIRON["add"] }
      if (!at) { print ""; print "### Changed"; print ""; print ENVIRON["add"] }
    }' | sed -e '/./,$!d')
fi

summary="$level bump, ${total_bullets} changelog bullet(s), lockstep=$lockstep"

if [ -n "$notes_out" ]; then
  release_notes "$body" "$current" "$next" > "$notes_out"
fi

if [ -z "$dry_run" ]; then
  # CHANGELOG: turn Unreleased into the version entry, leave a fresh Unreleased.
  tmp=$(mktemp)
  {
    awk '/^## Unreleased/ { exit } { print }' "$CHANGELOG"
    printf '## Unreleased\n\n## %s\n\n' "$next"
    printf '%s\n\n' "$body"
    awk 'skip { print } /^## Unreleased/ { skip = 1; next }' "$CHANGELOG" \
      | awk 'found { print; next } /^## / { found = 1; print }'
  } > "$tmp"
  mv "$tmp" "$CHANGELOG"

  # Version lives in two files; both move together or the release is a lie.
  perl -pi -e "s/^version:\s*\S+/version: $next/" "$PUBSPEC"
  perl -0pi -e "s/(s\.version\s*=\s*')[^']*(')/\${1}$next\${2}/" "$PODSPEC"
fi

echo "$current -> $next ($summary)"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "current=$current"
    echo "next=$next"
    echo "level=$level"
    echo "lockstep=$lockstep"
    echo "summary=$summary"
  } >> "$GITHUB_OUTPUT"
fi
