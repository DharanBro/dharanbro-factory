#!/usr/bin/env bash
# sync-repos.sh [repo...]   clone missing / fetch existing base clones listed in repos.yml
. "$(dirname "$0")/lib.sh"
names=("$@")
if [ ${#names[@]} -eq 0 ]; then
  while IFS= read -r n; do names+=("$n"); done < <(repos_json | jq -r '.repos|keys[]')
fi
for n in ${names[@]+"${names[@]}"}; do
  remote=$(repos_json | jq -r --arg n "$n" '.repos[$n].remote // empty')
  [ -n "$remote" ] || { echo "$n: not in repos.yml" >&2; continue; }
  if [ -d "$ROOT/repos/$n/.git" ]; then git -C "$ROOT/repos/$n" fetch -q --prune origin && echo "$n: fetched"
  else mkdir -p "$ROOT/repos" && git clone -q "$remote" "$ROOT/repos/$n" && echo "$n: cloned"; fi
done
