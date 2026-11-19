#!/bin/bash
# Sourced by config.env. A fork harness (Tests/nc-*, Tests/notchcast-*) joins HOSTED_ONLY_TESTS,
# LINUX_OK_TESTS or CI_SKIP_TESTS by a column-0 line in its own file, `// notchcast-hosted-only`, `// notchcast-linux-ok`
# or `// notchcast-ci-skip`, never by its name in config.env, so two PRs never edit one line there. Only a list already
# set gains names: test-harnesses.sh sees CI_SKIP_TESTS only on a hosted runner.
harness_tagged() {
    grep -lx "// notchcast-$1" "$2"/Tests/*.swift 2>/dev/null | sed 's#.*/##; s#\.swift$##' | paste -sd' ' - || true
}
harness_tags_root=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)
[ -z "${HOSTED_ONLY_TESTS+set}" ] || HOSTED_ONLY_TESTS=$(echo $HOSTED_ONLY_TESTS $(harness_tagged hosted-only "$harness_tags_root"))
[ -z "${LINUX_OK_TESTS+set}" ] || LINUX_OK_TESTS=$(echo $LINUX_OK_TESTS $(harness_tagged linux-ok "$harness_tags_root"))
[ -z "${CI_SKIP_TESTS+set}" ] || CI_SKIP_TESTS=$(echo $CI_SKIP_TESTS $(harness_tagged ci-skip "$harness_tags_root"))
unset harness_tags_root
