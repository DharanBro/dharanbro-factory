#!/usr/bin/env python3
"""sonar-verdict.py <new-code-issues.json> <base-issues.json> <head-issues.json> <branch.diff>
Prints one line per problem: "A ..." = issue on a changed line (primary line or any flow location),
"B ..." = unresolved issue in a changed file that the base scan did not have (key: rule + path + message, no line).
B catches S1541/S3776, which Sonar pins on a function's first line even when the branch only edited its body."""
import sys, json, re

new, base, head = (json.load(open(p))["issues"] for p in sys.argv[1:4])
ch, f = {}, None
for l in open(sys.argv[4]):
    if l.startswith("+++ b/"): f = l[6:].strip(); ch.setdefault(f, [])
    elif l.startswith("@@") and f:
        m = re.search(r"\+(\d+)(?:,(\d+))?", l); a = int(m.group(1)); n = int(m.group(2) or 1)
        ch[f].append((a, a + n - 1))

path = lambda i: i["component"].split(":", 1)[-1]
key = lambda i: (i["rule"], path(i), i["message"])
fmt = lambda t, i: f"{t} [{i['severity']}] {i['rule']} {path(i)}:{i.get('line') or 0} {i['message']}"
def hit(i):
    lines = [i.get("line") or 0] + [loc.get("textRange", {}).get("startLine", 0)
             for fl in i.get("flows", []) for loc in fl.get("locations", []) if loc.get("component") == i["component"]]
    return any(l == 0 or any(a <= l <= b for a, b in ch[path(i)]) for l in lines)

seen = {i["key"] for i in new if path(i) in ch and hit(i)}
for i in new:
    if i["key"] in seen: print(fmt("A", i))
old = {key(i) for i in base}
for i in head:
    if path(i) in ch and i["key"] not in seen and key(i) not in old: print(fmt("B", i))
