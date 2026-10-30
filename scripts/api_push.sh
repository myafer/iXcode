#!/bin/bash
# 通过 GitHub Git Data API 推送本地提交（绕过被墙/代理异常的 git https 通道）
# 用法: api_push.sh <内容基准本地commit> <commit message> <tag名>
# 说明: 远端 main 由 API 创建时 SHA 与本地不同，故 base 取远端 main 当前 SHA（内容应与基准 commit 一致）
set -e
REPO="myafer/iXcode"
BASE_CONTENT="$1"
MESSAGE="$2"
TAG="$3"
cd /Users/jojo/WorkBuddy/2026-10-29-13-44-17/XcodeRecents

BASE_SHA=$(gh api "repos/$REPO/commits/main" --jq .sha)
BASE_TREE=$(gh api "repos/$REPO/git/commits/$BASE_SHA" --jq .tree.sha)
echo "remote main: $BASE_SHA  tree: $BASE_TREE"

FILES=$(git diff --name-only "$BASE_CONTENT" HEAD)
echo "== files =="
echo "$FILES"

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

NEW_TREE=$(jq -n --arg b "$BASE_TREE" --argjson t "$TREE_ENTRIES" '{base_tree:$b, tree:$t}' | \
  gh api "repos/$REPO/git/trees" --input - --jq .sha)

NEW_COMMIT=$(jq -n --arg m "$MESSAGE" --arg t "$NEW_TREE" --arg p "$BASE_SHA" \
  '{message:$m, tree:$t, parents:[$p]}' | \
  gh api "repos/$REPO/git/commits" --input - --jq .sha)
echo "commit: $NEW_COMMIT"

gh api "repos/$REPO/git/refs/heads/main" -X PATCH -f sha="$NEW_COMMIT" --jq .object.sha

# tag：存在则挪，不存在则建（TAG 传空则只推 main，不发版）
if [ -n "$TAG" ]; then
  gh api "repos/$REPO/git/refs/tags/$TAG" -X PATCH -f sha="$NEW_COMMIT" --jq .object.sha 2>/dev/null \
    || gh api "repos/$REPO/git/refs" -f ref="refs/tags/$TAG" -f sha="$NEW_COMMIT" --jq .object.sha
else
  echo "(no tag, main only)"
fi

echo "== DONE: $NEW_COMMIT =="
