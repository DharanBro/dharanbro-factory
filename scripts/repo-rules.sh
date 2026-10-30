#!/usr/bin/env bash
# repo-rules.sh <task> <repo> | --self-test
# Who must approve this branch's PR, as facts instead of trial and error. Writes artifacts/approvals-<repo>.md:
#   base branch protection (or "not readable without admin") and rulesets; CODEOWNERS owners matching the diff;
#   approver list files (*approvers*.txt); whether approval workflows' path scopes cover the diff; org secrets the
#   workflows reference. First line: "Needs approval from: ..." (factory-pr copies it into prs.md).
# An approval workflow is one whose file name contains "approv"; its string inputs with "path" in the key are read
# as path regexes, and inputs naming an approvers file are listed.
# CODEOWNERS, approver files and approval workflows are read from origin/<base>: GitHub applies the base's.
# shellcheck disable=SC2016  # the ruby and jq programs are single-quoted on purpose
. "$(dirname "$0")/lib.sh"

# analyze <diff-files> <codeowners-file|""> <base-workflows-dir> <branch-workflows-dir>
# Prints "owners: <a b>", "auto: <summary>", then markdown sections.
analyze() {
  ruby -ryaml -e '
    diff = File.readlines(ARGV[0], chomp: true).reject(&:empty?)
    flags = File::FNM_PATHNAME | File::FNM_DOTMATCH
    # GitHub CODEOWNERS glob: leading / anchors at root, no inner / matches at any depth, trailing / = dir only.
    co_match = lambda do |pat, path|
      p = pat.sub(%r{\A/}, ""); dir = p.end_with?("/"); p = p.chomp("/")
      p = "**/" + p unless pat.start_with?("/") || p.include?("/")
      (dir ? [] : [p]).push(p + "/**/*").any? { |q| File.fnmatch(q, path, flags) }
    end
    out = []; owners = []
    if ARGV[1].to_s != "" && File.exist?(ARGV[1])
      rules = File.readlines(ARGV[1]).map(&:strip).reject { |l| l.empty? || l.start_with?("#") }.map { |l| l.split(/\s+/) }
      per = diff.map { |f| r = rules.reverse.find { |pat, *| co_match.(pat, f) }; [f, r ? r.drop(1) : []] }
      owners = per.flat_map(&:last).uniq
      out << "## CODEOWNERS matching the diff"
      per.group_by(&:last).each do |o, fs|
        out << "- #{o.empty? ? "no owner" : o.join(" ")}: #{fs.size} file(s) (#{fs.map(&:first).first(5).join(", ")}#{fs.size > 5 ? ", ..." : ""})"
      end
    else
      out << "## CODEOWNERS matching the diff" << "- no CODEOWNERS file on the base branch"
    end
    out << "" << "## Approval workflow path scopes (base workflows)"
    walk = lambda { |o, &b| o.is_a?(Hash) ? o.each { |k, v| b.(k, v); walk.(v, &b) } : o.is_a?(Array) ? o.each { |v| walk.(v, &b) } : nil }
    auto = []
    Dir.glob(File.join(ARGV[2], "*approv*.y{a,}ml"), File::FNM_CASEFOLD).sort.each do |f|
      walk.(YAML.safe_load(File.read(f), aliases: true) || {}) do |k, v|
        next unless k.is_a?(String) && v.is_a?(String)
        if k =~ /approvers?[-_]?file/i
          out << "- #{File.basename(f)} `#{k}`: #{v}"
        elsif k =~ /path/i
          re = (Regexp.new(v) rescue next); miss = diff.reject { |d| re.match?(d) }
          auto << k if miss.empty? && !diff.empty?
          out << "- #{File.basename(f)} `#{k}`: " + (miss.empty? ? "covers all #{diff.size} file(s)" : "does not cover #{miss.size}/#{diff.size} (#{miss.first(5).join(", ")})")
        end
      end
    end
    out << "- none found" if out.last.start_with?("## Approval")
    secrets = Dir.glob(File.join(ARGV[3], "*.y{a,}ml")).flat_map { |f| File.read(f).scan(/secrets\.([A-Za-z_][A-Za-z0-9_]*)/).flatten }.uniq.sort - ["GITHUB_TOKEN"]
    out << "" << "## Secrets referenced by workflows (check visibility for new repos)"
    out << (secrets.empty? ? "- none" : "- #{secrets.join(", ")}: org secrets must be visible to this repo; a new repo is often not on their allow-list")
    puts "owners:#{owners.map { |o| " " + o }.join}"
    puts "auto: #{auto.empty? ? "does not cover the diff" : "covers the whole diff via #{auto.uniq.join(", ")}"}"
    puts out' "$@"
}

