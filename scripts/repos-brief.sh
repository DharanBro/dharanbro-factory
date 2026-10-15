#!/usr/bin/env bash
# repos-brief.sh   "<name> [<type>]: <description>" per registered repo (cheap shortlist input)
. "$(dirname "$0")/lib.sh"
repos_json | jq -r '.repos|to_entries[]|"\(.key) [\(.value.type)]: \(.value.description // "-")"'
