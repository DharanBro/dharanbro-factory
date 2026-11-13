#!/usr/bin/env bash
# cr-enabled.sh <repo>   prints true|false: whether repos.yml has `coderabbit: true` for the repo (default off).
. "$(dirname "$0")/lib.sh"
repos_json | jq -r --arg r "${1:?repo}" '.repos[$r].coderabbit == true'
