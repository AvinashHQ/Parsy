---
name: pr-comment-review
description: Review PR comments, apply valid fixes, reply clearly, and resolve threads when appropriate
metadata:
  audience: maintainers
  scope: github-pr-review-followup
---
# PR Comment Review

## When to use
Use this skill when a pull request has review comments and you want to triage them, apply any necessary code or doc fixes, reply with what changed or why no change was needed, and finish the review loop cleanly.

## Workflow
1. Fetch the latest review comments and current branch status for the target PR.
2. Separate comments into:
   - valid comments that require a fix
   - valid comments that require only a clarification reply
   - comments that are incorrect, stale, or already addressed
3. For fix-required comments, apply the smallest correct code or documentation change.
4. Run the smallest relevant validation for the touched area.
5. Reply on every addressed thread with one of:
   - what changed
   - why no code/doc change was needed
   - what was intentionally left unchanged
6. Push follow-up commits when needed.
7. Resolve review threads when the hosting workflow/tool supports it and the comment has been fully addressed.
8. Keep the underlying delivery task in review or active execution until the PR lands; only close the task after review feedback is handled and the final PR plus validation evidence are posted.

## Guardrails
- Do not blindly accept every review suggestion; verify correctness against the code and repo rules.
- Keep fixes scoped to the actual review issue.
- Avoid bundling unrelated cleanup into review follow-ups.
- Always explain what changed or why nothing changed.
- If a comment is incorrect, reply politely with the validation result instead of forcing a bad fix.
- Prefer the smallest validation command that proves the fix.
- Requested changes mean the work is still open; do not describe the task as done just because the first PR or reply is posted.
