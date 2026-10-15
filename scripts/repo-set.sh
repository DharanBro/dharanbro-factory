#!/usr/bin/env bash
# repo-set.sh <name> [--remote URL] [--branch B] [--type frontend|backend|library] [--desc TEXT]
#   [--install CMD] [--test CMD] [--lint CMD] [--typecheck CMD] [--dev-cmd CMD] [--dev-url URL]
#   [--ui-test-doc PATH] [--ci-check CMD]... (repeatable; replaces the list) [--coderabbit true|false]
#   [--sonar-key KEY] [--sonar-coverage-cmd CMD]  (sets the `sonar:` block; url defaults to the local factory-sonar)
# Upsert an entry in repos.yml (gitignored, local) and clone into repos/<name> if missing.
. "$(dirname "$0")/lib.sh"
name="${1:?repo name}"; shift
[[ "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "bad repo name '$name'" >&2; exit 1; }
while [ $# -gt 0 ]; do
  [ $# -ge 2 ] || { echo "missing value for $1" >&2; exit 1; }
  case "$1" in
    --remote) export R_remote="$2" ;;      --branch) export R_branch="$2" ;;
    --type) export R_type="$2" ;;          --desc) export R_description="$2" ;;
    --install) export R_install="$2" ;;    --test) export R_test="$2" ;;
    --lint) export R_lint="$2" ;;          --typecheck) export R_typecheck="$2" ;;
    --dev-cmd) export R_dev_cmd="$2" ;;    --dev-url) export R_dev_url="$2" ;;
    --ui-test-doc) export R_ui_test_doc="$2" ;;
    --ci-check) export R_ci_checks="${R_ci_checks:+$R_ci_checks$'\n'}$2" ;;  --coderabbit) export R_coderabbit="$2" ;;
    --sonar-key) export R_sonar_key="$2" ;;
    --sonar-coverage-cmd) export R_sonar_coverage_cmd="$2" ;;
    *) echo "unknown flag $1" >&2; exit 1 ;;
  esac; shift 2
done

upsert() {
  ruby -ryaml -e '
    f, name = ARGV
    h = File.exist?(f) ? (YAML.load_file(f) || {}) : {}
    h["repos"] ||= {}
    e = (h["repos"][name] ||= {})
    %w[remote branch type description install test lint typecheck dev_cmd dev_url ui_test_doc ci_checks coderabbit].each do |k|
      v = ENV["R_#{k}"]; next if v.nil? || v.empty?
      e[k] = (k == "coderabbit" ? v == "true" : k == "ci_checks" ? v.split("\n") : v)
    end
    if ENV["R_sonar_key"].to_s != "" || ENV["R_sonar_coverage_cmd"].to_s != ""
      sn = (e["sonar"] ||= {})
      sn["project_key"] = ENV["R_sonar_key"] unless ENV["R_sonar_key"].to_s.empty?
      sn["coverage_cmd"] = ENV["R_sonar_coverage_cmd"] unless ENV["R_sonar_coverage_cmd"].to_s.empty?
      sn["url"] ||= "http://localhost:9100"
    end
    abort "remote required for a new repo" unless e["remote"]
    e["type"] ||= "library"
    if ENV["DEFAULT_BRANCH"] && !e["branch"] then e["branch"] = ENV["DEFAULT_BRANCH"] end
    File.write(f, "# Local repo registry (gitignored). Edit freely or use /factory-add-repo.\n" + h.to_yaml.sub(/\A---\n/, ""))
  ' "$ROOT/repos.yml" "$name"
}

upsert
remote=$(repos_json | jq -r --arg n "$name" '.repos[$n].remote')
dest="$ROOT/repos/$name"
if [ ! -d "$dest/.git" ]; then
  mkdir -p "$ROOT/repos"
  git clone -q "$remote" "$dest" >&2
fi
if [ "$(repos_json | jq -r --arg n "$name" '.repos[$n].branch // ""')" = "" ]; then
  DEFAULT_BRANCH=$(git -C "$dest" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##' || true)
  export DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
  upsert
fi
repos_json | jq -c --arg n "$name" '.repos[$n]'
