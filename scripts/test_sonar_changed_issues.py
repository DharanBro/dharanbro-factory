"""Regression coverage for Sonar issues anchored outside changed lines."""

import unittest

from sonar_changed_issues import changed_issues


class ChangedIssuesTest(unittest.TestCase):
    def test_function_issue_with_changed_contributing_expression(self):
        component = "toolkit--DP-6969:src/EntitySelect.tsx"
        issues = [
            {
                "component": component,
                "line": 10,
                "severity": "CRITICAL",
                "rule": "typescript:S1541",
                "message": "Function has a complexity of 13",
                "flows": [
                    {"locations": [
                        {"component": component, "textRange": {"startLine": 15}}
                    ]}
                ],
            },
            {
                "component": component,
                "line": 40,
                "severity": "MAJOR",
                "rule": "typescript:S0000",
                "message": "Unrelated issue",
            },
        ]
        diff = """+++ b/src/EntitySelect.tsx
@@ -15 +15 @@
-old
+new
"""

        result = list(changed_issues(issues, diff))

        self.assertEqual(len(result), 1)
        self.assertIn("typescript:S1541", result[0])


if __name__ == "__main__":
    unittest.main()