self_test() {
  local d fail=0 got
  d=$(mktemp -d); mkdir -p "$d/base" "$d/branch"
  printf '%s\n' infra/a.yaml infra/b.yaml docs/x.md .github/workflows/ci.yml > "$d/diff"
  printf '%s\n' '* @org/all' '/infra/ @org/infra' 'docs/ @org/docs' '*.md @org/writers' > "$d/CODEOWNERS"
  cat > "$d/base/auto-approve.yml" <<'EOF'
on: pull_request_target
jobs:
  call:
    with:
      paths-regex: '(^|/)infra/'
      approvers-file: .github/APPROVERS.txt
EOF
  printf 'jobs:\n  a:\n    steps:\n      - run: echo ${{ secrets.NPM_TOKEN }} ${{ secrets.GITHUB_TOKEN }}\n' > "$d/branch/ci.yml"
  got=$(analyze "$d/diff" "$d/CODEOWNERS" "$d/base" "$d/branch")
  want='owners: @org/infra @org/writers @org/all
auto: does not cover the diff
## CODEOWNERS matching the diff
- @org/infra: 2 file(s) (infra/a.yaml, infra/b.yaml)
- @org/writers: 1 file(s) (docs/x.md)
- @org/all: 1 file(s) (.github/workflows/ci.yml)

## Approval workflow path scopes (base workflows)
- auto-approve.yml `paths-regex`: does not cover 2/4 (docs/x.md, .github/workflows/ci.yml)
- auto-approve.yml `approvers-file`: .github/APPROVERS.txt

## Secrets referenced by workflows (check visibility for new repos)
- NPM_TOKEN: org secrets must be visible to this repo; a new repo is often not on their allow-list'
  if [ "$got" = "$want" ]; then echo "ok   analyze"; else printf 'FAIL analyze\n--- got\n%s\n--- want\n%s\n' "$got" "$want"; fail=1; fi
  printf '%s\n' infra/a.yaml > "$d/diff"
  got=$(analyze "$d/diff" "" "$d/base" "$d/branch" | sed -n '1,2p;4p')
  want='owners:
auto: covers the whole diff via paths-regex
- no CODEOWNERS file on the base branch'
  if [ "$got" = "$want" ]; then echo "ok   auto-covers"; else printf 'FAIL auto-covers\n--- got\n%s\n--- want\n%s\n' "$got" "$want"; fail=1; fi
  rm -rf "$d"; return $fail
}

[ "${1:-}" = --self-test ] && { self_test; exit; }
task="${1:?task}"; repo="${2:?repo}"
wt="$ROOT/tasks/$task/$repo"; out="$ROOT/tasks/$task/artifacts/approvals-$repo.md"
[ -d "$wt" ] || { echo "no worktree $wt" >&2; exit 1; }
base=$(repos_json | jq -r --arg r "$repo" '.repos[$r].branch // "main"')
slug=$(git -C "$wt" remote get-url origin | sed -E 's#^(git@[^:]+:|https?://[^/]+/)##; s#\.git$##')
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT; mkdir -p "$tmp/base" "$tmp/branch"
git -C "$wt" fetch -q origin "$base" || true
git -C "$wt" diff --name-only "origin/$base...HEAD" > "$tmp/diff"
co=""; for p in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
  git -C "$wt" show "origin/$base:$p" > "$tmp/CODEOWNERS" 2>/dev/null && { co="$tmp/CODEOWNERS"; break; }
