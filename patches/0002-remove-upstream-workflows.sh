#!/bin/bash
# Notchcast: remove upstream workflows (no GitLab mirror, Homebrew tap, Discord, triage, website or release runs in the fork)
# A script rather than a deletion patch, so an upstream edit to a workflow never stops the queue from applying.
set -euo pipefail
git rm -rq --ignore-unmatch .github/workflows
