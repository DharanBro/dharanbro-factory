#!/usr/bin/env bash
# Usage: evidence-html.sh <task-id>  -> tasks/<id>/artifacts/testing-evidence.html (self-contained, screenshots inlined)
set -euo pipefail
T="$(cd "$(dirname "$0")/.." && pwd)/tasks/$1/artifacts"
python3 -I - "$T" "$1" <<'PY'
import sys, glob, os, re, html, base64
a, tid = sys.argv[1], sys.argv[2]
esc = html.escape

def inline(s):
    s = esc(s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
    return s

def chip(cell):
    m = re.fullmatch(r"\s*(PASS|FAIL|FIXED|UNVERIFIED|BLOCKED|DONE)\b(.*)", cell)
    if not m: return None
    k = m.group(1).lower()
    return f"<span class='chip {k}'>{m.group(1)}</span>{inline(m.group(2))}"

STATUS = re.compile(r"(PASS|FAIL|FIXED|UNVERIFIED|BLOCKED)\b:?\s*(.*)")

def md(text):
    """Small markdown subset: headings, tables, lists, paragraphs, code fences."""
    out, lines, i = [], text.splitlines(), 0
    while i < len(lines):
        l = lines[i]
        if l.startswith("```"):
            j = i + 1
            while j < len(lines) and not lines[j].startswith("```"): j += 1
            out.append("<pre>" + esc("\n".join(lines[i+1:j])) + "</pre>"); i = j + 1
        elif re.match(r"#{1,6} ", l):
            n = 3 if len(l) - len(l.lstrip("#")) <= 2 else 4
            out.append(f"<h{n}>{inline(l.lstrip('# '))}</h{n}>"); i += 1
        elif l.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                rows.append([c.strip() for c in lines[i].strip().strip("|").split("|")]); i += 1
            rows = [r for r in rows if not all(re.fullmatch(r":?-+:?", c) for c in r)]
            t = "<div class='tw'><table><thead><tr>" + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr></thead><tbody>"
            for r in rows[1:]:
                t += "<tr>" + "".join(f"<td>{chip(c) or inline(c)}</td>" for c in r) + "</tr>"
            out.append(t + "</tbody></table></div>")
        elif STATUS.match(re.sub(r"^\s*[-*] ", "", l)):
            rows = []
            while i < len(lines) and STATUS.match(re.sub(r"^\s*[-*] ", "", lines[i])):
                m = STATUS.match(re.sub(r"^\s*[-*] ", "", lines[i]))
                rest = m.group(2).strip()
                sep = re.search(r"\s\|\s|: ", rest)
                name, ev = (rest[:sep.start()], rest[sep.end():]) if sep else (rest, "")
                rows.append(f"<li class='chk'><span class='chip {m.group(1).lower()}'>{m.group(1)}</span>"
                            f"<span class='nm'>{inline(name)}</span>" + (f"<span class='ev'>{inline(ev)}</span>" if ev else "") + "</li>")
                i += 1
            out.append("<ul class='checks'>" + "".join(rows) + "</ul>")
        elif re.match(r"\s*[-*] ", l):
            items = []
            while i < len(lines) and re.match(r"\s*[-*] ", lines[i]) and not STATUS.match(re.sub(r"^\s*[-*] ", "", lines[i])):
                ind = len(lines[i]) - len(lines[i].lstrip())
                items.append((ind >= 2, inline(re.sub(r"^\s*[-*] ", "", lines[i])))); i += 1
            out.append("<ul class='bl'>" + "".join(f"<li class='{'sub' if sub else ''}'>{x}</li>" for sub, x in items) + "</ul>")
        elif l.strip():
            p = [l]; i += 1
            while i < len(lines) and lines[i].strip() and not re.match(r"(#|\||```|\s*[-*] )", lines[i]) and not STATUS.match(lines[i]): p.append(lines[i]); i += 1
            out.append("<p>" + inline(" ".join(p)) + "</p>")
        else: i += 1
    return "\n".join(out)

nav, body, strip = [], [], []
tot = {"pass": 0, "fail": 0}

def section(sid, title, content, src=""):
    nav.append(f"<a href='#{sid}'>{esc(title)}</a>")
    c = {}
    for l in src.splitlines():
        m = STATUS.match(re.sub(r"^\s*[-*] ", "", l))
        if m and not l.startswith("|"): c[m.group(1)] = c.get(m.group(1), 0) + 1
    tail = src.split("## Unverified locally")[1] if "## Unverified locally" in src else ""
    un = len(re.findall(r"(?m)^- ", tail))
    if un: c["UNVERIFIED"] = c.get("UNVERIFIED", 0) + un
    first = re.match(r"<h3>([^<]*)</h3>\s*", content)
    if first and (re.match(r"<h3>", content[first.end():]) or first.group(1).lower().startswith(title.lower().split(": ")[-1])
                  or title.lower() in first.group(1).lower()):
        content = content[first.end():]
    sm = "".join(f"<span class='chip {k.lower()}'>{v} {k.lower()}</span>" for k, v in c.items())
    body.append(f"<section id='{sid}'><div class='sh'><h2>{esc(title)}</h2><div>{sm}</div></div>{content}</section>")

for p in sorted(glob.glob(f"{a}/test-report-*.md")):
    repo = os.path.basename(p)[12:-3]
    text = open(p).read()
    rows = {}
    for l in text.splitlines():
        m = re.match(r"\|\s*(\d+)\s*\|(.+)\|\s*(PASS|FAIL)\b", l)
        if m:
            rows[int(m.group(1))] = (m.group(2).strip(), m.group(3))
            tot[m.group(3).lower()] += 1
            strip.append((int(m.group(1)), m.group(3), m.group(2).strip()))
    figs = ""
    for img in sorted(glob.glob(f"{a}/ui/{repo}/*.png")):
        name = os.path.basename(img)
        n = int(re.match(r"(\d+)", name).group(1)) if re.match(r"\d+", name) else None
        cap, res = rows.get(n, (name, ""))
        src = "data:image/png;base64," + base64.b64encode(open(img, "rb").read()).decode()
        figs += (f"<figure><button type='button' data-src-id='i{n}'><img src='{src}' alt='{esc(cap)}'></button>"
                 f"<figcaption><span class='chip {res.lower()}'>{res or ''}</span> <b>{n}</b> {inline(cap)}"
                 f"<small>{esc(name)}</small></figcaption></figure>")
    section(f"ui-{repo}", f"UI test: {repo}", md(text) + (f"<h3>Screenshots</h3><div class='grid'>{figs}</div>" if figs else ""))

for p in sorted(glob.glob(f"{a}/ci-check-*.md")):
    section("ci-" + os.path.basename(p)[9:-3], "CI check: " + os.path.basename(p)[9:-3], md(open(p).read()), open(p).read())
for p in sorted(glob.glob(f"{a}/sonar-*.md")):
    section("sn-" + os.path.basename(p)[6:-3], "Sonar: " + os.path.basename(p)[6:-3], md(open(p).read()), "")
for p in sorted(glob.glob(f"{a}/review-*.md")):
    section("rv-" + os.path.basename(p)[7:-3], "Code review: " + os.path.basename(p)[7:-3], md(open(p).read()), "")

total = tot["pass"] + tot["fail"]
segs = "".join(f"<i class='seg {r.lower()}' title='{n}. {esc(t)}'></i>" for n, r, t in strip)
headline = (f"{tot['pass']} of {total} UI scenarios pass" if total else "No browser scenarios were run")
sub = ("Every scenario ran in the dashboard against ikea-devo, with a screenshot each." if total else "CI checks and code review are below.")

css = """
:root{--bg:#EEF1F4;--panel:#fff;--ink:#16202A;--mute:#5B6773;--line:#D5DBE1;--pass:#17724A;--passbg:#DDF1E6;--fail:#B3261E;--failbg:#FBE1DE;--warn:#8A5A00;--warnbg:#FBEBC8;--acc:#3A2FD0;--code:#E6EAEE}
@media(prefers-color-scheme:dark){:root{--bg:#10151A;--panel:#1A2128;--ink:#E7ECF0;--mute:#98A4AF;--line:#2D3741;--pass:#5FD39B;--passbg:#14382A;--fail:#FF8E85;--failbg:#45201D;--warn:#F0C15A;--warnbg:#3D2F0B;--acc:#9A92FF;--code:#252E37}}
*{box-sizing:border-box}html{scroll-behavior:smooth}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.55 system-ui,-apple-system,"Segoe UI",sans-serif}
code,pre,small{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
code{background:var(--code);padding:.1em .35em;border-radius:3px;font-size:.88em}
pre{background:var(--code);padding:1em;border-radius:6px;overflow:auto;white-space:pre-wrap}
a{color:var(--acc)}a:focus-visible,button:focus-visible{outline:3px solid var(--acc);outline-offset:2px}
.wrap{display:grid;grid-template-columns:220px minmax(0,1fr);gap:40px;max-width:1240px;margin:0 auto;padding:0 20px}
nav{position:sticky;top:0;align-self:start;padding:32px 0;display:flex;flex-direction:column;gap:2px;font-size:14px}
nav b{font-size:13px;color:var(--mute);margin-bottom:8px;font-weight:600}
nav a{color:var(--ink);text-decoration:none;padding:5px 10px;border-left:2px solid var(--line)}
nav a:hover{border-color:var(--acc);color:var(--acc)}
main{padding:32px 0 80px;min-width:0}
header{margin-bottom:40px}
h1{font-size:clamp(28px,4.2vw,44px);line-height:1.1;margin:.2em 0 .3em;letter-spacing:-.02em;font-weight:700}
header p{color:var(--mute);margin:0 0 20px;max-width:62ch}
.id{font:600 13px ui-monospace,Menlo,monospace;color:var(--acc)}
.strip{display:flex;gap:4px;height:28px;max-width:640px}
.seg{flex:1;border-radius:3px;background:var(--pass);transition:transform .12s}
.seg.fail{background:var(--fail)}.seg:hover{transform:scaleY(1.25)}
section{background:var(--panel);border:1px solid var(--line);border-radius:10px;padding:24px 28px;margin-bottom:24px}
h2{margin:0 0 .6em;font-size:22px;letter-spacing:-.01em}h3{margin:1.6em 0 .6em;font-size:17px}h4,h5{margin:1.2em 0 .4em}
p,li{max-width:74ch}ul{padding-left:1.2em}
.tw{overflow-x:auto;margin:1em 0}
table{border-collapse:collapse;width:100%;font-size:14px}
th{text-align:left;font-weight:600;color:var(--mute);border-bottom:2px solid var(--line);padding:8px 12px}
td{padding:9px 12px;border-bottom:1px solid var(--line);vertical-align:top}
tr:last-child td{border-bottom:0}
.chip{display:inline-block;font:600 12px/1 system-ui;padding:4px 8px;border-radius:99px;margin-right:6px;background:var(--code)}
.chip.pass,.chip.fixed,.chip.done{background:var(--passbg);color:var(--pass)}
.chip.fail,.chip.blocked{background:var(--failbg);color:var(--fail)}
.chip.unverified{background:var(--warnbg);color:var(--warn)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:20px}
ul.checks{list-style:none;padding:0;margin:1em 0;max-width:none;border:1px solid var(--line);border-radius:8px;overflow:hidden}
li.chk{display:grid;grid-template-columns:104px minmax(130px,230px) 1fr;gap:12px;align-items:baseline;padding:10px 14px;border-bottom:1px solid var(--line);max-width:none}
li.chk:last-child{border-bottom:0}li.chk .nm{font-weight:600;overflow-wrap:anywhere}li.chk .ev{color:var(--mute);font-size:14px}
li.chk .chip{justify-self:start;margin:0}
ul.bl li.sub{margin-left:1.4em;list-style:circle;color:var(--mute)}
.sh{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin-bottom:.6em}.sh h2{margin:0}.sh .chip{margin:0 0 0 6px}
@media(max-width:640px){li.chk{grid-template-columns:1fr;gap:2px}}
figure{margin:0;border:1px solid var(--line);border-radius:8px;overflow:hidden;background:var(--bg)}
figure button{display:block;width:100%;padding:0;border:0;background:none;cursor:zoom-in}
figure img{display:block;width:100%;height:auto}
figcaption{padding:10px 12px;font-size:13px;line-height:1.45}figcaption small{display:block;color:var(--mute);margin-top:4px;font-size:11px}
dialog{border:0;padding:0;background:none;max-width:96vw;max-height:96vh}dialog::backdrop{background:rgba(8,12,16,.8)}
dialog img{display:block;max-width:96vw;max-height:92vh;border-radius:6px}
@media(max-width:820px){.wrap{grid-template-columns:1fr;gap:0}nav{position:static;flex-direction:row;flex-wrap:wrap;padding:20px 0 0}nav b{width:100%}section{padding:18px}}
@media(prefers-reduced-motion:reduce){.seg{transition:none}html{scroll-behavior:auto}}
"""
js = """
const d=document.querySelector('dialog'),im=d.querySelector('img');
document.querySelectorAll('figure button').forEach(b=>b.onclick=()=>{im.src=b.querySelector('img').src;im.alt=b.querySelector('img').alt;d.showModal()});
d.onclick=()=>d.close();
"""
page = (f"<!doctype html><html lang='en'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"
        f"<title>{esc(tid)} testing evidence</title><style>{css}</style></head><body><div class='wrap'>"
        f"<nav aria-label='Sections'><b>{esc(tid)}</b>{''.join(nav)}</nav><main>"
        f"<header><span class='id'>{esc(tid)}</span><h1>{esc(headline)}</h1><p>{esc(sub)}</p>"
        f"{'<div class=strip role=img aria-label=' + chr(34) + esc(headline) + chr(34) + '>' + segs + '</div>' if strip else ''}</header>"
        f"{''.join(body)}</main></div><dialog><img alt=''></dialog><script>{js}</script></body></html>")
open(f"{a}/testing-evidence.html", "w").write(page)
print(f"{a}/testing-evidence.html")
PY
