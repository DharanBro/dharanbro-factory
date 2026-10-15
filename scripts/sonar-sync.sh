#!/usr/bin/env bash
# Mirror org SonarQube quality gate + quality profiles (rules) for every repo with a `sonar:` block in repos.yml
# into the local factory-sonar container. Org side: `sonar` CLI auth (same server the sonarqube MCP uses).
# Usage: bash scripts/sonar-sync.sh [repo ...]   (default: all repos with sonar.project_key)
. "$(dirname "$0")/lib.sh"
LOCAL="${SONAR_LOCAL_URL:-http://localhost:9100}"
ENVF="$ROOT/sonar/local.env"; mkdir -p "$ROOT/sonar"

# --- local server: start, wait, set admin password once, mint token ---
docker start factory-sonar >/dev/null 2>&1 || true
until [ "$(curl -s "$LOCAL/api/system/status" | jq -r .status 2>/dev/null)" = UP ]; do sleep 5; done
if [ ! -f "$ENVF" ]; then
  pw="Fac-$(openssl rand -hex 8)"
  curl -sf -u admin:admin -X POST "$LOCAL/api/users/change_password" -d login=admin -d previousPassword=admin --data-urlencode "password=$pw"
  tok=$(curl -sf -u "admin:$pw" -X POST "$LOCAL/api/user_tokens/generate" -d name=factory | jq -r .token)
  printf 'SONAR_LOCAL_USER=admin\nSONAR_LOCAL_PASSWORD=%s\nSONAR_LOCAL_TOKEN=%s\n' "$pw" "$tok" > "$ENVF"; chmod 600 "$ENVF"
fi
. "$ENVF"
L() { curl -sf -u "$SONAR_LOCAL_TOKEN:" "$@"; }   # local API call

# --- per repo ---
want=("$@")
for repo in $(repos_json | jq -r '.repos|to_entries[]|select(.value.sonar.project_key)|.key'); do
  [ ${#want[@]} -eq 0 ] || printf '%s\n' "${want[@]}" | grep -qx "$repo" || continue
  key=$(repos_json | jq -r --arg r "$repo" '.repos[$r].sonar.project_key')
  out="$ROOT/sonar/$repo"; mkdir -p "$out/profiles"; echo "== $repo ($key)"

  # gate: name + conditions
  gate=$(sonar api get "/api/qualitygates/get_by_project?project=$key" 2>/dev/null | jq -r .qualityGate.name)
  sonar api get "/api/qualitygates/show?name=$(jq -rn --arg g "$gate" '$g|@uri')" 2>/dev/null > "$out/gate.json"
  # gates are shared between repos -> build each once per run (destroy+create would unbind earlier repos)
  case " ${built:-} " in *" $gate "*) ;; *)
    L -X POST "$LOCAL/api/qualitygates/destroy" --data-urlencode "name=$gate" >/dev/null 2>&1 || true
    L -X POST "$LOCAL/api/qualitygates/create" --data-urlencode "name=$gate" >/dev/null
    # new gates ship with default conditions (e.g. new_coverage<80) -> clear them so only the org's conditions remain
    L "$LOCAL/api/qualitygates/show?name=$(jq -rn --arg g "$gate" '$g|@uri')" | jq -r '.conditions[].id' | while read -r id; do
      L -X POST "$LOCAL/api/qualitygates/delete_condition" -d "id=$id" >/dev/null
    done
    jq -c '.conditions[]' "$out/gate.json" | while read -r c; do
      L -X POST "$LOCAL/api/qualitygates/create_condition" --data-urlencode "gateName=$gate" \
        -d "metric=$(jq -r .metric <<<"$c")" -d "op=$(jq -r .op <<<"$c")" -d "error=$(jq -r .error <<<"$c")" >/dev/null \
        || echo "  gate cond skipped: $(jq -r .metric <<<"$c")"
    done
  built="${built:-} $gate" ;;
  esac
  L -X POST "$LOCAL/api/projects/create" -d "project=$key" --data-urlencode "name=$key" >/dev/null 2>&1 || true
  L -X POST "$LOCAL/api/qualitygates/select" -d "gateName=$gate" -d "projectKey=$key" >/dev/null
  echo "  gate: $gate ($(jq '.conditions|length' "$out/gate.json") conditions)"

  # profiles: every custom profile for the languages a frontend repo uses -> XML backup -> restore -> bind to project
  sonar api get "/api/qualityprofiles/search?project=$key" 2>/dev/null > "$out/profiles.json"
  jq -c '.profiles[]|select((.isBuiltIn|not) and (.language|IN("js","ts","css","web","xml","docker")))|{language,name}' "$out/profiles.json" | while read -r p; do
    lang=$(jq -r .language <<<"$p"); name=$(jq -r .name <<<"$p"); f="$out/profiles/$lang.xml"
    sonar api get "/api/qualityprofiles/backup?language=$lang&qualityProfile=$(jq -rn --arg n "$name" '$n|@uri')" 2>/dev/null > "$f"
    L -X POST "$LOCAL/api/qualityprofiles/restore" -F "backup=@$f" | jq -c '{profile:.profile.name,lang:.profile.language,ruleSuccesses:.ruleSuccesses,ruleFailures:.ruleFailures}' || echo "  restore failed: $lang"
    L -X POST "$LOCAL/api/qualityprofiles/add_project" --data-urlencode "qualityProfile=$name" -d "language=$lang" -d "project=$key" >/dev/null || echo "  bind failed: $lang"
  done
done
echo "local: $LOCAL  (creds: sonar/local.env)"
