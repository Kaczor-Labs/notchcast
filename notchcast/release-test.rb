#!/usr/bin/env ruby
require 'yaml'
require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'

ROOT = File.expand_path('..', __dir__)
ACTION = YAML.load_file(File.join(__dir__, 'actions/release/action.yml'))
SIGN = YAML.load_file(File.join(__dir__, 'actions/sign/action.yml'))


def assert(value, message)
  raise message unless value
end

[ACTION, SIGN].each do |action|
  action.fetch('runs').fetch('steps').each do |step|
    assert(step['shell'] == 'bash -e {0}', "#{step['name']} must preserve the workflow's implicit bash shell")
    output, status = Open3.capture2e('bash', '-n', stdin_data: step.fetch('run'))
    assert(status.success?, "#{step['name']} shell syntax failed: #{output}")
  end
end
assert(SIGN.fetch('runs').fetch('steps').none? { |step| step['run'].match?(/xcodebuild|src\/|Scripts\//) },
       'the sign action must run none of the tree\'s code')

WORKFLOWS = Dir.glob(File.join(ROOT, '.github/workflows/*.yml')).to_h { |path| [File.basename(path, '.yml'), YAML.load_file(path)] }
uses = ->(job, action) { job.fetch('steps', []).count { |step| step['uses'] == "./tools/notchcast/actions/#{action}" } }
[%w[snapshot build snapshot], %w[sync-release build sign], %w[test-build build sign]].each do |name, build, sign|
  jobs = WORKFLOWS.fetch(name).fetch('jobs')
  assert(uses.(jobs.fetch(build), 'release') == 1, "#{name} #{build} must use the shared release action once")
  assert(uses.(jobs.fetch(sign), 'sign') == 1, "#{name} #{sign} must use the shared sign action once")
  assert(Array(jobs.fetch(sign)['needs']).include?(build), "#{name} #{sign} must sign what #{build} built")
  if name == 'snapshot'
    publish = jobs.fetch('publish')
    assert(publish['needs'].include?('snapshot') && !publish.key?('if'),
           'snapshot publish must remain gated on lint, tests and the signed build')
    checks = jobs.fetch(build)
    release = checks.fetch('steps').index { |step| step['uses'] == './tools/notchcast/actions/release' }
    steps = checks.fetch('steps').first(release)
    tests = steps.find { |step| step['uses'] == './tools/notchcast/actions/tests' }
    lint = steps.find { |step| step['name'] == 'Lint' }
    final = steps.last
    assert(!checks.key?('continue-on-error'), 'snapshot checks must fail the run when red')
    assert(steps.none? { |step| step['continue-on-error'] && !step.equal?(tests) },
           'only the tests action may continue on error, so the final step reports it')
    assert(tests && lint && lint['run'].include?('./Scripts/lint.sh'), 'snapshot checks must run tests and lint')
    assert(final['if'] == "steps.checks.outputs.green != 'true'" && final['run'].include?('exit 1') &&
           !final.key?('continue-on-error'), 'snapshot checks must end in the step that fails when not green')
  end
  puts "PASS #{name} builds with the release action and signs with the sign action"
end

# A job that can read a secret or uses environment sync runs none of the tree's code (#873): no build, test, replay,
# xcodegen or script from the checked-out tree.
TREE_CODE = %r{xcodebuild|Scripts/|ci\.py replay|XCODEGEN|run-tests|\.\./tools/}
TREE_ACTIONS = %w[release tests xcode xcodegen].map { |action| "./tools/notchcast/actions/#{action}" }
WORKFLOWS.each do |name, workflow|
  workflow.fetch('jobs').each do |id, job|
    next unless job.to_s.include?('secrets.') || job['environment']
    next if job.key?('uses')
    job.fetch('steps').each do |step|
      assert(!TREE_ACTIONS.include?(step['uses']), "#{name} #{id} holds secrets and runs #{step['uses']}")
      assert(!step['run'].to_s.match?(TREE_CODE), "#{name} #{id} holds secrets and runs tree code in #{step['name'] || step['uses'] || step['run'].to_s[0, 40]}")
      assert(step['working-directory'] != 'src' || !step.key?('run') || step['run'].match?(/\Anotchcast\//),
             "#{name} #{id} holds secrets and runs a command in the tree")
    end
  end
  puts "PASS #{name}: no job with secrets runs the tree's code"
end

launch = ACTION.fetch('runs').fetch('steps').find { |step| step['name'] == 'Launch and stay alive' }
assert(launch && launch['run'].include?("sleep 30\n") && launch['run'].include?('kill -0 "$PID"'), 'release must check liveness after 30 seconds')

Dir.mktmpdir('release-launch-') do |directory|
  FileUtils.mkdir_p(File.join(directory, 'tools/notchcast'))
  File.write(File.join(directory, 'tools/notchcast/config.env'), "APP_NAME=Fixture\n")
  FileUtils.mkdir_p(File.join(directory, 'bin'))
  File.write(File.join(directory, 'bin/ditto'), "#!/bin/bash\ncp -R \"$1\" \"$2\"\n")
  # Waits for the fixture to run, so a slow start can't pass as alive.
  File.write(File.join(directory, 'bin/sleep'), "#!/bin/bash\n[ \"$1\" = 30 ] || exit 9\n" \
    "for _ in $(seq 300); do [ -e \"$RUNNER_TEMP/ran\" ] && break; /bin/sleep 0.1; done\n/bin/sleep 0.5\n")
  FileUtils.chmod(0755, Dir.glob(File.join(directory, 'bin/*')))
  app = File.join(directory, 'DerivedData/Build/Products/Release/Fixture.app/Contents/MacOS')
  FileUtils.mkdir_p(app)
  executable = File.join(app, 'Fixture')
  script = File.join(directory, 'launch.sh')
  File.write(script, launch.fetch('run'))
  env = {'RUNNER_TEMP' => directory, 'PATH' => "#{directory}/bin:#{ENV.fetch('PATH')}"}
  [['exec /bin/sleep 120', true], ['exit 1', false]].each do |body, expected|
    File.write(executable, "#!/bin/bash\ntouch \"$RUNNER_TEMP/ran\"\n#{body}\n")
    FileUtils.chmod(0755, executable)
    FileUtils.rm_rf(File.join(directory, 'launch'))
    FileUtils.rm_f(File.join(directory, 'ran'))
    output, status = Open3.capture2e(env, 'bash', '-e', script, chdir: directory)
    assert(status.success? == expected, "launch result does not match process liveness: #{output}")
    puts "PASS launch check #{expected ? 'accepts a live process' : 'rejects a crashed process'}"
  end
end
package = SIGN.fetch('runs').fetch('steps').find { |step| step['name'] == 'Package zip and dmg' }
assert(package && !package['run'].match?(/^\s*hdiutil|-quiet/), 'packaging must not hide why it failed (#902)')

Dir.mktmpdir('release-package-') do |directory|
  FileUtils.mkdir_p(File.join(directory, 'tools/notchcast'))
  File.write(File.join(directory, 'tools/notchcast/config.env'), "APP_NAME=Fixture\n")
  FileUtils.mkdir_p(File.join(directory, 'signed/Fixture.app/Contents'))
  FileUtils.mkdir_p(File.join(directory, 'bin'))
  File.write(File.join(directory, 'bin/ditto'), "#!/bin/bash\ntouch \"${@: -1}\"\n")
  script = File.join(directory, 'package.sh')
  File.write(script, package.fetch('run'))
  env = {'RUNNER_TEMP' => directory, 'VERSION' => '1.0', 'PATH' => "#{directory}/bin:#{ENV.fetch('PATH')}"}
  [['touch "${@: -1}"; echo "$@" > "$RUNNER_TEMP/args"', true],
   ['echo "Error: Resource busy" >&2; exit 1', false]].each do |body, expected|
    File.write(File.join(directory, 'bin/diskutil'), "#!/bin/bash\n#{body}\n")
    FileUtils.chmod(0755, Dir.glob(File.join(directory, 'bin/*')))
    FileUtils.rm_rf(File.join(directory, 'dist'))
    output, status = Open3.capture2e(env, 'bash', '-e', script, chdir: directory)
    assert(status.success? == expected, "package result does not match diskutil: #{output}")
    if expected
      args = File.read(File.join(directory, 'args'))
      assert(args.start_with?('image create from --format UDZO --volumeName Fixture ') &&
             args.end_with?(" dist/Fixture-1.0.dmg\n") && File.exist?(File.join(directory, 'dist/Fixture-1.0.zip')),
             "package must build a UDZO dmg and a zip: #{args}")
    else
      assert(output.include?('Resource busy') && output.include?('::error::diskutil'),
             "a failed dmg must say why: #{output}")
    end
    puts "PASS package #{expected ? 'builds the zip and dmg' : 'reports a failed dmg'}"
  end
end
# test-build.yml signs a PR's head on demand: only by dispatch, only from main, never a closed or a fork's PR.
TEST_BUILD = WORKFLOWS.fetch('test-build')
assert(TEST_BUILD.fetch(true).keys == ['workflow_dispatch'], 'test-build must start only by dispatch')
test_jobs = TEST_BUILD.fetch('jobs')
assert(test_jobs.fetch('plan')['if'] == "github.ref == 'refs/heads/main'", 'test-build must run only from main')
assert(test_jobs.fetch('build')['if'] == "needs.plan.outputs.build == 'true'", 'test-build builds only what lanes.py says')
assert(test_jobs.fetch('build').fetch('steps').none? { |step| step.to_s.include?('secrets.') }, 'test-build build holds no secret')
build_steps = test_jobs.fetch('build').fetch('steps')
verify_step = build_steps.first
assert(verify_step.fetch('name') == 'Verify the PR before building for signing', 'verify the planned PR before checkout')
sign_steps = test_jobs.fetch('sign').fetch('steps')
[build_steps.find { |step| step.dig('with', 'path') == 'tools' }, sign_steps.first].each do |step|
  assert(step.dig('with', 'ref') == '${{ github.sha }}', 'the planner may not choose signing or build tools')
end
artifact = sign_steps.last
assert(artifact.dig('with', 'name') == 'test-build' && artifact.dig('with', 'path') == 'dist/*.zip' &&
       artifact.dig('with', 'retention-days') == 3, 'test-build keeps only the zip, for 3 days')
plan_step = test_jobs.fetch('plan').fetch('steps').find { |step| step['id'] == 'plan' }

Dir.mktmpdir('test-build-plan-') do |directory|
  FileUtils.mkdir_p(File.join(directory, 'bin'))
  File.write(File.join(directory, 'bin/gh'), <<~'SH')
    #!/bin/bash
    refuse() { echo "gh stub: unexpected call: $*" >&2; exit 1; }
    case "$1 $2" in
      'pr view') [ "$3 $4 $5" = "$PR -R owner/repo" ] || refuse "$@"; json="$PR_JSON" ;;
      'release list') [ "$3 $4" = '-R owner/repo' ] || refuse "$@"; json="$RELEASES" ;;
      *) refuse "$@" ;;
    esac
    printf '%s' "$json" | jq -r "${*: -1}"
  SH
  File.write(File.join(directory, 'bin/git'), <<~'SH')
    #!/bin/bash
    case "$1 $2" in
      'rev-parse FETCH_HEAD') echo "$FETCHED" ;;
      merge-base*) echo 2222222222222222222222222222222222222222 ;;
    esac
  SH
  File.write(File.join(directory, 'bin/python3'), "#!/bin/bash\nprintf 'build=%s\\nscripts=true\\n' \"$LANE\"\n")
  FileUtils.chmod(0755, Dir.glob(File.join(directory, 'bin/*')))
  script = File.join(directory, 'step.sh')
  output_file = File.join(directory, 'output')
  head = 'abcdef0123456789abcdef0123456789abcdef01'
  beta_head = '05f7006571f7610675a50b34a2d3e89310b36521'
  pr = ->(state: 'OPEN', cross: false, branch: 'fix', oid: head) {
    {state: state, isCrossRepository: cross, headRefOid: oid, headRefName: branch}.to_json
  }
  stable = [['v0.12.9', false], ['v0.12.8.snapshot.20261107210745', false], ['v0.12.7.snapshot.20261108000000', false],
            ['v0.12.9.snapshot.20261109000000', true]]
  beta = stable + [['v0.13.0-beta.145.snapshot.20261123171110', false]]
  unmakeable = [['v0.13.0-rc.1.2.snapshot.20261124000000', false]]
  step = ->(job_step, variables) {
    File.write(script, job_step.fetch('run'))
    File.write(output_file, '')
    variables = {'PATH' => "#{directory}/bin:#{ENV.fetch('PATH')}", 'GITHUB_OUTPUT' => output_file,
                 'GITHUB_REPOSITORY' => 'owner/repo', 'RUN_NUMBER' => '5'}.merge(variables)
    output, status = Open3.capture2e(variables, 'bash', '-eo', 'pipefail', script, chdir: directory)
    [output, status.success?, File.read(output_file)]
  }
  one_error = ->(output, want) { output.lines.grep(/^::/).size == 1 && output.match?(/^::error::.*#{Regexp.escape(want)}/) }
  planned = {}
  [['open PR that builds the app', '7', pr.(), head, 'true', stable, "build=true\nhead=#{head}\nversion=0.12.7.pr7.abcdef01\n"],
   ['beta snapshot base', '1436', pr.(oid: beta_head), beta_head, 'true', beta, "version=0.13.0-beta.145.pr1436.05f70065\n"],
   ['newer snapshot tag the producer cannot make', '1436', pr.(oid: beta_head), beta_head, 'true', beta + unmakeable,
    "version=0.13.0-beta.145.pr1436.05f70065\n"],
   ['add-on branch, whatever lanes.py says', '7', pr.(branch: 'v2/addons-x'), head, 'false', stable, 'build=true'],
   ['docs-only PR', '7', pr.(), head, 'false', stable, "build=false\n"],
   ['closed PR', '7', pr.(state: 'MERGED'), head, 'true', stable, nil, 'is MERGED'],
   ["a fork's PR", '7', pr.(cross: true), head, 'true', stable, nil, 'another repository'],
   ['head moved while planning', '7', pr.(), '0' * 40, 'true', stable, nil, 'moved while planning'],
   ['no snapshot tag the producer can make', '7', pr.(), head, 'true', unmakeable, nil, 'no snapshot release'],
   ['not a number', '7; true', pr.(), head, 'true', stable, nil, 'must be a PR number'],
   ['a line break in the PR number', "7\n::warning::x", pr.(), head, 'true', stable, nil, 'must be a PR number']
  ].each do |name, number, json, fetched, lane, tags, want, error|
    output, ok, written = step.(plan_step, 'PR' => number, 'PR_JSON' => json, 'FETCHED' => fetched, 'LANE' => lane,
                                'RELEASES' => tags.map { |tag, draft| {tagName: tag, isDraft: draft} }.to_json)
    if want
      assert(ok && written.include?(want), "test-build plan, #{name}: #{output}#{written}")
    else
      assert(!ok && one_error.(output, error), "test-build plan, #{name}: #{output}#{written}")
      assert(written.empty?, "test-build plan, #{name}: a refusal must plan nothing")
    end
    assert(!written.match?(/version=.*[.]snapshot[.]/), 'a test build version must never look like a snapshot')
    puts "PASS test-build plan: #{name}"
    next unless written.include?('build=true')
    outputs = written.lines.to_h { |line| line.chomp.split('=', 2) }
    planned[name] = outputs.fetch('version')
    output, ok, = step.(verify_step, 'PR' => number, 'PR_JSON' => json, 'HEAD' => outputs.fetch('head'),
                        'VERSION' => outputs.fetch('version'))
    assert(ok, "test-build verification refuses what the plan made, #{name}: #{output}")
    puts "PASS test-build verification: accepts the plan of #{name}"
  end
  version = planned.fetch('open PR that builds the app')
  beta_version = planned.fetch('beta snapshot base')
  [['closed after planning', '7', pr.(state: 'CLOSED'), head, version, 'is CLOSED'],
   ['fork reported by GitHub', '7', pr.(cross: true), head, version, 'another repository'],
   ['different commit from GitHub', '7', pr.(), '0' * 40, '0.12.7.pr7.00000000', 'moved from the planned head'],
   ['no answer from GitHub', '7', '', head, version, 'could not read PR #7'],
   ['not a number', '7; true', pr.(), head, version, 'must be a PR number'],
   ['a line break in the PR number', "7\n::warning::x", pr.(), head, version, 'must be a PR number'],
   ['head is not a commit id', '7', pr.(), 'abcdef01', version, 'is not a commit id'],
   ['a line break in the head', '7', pr.(), "#{head}\n::warning::x", version, 'is not a commit id'],
   ['a line break in the version', '7', pr.(), head, "#{version}\n::warning::x", 'planned version'],
   ['version of another PR', '7', pr.(), head, '0.12.7.pr9.abcdef01', 'planned version'],
   ['beta version of another PR', '1437', pr.(oid: beta_head), beta_head, beta_version, 'planned version'],
   ['beta version of another head', '1436', pr.(), head, beta_version, 'planned version'],
   ['base the producer cannot make', '7', pr.(), head, '0.13.0-rc.1.2.pr7.abcdef01', 'planned version'],
   ['snapshot version', '7', pr.(), head, '0.12.7.snapshot.20261108000000.pr7.abcdef01', 'planned version']
  ].each do |name, number, json, sha, planned_version, error|
    output, ok, = step.(verify_step, 'PR' => number, 'PR_JSON' => json, 'HEAD' => sha, 'VERSION' => planned_version)
    assert(!ok && one_error.(output, error), "test-build verification, #{name}: #{output}")
    puts "PASS test-build verification: #{name}"
  end
end
puts 'release action: PASS'
