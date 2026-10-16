#!/usr/bin/env python3
"""Report Sonar issues whose primary or contributing locations changed on a branch."""

import json
import re
import sys


def changed_ranges(diff):
    ranges = {}
    path = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:]
            ranges.setdefault(path, [])
        elif line.startswith("@@") and path:
            match = re.search(r"\+(\d+)(?:,(\d+))?", line)
            if match:
                start = int(match.group(1))
                count = int(match.group(2) or 1)
                ranges[path].append((start, start + count - 1))
    return ranges


def changed_issues(issues, diff):
    ranges = changed_ranges(diff)
    for issue in issues:
        path = issue["component"].split(":", 1)[-1]
        if path not in ranges:
            continue
        line = issue.get("line") or 0
        locations = [
            location
            for flow in issue.get("flows", [])
            for location in flow.get("locations", [])
        ]
        # Function-level issues can be anchored to an unchanged declaration.
        # Sonar's flow locations include expressions that contribute to the issue.
        affected = [line] + [
            location["textRange"]["startLine"]
            for location in locations
            if location.get("component", "").split(":", 1)[-1] == path
            and location.get("textRange", {}).get("startLine")
        ]
        if line == 0 or any(
            start <= affected_line <= end
            for start, end in ranges[path]
            for affected_line in affected
        ):
            yield f"- [{issue['severity']}] {issue['rule']} {path}:{line} {issue['message']}"


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as issues_file:
        issues = json.load(issues_file)["issues"]
    with open(sys.argv[2], encoding="utf-8") as diff_file:
        diff = diff_file.read()
    print("\n".join(changed_issues(issues, diff)))
