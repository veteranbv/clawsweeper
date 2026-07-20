#!/usr/bin/env bash
set -euo pipefail

repo="${PROOF_REPO:?}"
pr="${PROOF_PR:?}"
mode="${PROOF_MODE:?}"
run_url="${PROOF_RUN_URL:?}"
gold='rating: 🦐 gold shrimp'
platinum='rating: 🐚 platinum hermit'
churn='proof-fixture: synthetic churn'
mkdir -p proof-output

head_sha="$(gh api "repos/$repo/pulls/$pr" --jq .head.sha)"

ensure_label() {
  local name="$1" color="$2"
  gh label create "$name" --repo "$repo" --color "$color" --force >/dev/null
}

post_issue_comment() {
  local body="$1"
  gh api --method POST "repos/$repo/issues/$pr/comments" -f body="$body" >/dev/null
}

post_inline_comment() {
  local body="$1" line="$2"
  gh api --method POST "repos/$repo/pulls/$pr/comments" \
    -f body="$body" \
    -f commit_id="$head_sha" \
    -f path='proof/live-label-sync-fixture.txt' \
    -F line="$line" \
    -f side='RIGHT' >/dev/null
}

toggle_churn() {
  gh issue edit "$pr" --repo "$repo" --add-label "$churn" >/dev/null
  gh issue edit "$pr" --repo "$repo" --remove-label "$churn" >/dev/null
}

count_paginated() {
  local endpoint="$1"
  gh api --paginate "$endpoint?per_page=100" --slurp | jq 'add | length'
}

snapshot() {
  local action_report="${1:-}"
  local labels issue_comments timeline_events inline_comments executed_sha
  executed_sha="$(git -C sut rev-parse HEAD 2>/dev/null || printf 'not-applicable')"
  labels="$(gh pr view "$pr" --repo "$repo" --json labels --jq '[.labels[].name] | sort')"
  issue_comments="$(count_paginated "repos/$repo/issues/$pr/comments")"
  timeline_events="$(count_paginated "repos/$repo/issues/$pr/timeline")"
  inline_comments="$(count_paginated "repos/$repo/pulls/$pr/comments")"
  jq -n \
    --arg mode "$mode" \
    --arg repository "$repo" \
    --argjson pull_request "$pr" \
    --arg head_sha "$head_sha" \
    --arg executed_sha "$executed_sha" \
    --arg fixed_sha '12228184bbf34aab227c3e1f087eec9c4a8ed0fb' \
    --arg baseline_sha '846b73c666c01b1c29d8a65a93549fca5742b404' \
    --arg run_url "$run_url" \
    --argjson labels "$labels" \
    --argjson issue_comments "$issue_comments" \
    --argjson timeline_events "$timeline_events" \
    --argjson inline_review_comments "$inline_comments" \
    --slurpfile action_report "${action_report:-/dev/null}" \
    '{schema_version: 1, mode: $mode, repository: $repository, pull_request: $pull_request,
      head_sha: $head_sha, executed_sha: $executed_sha, fixed_sha: $fixed_sha,
      baseline_sha: $baseline_sha, run_url: $run_url,
      counts: {issue_comments: $issue_comments, timeline_events: $timeline_events,
        inline_review_comments: $inline_review_comments}, labels: $labels,
      action_report: ($action_report[0] // null)}' \
    | tee "proof-output/$mode.json"
}

case "$mode" in
  preseed)
    ensure_label "$gold" 'D4AF37'
    ensure_label "$platinum" 'E5E4E2'
    ensure_label "$churn" 'C5DEF5'
    gh issue edit "$pr" --repo "$repo" --remove-label "$platinum" >/dev/null 2>&1 || true
    gh issue edit "$pr" --repo "$repo" --add-label "$gold" >/dev/null
    for index in $(seq -w 1 26); do
      post_issue_comment "[synthetic proof] pre-review bot issue activity $index"
    done
    for index in $(seq -w 1 41); do
      line=$((10#$index + 5))
      post_inline_comment "[synthetic proof] pre-review bot inline activity $index" "$line"
    done
    for _ in $(seq 1 30); do toggle_churn; done
    snapshot
    ;;
  postreview)
    post_issue_comment '[synthetic proof] post-review bot issue activity'
    post_inline_comment '[synthetic proof] post-review bot inline activity' 100
    toggle_churn
    snapshot
    ;;
  posthuman)
    for index in $(seq -w 1 13); do
      post_issue_comment "[synthetic proof] guard-window bot issue activity $index"
    done
    post_inline_comment '[synthetic proof] guard-window bot inline activity' 99
    for _ in $(seq 1 30); do toggle_churn; done
    snapshot
    ;;
  apply-before|apply-after|apply-blocked)
    test -f "harness/proof/reports/$pr.md"
    mkdir -p proof-output/items proof-output/closed proof-output/plans
    cp "harness/proof/reports/$pr.md" "proof-output/items/$pr.md"
    args=(
      apply-decisions
      --target-repo "$repo"
      --items-dir proof-output/items
      --closed-dir proof-output/closed
      --plans-dir proof-output/plans
      --report-path "proof-output/$mode-action.json"
      --limit 10
      --processed-limit 1
      --close-delay-ms 0
      --sync-comments-only
      --comment-sync-min-age-days 0
      --item-numbers "$pr"
    )
    if [ "$mode" = 'apply-before' ]; then args+=(--dry-run); fi
    node sut/dist/clawsweeper.js "${args[@]}"
    snapshot "proof-output/$mode-action.json"
    ;;
  snapshot)
    snapshot
    ;;
  *)
    echo "unsupported proof mode: $mode" >&2
    exit 2
    ;;
esac