done
git -C "$wt" archive "origin/$base" .github/workflows 2>/dev/null | tar -x -C "$tmp/base" 2>/dev/null || true
[ -d "$tmp/base/.github/workflows" ] && mv "$tmp/base/.github/workflows"/* "$tmp/base/" 2>/dev/null
[ -d "$wt/.github/workflows" ] && cp "$wt/.github/workflows"/*.y*ml "$tmp/branch/" 2>/dev/null
analyze "$tmp/diff" "$co" "$tmp/base" "$tmp/branch" > "$tmp/an"

reviews=""; codeowner=""
{
  echo "## Base branch \`$base\` protection"
  if p=$(gh api "repos/$slug/branches/$base/protection" 2>&1); then
    reviews=$(jq -r '.required_pull_request_reviews.required_approving_review_count // 0' <<<"$p")
    codeowner=$(jq -r '.required_pull_request_reviews.require_code_owner_reviews // false' <<<"$p")
    jq -r '"- required approving reviews: \(.required_pull_request_reviews.required_approving_review_count // 0)",
           "- code-owner review required: \(.required_pull_request_reviews.require_code_owner_reviews // false)",
           "- required checks: \((.required_status_checks.contexts // []) | join(", "))"' <<<"$p"
  else
    echo "- not readable without admin, or no classic protection ($(tail -n1 <<<"$p" | cut -c1-120))"
  fi
  if r=$(gh api "repos/$slug/rules/branches/$base" 2>&1); then
    jq -r 'if length == 0 then "- rulesets: none" else .[] |
      if .type == "pull_request" then "- ruleset: \(.parameters.required_approving_review_count) approving review(s), code-owner review \(.parameters.require_code_owner_review)"
      elif .type == "required_status_checks" then "- ruleset required checks: \([.parameters.required_status_checks[].context] | join(", "))"
      else "- ruleset: \(.type)" end end' <<<"$r"
    rv=$(jq -r '[.[] | select(.type == "pull_request") | .parameters.required_approving_review_count] | max // empty' <<<"$r")
    [ -n "$rv" ] && { [ -z "$reviews" ] || [ "$rv" -gt "$reviews" ]; } && reviews=$rv
    [ "$(jq -r 'any(.[]; .type == "pull_request" and .parameters.require_code_owner_review)' <<<"$r")" = true ] && codeowner=true
  else
    echo "- rulesets not readable ($(tail -n1 <<<"$r" | cut -c1-120))"
  fi
  echo; tail -n +3 "$tmp/an"
  echo; echo "## Approver list files (origin/$base)"
  files=$(git -C "$wt" ls-tree -r --name-only "origin/$base" | grep -iE '(^|/)[^/]*approvers[^/]*\.txt$' || true)
  if [ -z "$files" ]; then echo "- none"; else
    while IFS= read -r f; do echo "- \`$f\`: $(git -C "$wt" show "origin/$base:$f" | grep -v '^\s*#' | grep . | paste -sd ' ' -)"; done <<<"$files"
  fi
} > "$tmp/body"
owners=$(sed -n '1s/^owners: *//p' "$tmp/an"); auto=$(sed -n '2s/^auto: //p' "$tmp/an")
{
  echo "Needs approval from: ${owners:-no CODEOWNERS owner}; approving reviews required: ${reviews:-unknown}; code-owner review required: ${codeowner:-unknown}; auto-approve: $auto"
  echo; echo "# Approval facts: $slug ($(wc -l < "$tmp/diff" | tr -d ' ') changed files vs origin/$base)"; echo
  cat "$tmp/body"
} > "$out"
head -1 "$out"
