#!/bin/bash
set -euo pipefail

# Tag and push a release version
# Usage: scripts/release.sh <version>
# Example: scripts/release.sh 1.0.0

VERSION="${1:-}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
if [[ -z "$VERSION" ]]; then
    echo "Usage: scripts/release.sh <version>"
    echo "Example: scripts/release.sh 1.0.0"
    exit 1
fi

# Validate version format
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version format: $VERSION"
    echo "Expected: X.Y.Z (e.g., 1.0.0)"
    exit 1
fi

TAG="v${VERSION}"
NOTES_FILE="docs/releases/${TAG}.md"
PUBLIC_NOTES_FILE="docs/releases/${TAG}-github.md"

BRANCH=$(git branch --show-current)
if [[ "$BRANCH" != "main" ]]; then
    echo "Release tags must be created from main; current branch is '${BRANCH:-detached HEAD}'."
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Commit and verify every release file before tagging."
    exit 1
fi

REMOTE_MAIN=$(git ls-remote --exit-code origin refs/heads/main | awk '{print $1}')
LOCAL_HEAD=$(git rev-parse HEAD)
if [[ -z "$REMOTE_MAIN" || "$LOCAL_HEAD" != "$REMOTE_MAIN" ]]; then
    echo "Local main is not the exact current origin/main commit."
    echo "Local:  $LOCAL_HEAD"
    echo "Remote: ${REMOTE_MAIN:-unavailable}"
    exit 1
fi

if [[ ! -f "$NOTES_FILE" ]]; then
    echo "Curated release notes are required at $NOTES_FILE"
    exit 1
fi
if [[ ! -f "$PUBLIC_NOTES_FILE" ]]; then
    echo "Public GitHub release notes are required at $PUBLIC_NOTES_FILE"
    exit 1
fi
if grep -Fq 'Status: **Draft' "$NOTES_FILE" ||
   grep -Fq 'Status: **Draft' "$PUBLIC_NOTES_FILE" ||
   grep -Fq -- '- [ ]' "$NOTES_FILE"; then
    echo "Release notes are still marked as draft or contain incomplete release gates."
    exit 1
fi

# Check if tag already exists
if git rev-parse --verify "refs/tags/$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists"
    exit 1
fi

# Show what will be tagged
echo "Creating release $TAG at $(git rev-parse --short HEAD)"
echo "Release notes: $NOTES_FILE"
echo ""
echo "Commits since last tag:"
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
if [[ -n "$LAST_TAG" ]]; then
    git log --oneline "$LAST_TAG..HEAD"
else
    git log --oneline -10
fi

echo ""
read -p "Tag and push $TAG? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

git tag -a "$TAG" -m "$TAG: verified release candidate"
git push origin "refs/tags/$TAG"

REMOTE_URL=$(git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||; s|\.git$||')
echo ""
echo "Pushed $TAG -- GitHub Actions will build and release."
echo "  Monitor: https://github.com/${REMOTE_URL}/actions"
