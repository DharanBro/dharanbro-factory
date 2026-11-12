#!/usr/bin/env bash
# cr-fetch.sh with a stub gh (recorded JSON, no network): stops on a completed CodeRabbit status, skips
# acknowledged threads, posts one "@coderabbitai review" per head sha when the walkthrough was edited to "paused".
. "$(dirname "$0")/lib.sh"
R=$(fake_root cr-fetch.sh); B="$R/bin"; mkdir -p "$B" "$R/tasks/t/artifacts"
printf 'repos:\n  r: {remote: "git@github.com:o/r.git"}\n' > "$R/repos.yml"
printf '#!/usr/bin/env bash\n:\n' > "$B/sleep"
cat > "$B/gh" <<'EOF2'
#!/usr/bin/env bash
D=$(dirname "$0")
case "$1 $2" in
  "api graphql") cat "$D/resp-$(cat "$D/n" 2>/dev/null || echo 1).json"; if [ -f "$D/n" ]; then echo $(( $(cat "$D/n") + 1 )) > "$D/n"; fi ;;
  "pr comment") echo "$*" >> "$D/posted" ;;
esac
EOF2
chmod +x "$B/gh" "$B/sleep"
# status = SUCCESS, no review object; thread 1 last comment is an ack, thread 2 is open
cat > "$B/resp-1.json" <<'EOF2'
{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"oid":"h1","committedDate":"2026-01-01T00:00:00Z",
 "statusCheckRollup":{"contexts":{"nodes":[{"context":"CodeRabbit","state":"SUCCESS"}]}}}}]},
 "reviews":{"nodes":[]},"comments":{"nodes":[]},
 "reviewThreads":{"nodes":[
  {"isResolved":false,"path":"a.ts","line":1,"comments":{"nodes":[{"databaseId":1,"author":{"login":"coderabbitai"},"body":"bug"}]},"last":{"nodes":[{"author":{"login":"coderabbitai"},"body":"Understood. We can address this in a follow-up."}]}},
  {"isResolved":false,"path":"b.ts","line":2,"comments":{"nodes":[{"databaseId":2,"author":{"login":"coderabbitai"},"body":"bug2"}]},"last":{"nodes":[{"author":{"login":"coderabbitai"},"body":"still broken"}]}}]}}}}}
EOF2
run() { PATH="$B:$PATH" FACTORY_ROOT="$R" bash "$R/scripts/cr-fetch.sh" t r 5 x 2>&1; }
ok status-stop-ack-skipped "$(run)" 1
ok only-open-thread-listed "$(grep -c '^## .*b.ts' "$R/tasks/t/artifacts/coderabbit-r-rx.md")" 1
# paused: walkthrough edited after the head commit, no status yet; second poll has the status
cat > "$B/resp-2.json" <<'EOF2'
{"data":{"repository":{"pullRequest":{"commits":{"nodes":[{"commit":{"oid":"h1","committedDate":"2026-01-01T00:00:00Z","statusCheckRollup":{"contexts":{"nodes":[]}}}}]},
 "reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"coderabbitai"},"createdAt":"2025-12-01T00:00:00Z","updatedAt":"2026-01-02T00:00:00Z","body":"Reviews paused"}]},"reviewThreads":{"nodes":[]}}}}}
EOF2
cp "$B/resp-1.json" "$B/resp-3.json"; cp "$B/resp-2.json" "$B/resp-4.json"; echo 2 > "$B/n"
run >/dev/null
ok pause-posts-once "$(grep -c coderabbitai "$B/posted")" 1
ok pause-marker-sha "$(cat "$R/tasks/t/work/cr-review-requested-r-5.sha")" h1
finish
