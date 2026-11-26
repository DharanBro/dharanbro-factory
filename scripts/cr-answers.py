#!/usr/bin/env python3
"""cr-answers.py <answers-file> < coderabbit-agent-output
Splits CodeRabbit CLI findings into answered and open. An answer line is `- <file> | <match key> | <reason>`; it silences a
finding only when fileName equals <file> AND the key (>= 8 chars, case-insensitive) appears in the finding's title or
instructions, so a different finding in the same file stays open. Prints `A <file> | <key> | <reason>` per answered finding
(once per answer) and `O [severity] <file>: <text>` per open one."""
import json, sys, os
ans = []
if os.path.exists(sys.argv[1]):
    for l in open(sys.argv[1]):
        p = [x.strip() for x in l.lstrip("- ").split("|", 2)]
        if len(p) == 3 and len(p[1]) >= 8 and p[2]:
            ans.append(p)
used = set()
for l in sys.stdin:
    try: f = json.loads(l)
    except ValueError: continue
    if f.get("type") != "finding": continue
    txt = f"{f.get('title') or ''} {f.get('codegenInstructions') or ''}"
    hit = next((a for a in ans if a[0] == f.get("fileName") and a[1].lower() in txt.lower()), None)
    if hit: used.add(tuple(hit))
    else: print(f"O [{f.get('severity')}] {f.get('fileName')}: {f.get('codegenInstructions') or f.get('title') or 'see CLI output'}")
for a in sorted(used): print("A " + " | ".join(a))
