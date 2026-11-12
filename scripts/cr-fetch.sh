#!/usr/bin/env bash
# cr-fetch.sh <task> <repo> <pr-number> <round>
# Wait (token-free polling) for a CodeRabbit review of the PR's head commit (matched by sha: a slow review of an
# older commit can land after a newer push), then write all
# UNRESOLVED CodeRabbit threads to artifacts/coderabbit-<repo>-r<round>.md. Prints the count; exit 2 on timeout.
# Threads whose last comment is ours (fix pushed or reply posted), or is a CodeRabbit acknowledgement, are skipped.
# Also stops when CodeRabbit's status check on the head commit has completed. A paused-review notice (walkthrough
# comment edited after the head commit) gets one `@coderabbitai review` per head sha; CR_NO_POST=1 disables posting.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; repo="${2:?}"; pr="${3:?}"; round="${4:?}"
remote=$(repos_json | jq -r --arg r "$repo" '.repos[$r].remote')
slug=$(sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##' <<<"$remote"); owner="${slug%%/*}"; rname="${slug##*/}"
out="$ROOT/tasks/$task/artifacts/coderabbit-$repo-r$round.md"
Q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  commits(last:1){nodes{commit{oid committedDate statusCheckRollup{contexts(first:50){nodes{
    ... on StatusContext{context state} ... on CheckRun{name status conclusion}}}}}}}
  reviews(last:30){nodes{author{login} submittedAt commit{oid}}}
  comments(last:30){nodes{author{login} createdAt updatedAt body}}
  reviewThreads(first:100){nodes{isResolved path line comments(first:20){nodes{databaseId author{login} body}}
    last:comments(last:1){nodes{author{login} body}}}}}}}'
tmo=$(conf "$task" | jq -r '.caps.coderabbit_wait_min // 20'); deadline=$(( $(date +%s) + tmo * 60 ))
while :; do
  J=$(gh api graphql -f query="$Q" -F o="$owner" -F r="$rname" -F n="$pr")
  seen=$(jq '.data.repository.pullRequest as $p | ($p.commits.nodes[0].commit.oid) as $head
             | [$p.reviews.nodes[]|select(.author.login|startswith("coderabbitai"))|select(.commit.oid==$head)]|length' <<<"$J")
  # CodeRabbit may pause incremental reviews or answer "Already reviewed the last commit" without a new
  # review; then no newer review will ever come, so stop waiting and read the threads as they are.
  stalled=$(jq '.data.repository.pullRequest as $p | ($p.commits.nodes[0].commit.committedDate) as $lc
             | [$p.comments.nodes[]|select(.author.login|startswith("coderabbitai"))|select(.createdAt>$lc)
                |select(.body|test("Reviews paused|Already reviewed the last commit|Review finished"))]|length' <<<"$J")
  [ "$stalled" -gt 0 ] && break
  done_status=$(jq '[.data.repository.pullRequest.commits.nodes[0].commit.statusCheckRollup.contexts.nodes[]?
             | select((.context // .name // "")|test("coderabbit";"i"))
             | select((.state // "")|IN("SUCCESS","FAILURE","ERROR") or (.status // "") == "COMPLETED")]|length' <<<"$J")
  [ "$done_status" -gt 0 ] && break
  paused=$(jq '.data.repository.pullRequest as $p | ($p.commits.nodes[0].commit.committedDate) as $lc
             | [$p.comments.nodes[]|select(.author.login|startswith("coderabbitai"))|select(.updatedAt>$lc)|select(.body|test("Reviews paused"))]|length' <<<"$J")
  if [ "$paused" -gt 0 ]; then
    head=$(jq -r '.data.repository.pullRequest.commits.nodes[0].commit.oid' <<<"$J"); mark="$ROOT/tasks/$task/work/cr-review-requested-$repo-$pr.sha"
    if [ "$(cat "$mark" 2>/dev/null)" != "$head" ] && [ -z "${CR_NO_POST:-}" ]; then
      mkdir -p "$(dirname "$mark")"; echo "$head" > "$mark"
      gh pr comment "$pr" --repo "$owner/$rname" --body "@coderabbitai review" >/dev/null
    fi
  fi
  [ "$seen" -gt 0 ] && break
  [ "$(date +%s)" -gt "$deadline" ] && { echo TIMEOUT; exit 2; }
  sleep 30
done
jq -r '[.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved==false and (.comments.nodes[0].author.login|startswith("coderabbitai")))
        | select(.last.nodes[0].author.login|startswith("coderabbitai"))
        | select(.last.nodes[0].body|test("Review thread resolved|in a follow-up|mark this finding as addressed|I consider")|not)]
       | to_entries[] | "## \(.key+1). \(.value.path):\(.value.line // "?") (comment id \(.value.comments.nodes[0].databaseId))\n" + ([.value.comments.nodes[]|"**\(.author.login)**: \(.body[0:1500])"]|join("\n\n")) + "\n"' <<<"$J" > "$out"
grep -c '^## ' "$out" || true
