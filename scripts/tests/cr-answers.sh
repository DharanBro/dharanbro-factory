#!/usr/bin/env bash
# cr-answers.py: an answer silences a finding only on file AND key match; same file, other finding stays open.
. "$(dirname "$0")/lib.sh"
D=$(mktemp -d)
f() { printf '{"type":"finding","severity":"major","fileName":"%s","title":"%s","codegenInstructions":"%s"}\n' "$1" "$2" "$3"; }
{ f src/A.tsx "Scroll focus" "scrollToFirstError runs before the DOM updates"; f src/A.tsx "Duplicate id" "dynamic-list-0-header repeats"; f src/B.tsx "Scroll focus" "scrollToFirstError again"; echo '{"type":"complete","findings":3}'; } > "$D/cr"
cat > "$D/ans.md" <<'A'
- src/A.tsx | scrollToFirstError | handled by the rAF in useFocusFirstError (hooks.ts:40)
- src/A.tsx | nomatchkey-xyz | stale answer, matches nothing
- src/C.tsx | short | key under 8 chars is ignored
- src/B.tsx | scrollToFirstError |
A
out=$(python3 -I "$SRC/scripts/cr-answers.py" "$D/ans.md" < "$D/cr")
ok answered-listed "$(grep -c '^A src/A.tsx | scrollToFirstError | handled by' <<<"$out")" 1
ok same-file-new-finding-open "$(grep -c '^O .*src/A.tsx.*dynamic-list-0-header' <<<"$out")" 1
ok other-file-open "$(grep -c '^O .*src/B.tsx' <<<"$out")" 1
ok answer-without-reason-ignored "$(grep -c '^A src/B' <<<"$out")" 0
ok unmatched-answer-not-listed "$(grep -c 'nomatchkey' <<<"$out")" 0
ok no-answers-file-all-open "$(python3 -I "$SRC/scripts/cr-answers.py" "$D/none.md" < "$D/cr" | grep -c '^O ')" 3
finish
