#!/usr/bin/env bash
# cr-fetch.sh <task> <repo> <pr-number> <round>
# Wait (token-free polling) for a CodeRabbit review newer than the PR's last commit, then write all
# UNRESOLVED CodeRabbit threads to artifacts/coderabbit-<repo>-r<round>.md. Prints the count; exit 2 on timeout.
# Threads whose last comment is ours (fix pushed or reply posted) are skipped until CodeRabbit answers again.
. "$(dirname "$0")/lib.sh"
task="${1:?}"; repo="${2:?}"; pr="${3:?}"; round="${4:?}"
remote=$(repos_json | jq -r --arg r "$repo" '.repos[$r].remote')
slug=$(sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##' <<<"$remote"); owner="${slug%%/*}"; rname="${slug##*/}"
out="$ROOT/tasks/$task/artifacts/coderabbit-$repo-r$round.md"
Q='query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){pullRequest(number:$n){
  commits(last:1){nodes{commit{committedDate}}}
  reviews(last:30){nodes{author{login} submittedAt}}
  comments(last:10){nodes{author{login} createdAt body}}
  reviewThreads(first:100){nodes{isResolved path line comments(first:20){nodes{databaseId author{login} body}}
    last:comments(last:1){nodes{author{login}}}}}}}}'
tmo=$(conf "$task" | jq -r '.caps.coderabbit_wait_min // 20'); deadline=$(( $(date +%s) + tmo * 60 ))
while :; do
  J=$(gh api graphql -f query="$Q" -F o="$owner" -F r="$rname" -F n="$pr")
  seen=$(jq '.data.repository.pullRequest as $p | ($p.commits.nodes[0].commit.committedDate) as $lc
             | [$p.reviews.nodes[]|select(.author.login|startswith("coderabbitai"))|select(.submittedAt>$lc)]|length' <<<"$J")
  # CodeRabbit may pause incremental reviews or answer "Already reviewed the last commit" without a new
  # review; then no newer review will ever come, so stop waiting and read the threads as they are.
  stalled=$(jq '.data.repository.pullRequest as $p | ($p.commits.nodes[0].commit.committedDate) as $lc
             | [$p.comments.nodes[]|select(.author.login|startswith("coderabbitai"))|select(.createdAt>$lc)
                |select(.body|test("Reviews paused|Already reviewed the last commit"))]|length' <<<"$J")
  [ "$stalled" -gt 0 ] && break
  [ "$seen" -gt 0 ] && break
  [ "$(date +%s)" -gt "$deadline" ] && { echo TIMEOUT; exit 2; }
  sleep 30
done
jq -r '[.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved==false and (.comments.nodes[0].author.login|startswith("coderabbitai")))
        | select(.last.nodes[0].author.login|startswith("coderabbitai"))]
       | to_entries[] | "## \(.key+1). \(.value.path):\(.value.line // "?") (comment id \(.value.comments.nodes[0].databaseId))\n" + ([.value.comments.nodes[]|"**\(.author.login)**: \(.body[0:1500])"]|join("\n\n")) + "\n"' <<<"$J" > "$out"
grep -c '^## ' "$out" || true
