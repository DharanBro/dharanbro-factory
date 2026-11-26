#!/usr/bin/env bash
# sonar-verdict.py with fixture issues (no Sonar server): S1541 sits on the first line of a function the branch only edited
# inside; counted via the base diff (B). Issues already in the base, in untouched files, or on untouched lines stay out.
. "$(dirname "$0")/lib.sh"
D=$(mktemp -d)
iss() { printf '{"key":"%s","rule":"%s","severity":"CRITICAL","component":"p:%s","line":%s,"message":"%s","flows":%s}' "$1" "$2" "$3" "$4" "$5" "${6:-[]}"; }
# new-code issues: the S1541 (line 637, unchanged) with a flow location on changed line 650; one real hit on changed line 12; one on untouched line 99
{ echo '{"issues":['
  iss k1 typescript:S1541 src/a.tsx 637 "complexity 12" '[{"locations":[{"component":"p:src/a.tsx","textRange":{"startLine":650}}]}]'; echo ,
  iss k2 typescript:S1135 src/a.tsx 12 "todo"; echo ,
  iss k3 typescript:S1135 src/a.tsx 99 "old todo"; echo ']}'; } > "$D/new.json"
echo '{"issues":[]}' > "$D/base0.json"
# base had the same S1135 on line 99 and an S1541 "complexity 10" on the function (message differs: it grew)
{ echo '{"issues":['; iss b1 typescript:S1135 src/a.tsx 99 "old todo"; echo ,; iss b2 typescript:S1541 src/a.tsx 637 "complexity 10"; echo ']}'; } > "$D/base.json"
# head: everything above plus an untouched-function S1541 in a changed file that the base already had, and an issue in an untouched file
{ echo '{"issues":['
  iss k1 typescript:S1541 src/a.tsx 637 "complexity 12"; echo ,
  iss k2 typescript:S1135 src/a.tsx 12 "todo"; echo ,
  iss k3 typescript:S1135 src/a.tsx 99 "old todo"; echo ,
  iss k4 typescript:S3776 src/a.tsx 300 "cognitive 16"; echo ,
  iss k5 typescript:S3776 src/other.tsx 5 "cognitive 20"; echo ']}'; } > "$D/head.json"
printf '+++ b/src/a.tsx\n@@ -10,0 +12,1 @@\n+x\n@@ -648,0 +650,1 @@\n+y\n' > "$D/diff"
out=$(python3 -I "$SRC/scripts/sonar-verdict.py" "$D/new.json" "$D/base.json" "$D/head.json" "$D/diff")
ok flow-location-on-changed-line "$(grep -c '^A .*S1541' <<<"$out")" 1
ok changed-line-hit "$(grep -c '^A .*S1135 src/a.tsx:12' <<<"$out")" 1
ok untouched-line-and-base-issue-ignored "$(grep -c 'old todo' <<<"$out")" 0
ok new-in-changed-file-on-unchanged-line "$(grep -c '^B .*S3776 src/a.tsx:300' <<<"$out")" 1
ok untouched-file-ignored "$(grep -c 'other.tsx' <<<"$out")" 0
# without the flow, S1541 (unchanged line, message grew vs base) must still be caught through B
sed 's/"flows":\[{[^]]*\]}\]/"flows":[]/' "$D/new.json" > "$D/new2.json"
out2=$(python3 -I "$SRC/scripts/sonar-verdict.py" "$D/new2.json" "$D/base.json" "$D/head.json" "$D/diff")
ok first-line-issue-caught-via-base-diff "$(grep -c '^B .*S1541 src/a.tsx:637' <<<"$out2")" 1
# same S1541 with the same message in base: not new
sed 's/complexity 10/complexity 12/' "$D/base.json" > "$D/base2.json"
ok unchanged-complexity-not-new "$(python3 -I "$SRC/scripts/sonar-verdict.py" "$D/new2.json" "$D/base2.json" "$D/head.json" "$D/diff" | grep -c S1541)" 0
finish
