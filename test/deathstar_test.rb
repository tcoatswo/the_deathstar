# frozen_string_literal: true

require 'minitest/autorun'
require 'stringio'
require 'tmpdir'
require_relative '../DeathStar'

class FakeRunner
  attr_reader :calls

  def initialize(fail_worker: false, fail_run: false, fail_cleanup: false)
    @calls = []
    @fail_worker = fail_worker
    @fail_run = fail_run
    @fail_cleanup = fail_cleanup
  end

  def run(*args, **_options)
    @calls << args
    if args[1] == 'cp' && args[2].include?(':/home/.')
      File.write(File.join(args[3], 'demo.txt'), 'result')
    end
    code = if (@fail_worker && args[1] == 'exec')
             7
           elsif (@fail_run && args[1] == 'run') || (@fail_cleanup && args[1] == 'rm')
             1
           else
             0
           end
    DeathStar::Result.new(status: code, stdout: '', stderr: code == 0 ? '' : 'simulated failure', timed_out: false)
  end
end

class DeathStarTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @targets = File.join(@dir, 'targets.txt')
    @output_dir = File.join(@dir, 'results')
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def app(args, runner: FakeRunner.new)
    output = StringIO.new
    error = StringIO.new
    instance = DeathStar::App.new(['--ip-list', @targets, '--output-dir', @output_dir, *args],
                                  env: {}, output: output, error: error, runner: runner)
    [instance.run, output.string, error.string, runner]
  end

  def manifest
    JSON.parse(File.read(Dir[File.join(@output_dir, '*', 'manifest.json')].first))
  end

  def test_dry_run_deduplicates_and_shards_without_docker
    File.write(@targets, "# lab\n10.0.0.1\n10.0.0.1 # duplicate\n10.0.0.2\n10.0.0.3\n")
    status, _, _, runner = app(['--dry-run', '--shard-size', '2'])
    assert_equal 0, status
    assert_empty runner.calls
    assert_equal 3, manifest['target_count']
    assert_equal [2, 1], manifest['workers'].map { |w| w['target_count'] }
    assert_equal 'planned', manifest['status']
  end

  def test_invalid_ip_rejected_before_creating_output
    File.write(@targets, "10.0.0.1\nexample.com\n")
    status, _, error, = app(['--dry-run'])
    assert_equal 2, status
    assert_match(/line 2/, error)
    refute Dir.exist?(@output_dir)
  end

  def test_public_ip_requires_confirmation
    File.write(@targets, "8.8.8.8\n")
    status, _, error, runner = app([])
    assert_equal 2, status
    assert_match(/confirm-public/, error)
    assert_empty runner.calls
  end

  def test_success_collects_each_worker_and_removes_only_owned_containers
    File.write(@targets, "10.0.0.1\n10.0.0.2\n10.0.0.3\n")
    status, _, _, runner = app(['--shard-size', '2', '--max-parallel', '2'])
    assert_equal 0, status
    assert_equal 'succeeded', manifest['status']
    assert_equal 2, runner.calls.count { |args| args[1] == 'rm' }
    assert_equal 2, Dir[File.join(@output_dir, '*', 'worker-*', 'results', 'demo.txt')].length
    assert runner.calls.grep(Array).all? { |args| args[1] != 'rm' || args[3].start_with?('deathstar-') }
  end

  def test_worker_failure_is_recorded_and_results_are_kept
    File.write(@targets, "10.0.0.1\n")
    status, _, _, = app([], runner: FakeRunner.new(fail_worker: true))
    assert_equal 1, status
    assert_equal 'failed', manifest['status']
    assert_equal 7, manifest['workers'][0]['exit_code']
    assert_equal 1, Dir[File.join(@output_dir, '*', 'worker-*', 'results', 'demo.txt')].length
  end

  def test_failed_docker_run_does_not_remove_existing_name
    File.write(@targets, "10.0.0.1\n")
    status, _, _, runner = app([], runner: FakeRunner.new(fail_run: true))
    assert_equal 1, status
    assert_equal 'failed', manifest['workers'][0]['status']
    refute runner.calls.any? { |args| args[1] == 'rm' }
  end

  def test_failed_cleanup_is_reported
    File.write(@targets, "10.0.0.1\n")
    status, _, _, = app([], runner: FakeRunner.new(fail_cleanup: true))
    assert_equal 1, status
    assert_match(/cleanup failed/, manifest['workers'][0]['error'])
  end

  def test_process_runner_reports_timeout
    result = DeathStar::ProcessRunner.new.run('ruby', '-e', 'sleep 5', timeout: 0.1)
    assert result.timed_out
    refute result.success?
  end
end
