#!/usr/bin/env bash
# plan-meta.sh <task>   plan.md YAML front matter -> JSON: {repos:[...], waves:[{wave,repos}], frontend:[...], locked}
. "$(dirname "$0")/lib.sh"
f="$ROOT/tasks/${1:?task}/plan.md"
[ -f "$f" ] || { echo "no plan.md" >&2; exit 1; }
ruby -ryaml -rjson -e '
  t = File.read(ARGV[0]); m = t.match(/\A---\n(.*?)\n---\n/m) or abort "plan.md has no front matter"
  puts JSON.generate(YAML.safe_load(m[1]) || {})' "$f" |
jq '{locked:(.locked // false), repos:[.repos[].name],
     waves:(.repos|group_by(.wave // 1)|map({wave:(.[0].wave // 1),repos:map(.name)})|sort_by(.wave)),
     frontend:[.repos[]|select(.type=="frontend" and (.ui // true))|.name]}'
