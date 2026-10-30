#!/bin/bash
# 通过 GitHub Git Data API 推送本地提交（绕过被墙的 git https 通道）
set -e
REPO="myafer/iXcode"
BASE_SHA="9f9a079b0217790b23baaff1bc4933d38c08bf33"
cd /Users/jojo/WorkBuddy/2026-10-29-13-44-17/XcodeRecents

FILES="Resources/AppIcon.icns
Resources/AppIcon.iconset/icon_128x128.png
Resources/AppIcon.iconset/icon_16x16.png
Resources/AppIcon.iconset/icon_16x16@2x.png
Resources/AppIcon.iconset/icon_256x256.png
Resources/AppIcon.iconset/icon_32x32.png
Resources/AppIcon.iconset/icon_32x32@2x.png
Resources/AppIcon.iconset/icon_512x512.png
Resources/AppIcon.iconset/icon_512x512@2x.png
Resources/AppIcon.png
Resources/Info.plist
scripts/compose_icon.swift"

echo "== base tree =="
BASE_TREE=$(gh api "repos/$REPO/git/commits/$BASE_SHA" --jq .tree.sha)
echo "$BASE_TREE"

echo "== create blobs =="
TREE_ENTRIES="[]"
for f in $FILES; do
  B64=$(base64 < "$f" | tr -d '\n')
  printf '{"content":"%s","encoding":"base64"}' "$B64" > /tmp/blob_$$.json
  BLOB_SHA=$(gh api "repos/$REPO/git/blobs" --input /tmp/blob_$$.json --jq .sha)
  rm -f /tmp/blob_$$.json
  echo "  blob $BLOB_SHA  $f"
  TREE_ENTRIES=$(jq -cn --argjson t "$TREE_ENTRIES" --arg p "$f" --arg s "$BLOB_SHA" \
    '$t + [{path:$p, mode:"100644", type:"blob", sha:$s}]')
done

echo "== create tree =="
NEW_TREE=$(jq -n --arg b "$BASE_TREE" --argjson t "$TREE_ENTRIES" '{base_tree:$b, tree:$t}' | \
  gh api "repos/$REPO/git/trees" --input - --jq .sha)
echo "$NEW_TREE"

echo "== create commit =="
NEW_COMMIT=$(jq -n --arg m "feat: replace app icon with user-provided colorful hammer design" \
  --arg t "$NEW_TREE" --arg p "$BASE_SHA" \
  '{message:$m, tree:$t, parents:[$p]}' | \
  gh api "repos/$REPO/git/commits" --input - --jq .sha)
echo "$NEW_COMMIT"

echo "== update main =="
gh api "repos/$REPO/git/refs/heads/main" -X PATCH -f sha="$NEW_COMMIT" --jq .object.sha

echo "== create tag v2.5 =="
gh api "repos/$REPO/git/refs" -f ref="refs/tags/v2.5" -f sha="$NEW_COMMIT" --jq .object.sha 2>/dev/null \
  || gh api "repos/$REPO/git/refs/tags/v2.5" -X PATCH -f sha="$NEW_COMMIT" --jq .object.sha

echo "== DONE: $NEW_COMMIT =="
