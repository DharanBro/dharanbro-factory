#!/usr/bin/env bash
# doctor.sh: a "Factory worker" skill without a stage in factory.yml fails the "worker stages" check.
. "$(dirname "$0")/lib.sh"
R=$(fake_root doctor.sh); B="$R/bin"; mkdir -p "$B" "$R/skills/factory-plan" "$R/skills/factory-add-repo" "$R/skills/factory-new-thing"
printf -- '---\ndescription: Factory worker. x\n---\n' | tee "$R/skills/factory-plan/SKILL.md" > "$R/skills/factory-new-thing/SKILL.md"
printf -- '---\ndescription: Register a repo\n---\n' > "$R/skills/factory-add-repo/SKILL.md"
printf '#!/usr/bin/env bash\nexit 1\n' | tee "$B/gh" > "$B/claude"; chmod +x "$B"/*   # no network, no plugins
line() { PATH="$B:$PATH" FACTORY_ROOT="$R" bash "$R/scripts/doctor.sh" 2>&1 | grep '^worker stages'; }
ok missing "$(line)" "worker stages          MISSING in factory.yml: new_thing"
rm -r "$R/skills/factory-new-thing"
ok present "$(line)" "worker stages          ok"
rm -rf "$R"
finish
