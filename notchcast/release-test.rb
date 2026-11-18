#!/usr/bin/env ruby
require 'yaml'
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
[%w[snapshot build snapshot], %w[sync-release build sign]].each do |name, build, sign|
  jobs = WORKFLOWS.fetch(name).fetch('jobs')
  assert(uses.(jobs.fetch(build), 'release') == 1, "#{name} #{build} must use the shared release action once")
  assert(uses.(jobs.fetch(sign), 'sign') == 1, "#{name} #{sign} must use the shared sign action once")
  assert(Array(jobs.fetch(sign)['needs']).include?(build), "#{name} #{sign} must sign what #{build} built")
  if name == 'snapshot'
    publish = jobs.fetch('publish')
    assert(%w[checks snapshot].all? { |need| publish['needs'].include?(need) } && !publish.key?('if'),
           'snapshot publish must remain gated on lint, tests and the signed build')
    checks = jobs.fetch('checks')
    steps = checks.fetch('steps')
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
      assert(!step['run'].to_s.match?(TREE_CODE), "#{name} #{id} holds secrets and runs tree code in #{step['name'] || step['run'][0, 40]}")
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
puts 'release action: PASS'
