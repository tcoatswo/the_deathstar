#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'ipaddr'
require 'json'
require 'optparse'
require 'securerandom'
require 'tempfile'
require 'thread'
require 'timeout'
require 'time'

module DeathStar
  class Error < StandardError; end

  Result = Struct.new(:status, :stdout, :stderr, :timed_out, keyword_init: true) do
    def success? = !timed_out && status == 0
  end

  class ProcessRunner
    def run(*args, timeout:, stdout_path: nil, stderr_path: nil)
      Tempfile.create('deathstar-stdout') do |temporary_stdout|
        Tempfile.create('deathstar-stderr') do |temporary_stderr|
          out = stdout_path ? File.open(stdout_path, 'w') : temporary_stdout
          err = stderr_path ? File.open(stderr_path, 'w') : temporary_stderr
          pid = Process.spawn(*args, in: File::NULL, out: out, err: err, pgroup: true)
          timed_out = false
          status = begin
            Timeout.timeout(timeout) { Process.waitpid2(pid).last.exitstatus }
          rescue Timeout::Error
            timed_out = true
            Process.kill('KILL', -pid) rescue nil
            Process.waitpid(pid) rescue nil
            nil
          end
          out.flush
          err.flush
          Result.new(status: status,
                     stdout: stdout_path ? '' : File.read(temporary_stdout.path),
                     stderr: stderr_path ? '' : File.read(temporary_stderr.path),
                     timed_out: timed_out)
        ensure
          out.close if stdout_path && out && !out.closed?
          err.close if stderr_path && err && !err.closed?
        end
      end
    end
  end

  class App
    DEFAULTS = {
      ip_list: '/home/ubuntu/IPlist.txt', output_dir: '/home/ubuntu/SCAN-RESULTS',
      image: 'ubuntu:v10', command: 'python start.py', shard_size: 10,
      max_parallel: 4, timeout: 1800, docker_timeout: 60
    }.freeze

    def initialize(argv, env: ENV, input: $stdin, output: $stdout, error: $stderr, runner: ProcessRunner.new)
      @argv, @env, @input, @output, @error, @runner = argv, env, input, output, error, runner
      @config = DEFAULTS.dup
      @config[:ip_list] = env.fetch('IP_LIST', @config[:ip_list])
      @config[:output_dir] = env.fetch('OUTPUT_DIR', @config[:output_dir])
      @config[:image] = env.fetch('IMAGE', @config[:image])
      @config[:command] = env.fetch('EXEC_CMD', @config[:command])
      %i[shard_size max_parallel timeout docker_timeout].each do |key|
        @config[key] = env.fetch(key.to_s.upcase, @config[key])
      end
      @config[:confirm_public] = env['CONFIRM'].to_s.upcase == 'YES'
      @config[:dry_run] = false
      @config[:keep_containers] = false
      @active = {}
      @lock = Mutex.new
    end

    def run
      parse_options
      return 0 if @help
      File.umask(0o077)
      validate_config
      targets = read_targets
      confirm_public(targets) unless @config[:dry_run]
      shards = targets.each_slice(@config[:shard_size]).to_a
      docker!('version', '--format', '{{.Server.Version}}') unless @config[:dry_run]
      run_id = "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{SecureRandom.hex(4)}"
      run_dir = File.join(File.expand_path(@config[:output_dir]), run_id)
      manifest = {
        run_id: run_id, started_at: Time.now.utc.iso8601, status: @config[:dry_run] ? 'planned' : 'running',
        config: @config.reject { |k, _| k == :confirm_public }, target_count: targets.length,
        workers: shards.each_with_index.map do |shard, i|
          { index: i + 1, container: "deathstar-#{run_id.downcase}-#{i + 1}",
            target_count: shard.length, status: 'planned' }
        end
      }
      FileUtils.mkdir_p(run_dir)
      shards.each_with_index do |shard, i|
        worker_dir = File.join(run_dir, format('worker-%04d', i + 1))
        FileUtils.mkdir_p(worker_dir)
        File.write(File.join(worker_dir, 'targets.txt'), shard.join("\n") + "\n")
      end
      save_manifest(run_dir, manifest)
      @output.puts "Run: #{run_dir} (#{targets.length} targets, #{shards.length} workers)"
      return 0 if @config[:dry_run]

      queue = Queue.new
      shards.each_index { |i| queue << i }
      threads = Array.new([@config[:max_parallel], shards.length].min) do
        Thread.new do
          loop do
            i = queue.pop(true) rescue break
            process_worker(i, run_dir, manifest)
          end
        end
      end
      threads.each(&:join)
      manifest[:finished_at] = Time.now.utc.iso8601
      manifest[:status] = manifest[:workers].all? { |w| w[:status] == 'succeeded' } ? 'succeeded' : 'failed'
      save_manifest(run_dir, manifest)
      @output.puts "Completed: #{manifest[:workers].count { |w| w[:status] == 'succeeded' }}/#{shards.length} succeeded"
      manifest[:status] == 'succeeded' ? 0 : 1
    rescue OptionParser::ParseError, ArgumentError, SystemCallError, Error => e
      @error.puts "Error: #{e.message}"
      2
    rescue Interrupt
      @error.puts 'Interrupted; finalizing the run.'
      threads&.each(&:kill)
      threads&.each(&:join)
      cleanup_active unless @config[:keep_containers]
      if manifest && run_dir
        manifest[:workers].each { |worker| worker[:status] = 'interrupted' if %w[planned running].include?(worker[:status]) }
        manifest[:status] = 'interrupted'
        manifest[:finished_at] = Time.now.utc.iso8601
        save_manifest(run_dir, manifest)
      end
      130
    end

    private

    def parse_options
      parser = OptionParser.new do |o|
        o.banner = 'Usage: ruby DeathStar.rb [options]'
        o.on('--ip-list PATH', 'File with one IP address per line') { |v| @config[:ip_list] = v }
        o.on('--output-dir PATH', 'Directory for per-run results') { |v| @config[:output_dir] = v }
        o.on('--image IMAGE', 'Docker worker image') { |v| @config[:image] = v }
        o.on('--command COMMAND', 'Command run inside each worker via sh -lc') { |v| @config[:command] = v }
        o.on('--shard-size N', Integer, 'Targets per worker') { |v| @config[:shard_size] = v }
        o.on('--max-parallel N', Integer, 'Concurrent workers') { |v| @config[:max_parallel] = v }
        o.on('--timeout SECONDS', Integer, 'Seconds allowed for each worker command') { |v| @config[:timeout] = v }
        o.on('--docker-timeout SECONDS', Integer, 'Seconds allowed for Docker setup and copy commands') { |v| @config[:docker_timeout] = v }
        o.on('--confirm-public', 'Confirm authorization for public IPs') { @config[:confirm_public] = true }
        o.on('--dry-run', 'Validate and write a plan without using Docker') { @config[:dry_run] = true }
        o.on('--keep-containers', 'Keep worker containers after the run') { @config[:keep_containers] = true }
        o.on('-h', '--help', 'Show help') { @output.puts o; @help = true }
      end
      parser.parse!(@argv)
      raise Error, "Unexpected arguments: #{@argv.join(' ')}" unless @argv.empty?
    end

    def validate_config
      %i[shard_size max_parallel timeout docker_timeout].each do |key|
        @config[key] = Integer(@config[key])
        raise Error, "#{key} must be greater than zero" unless @config[key].positive?
      end
      %i[ip_list output_dir image command].each do |key|
        raise Error, "#{key} must not be empty" if @config[key].to_s.strip.empty?
      end
    end

    def read_targets
      raise Error, "Target file not found: #{@config[:ip_list]}" unless File.file?(@config[:ip_list])
      seen = {}
      targets = []
      File.foreach(@config[:ip_list]).with_index(1) do |line, number|
        target = line.split('#', 2).first.to_s.strip
        next if target.empty?
        raise Error, "Invalid IP address at line #{number}: #{target}" if target.include?('/') || !valid_ip?(target)
        canonical = IPAddr.new(target).to_s
        next if seen[canonical]
        seen[canonical] = true
        targets << target
      end
      raise Error, "No IP addresses found in #{@config[:ip_list]}" if targets.empty?
      targets
    end

    def valid_ip?(target)
      IPAddr.new(target)
      true
    rescue IPAddr::InvalidAddressError
      false
    end

    def confirm_public(targets)
      public_count = targets.count do |target|
        ip = IPAddr.new(target)
        !ip.private? && !ip.loopback? && !ip.link_local?
      end
      return if public_count.zero? || @config[:confirm_public]
      raise Error, "#{public_count} public IP(s) require --confirm-public or CONFIRM=YES" unless @input.tty?
      @output.print "#{public_count} public IP(s). Confirm authorized scope by typing YES: "
      raise Error, 'Authorization not confirmed' unless @input.gets.to_s.strip == 'YES'
    end

    def process_worker(i, run_dir, manifest)
      worker = manifest[:workers][i]
      name = worker[:container]
      worker_dir = File.join(run_dir, format('worker-%04d', i + 1))
      update_worker(run_dir, manifest, i, status: 'running', started_at: Time.now.utc.iso8601)
      created = false
      begin
        docker!('run', '-d', '--name', name, '--label', "com.deathstar.run=#{manifest[:run_id]}", @config[:image])
        created = true
        @lock.synchronize { @active[name] = true }
        docker!('cp', File.join(worker_dir, 'targets.txt'), "#{name}:/IPlist.txt")
        result = @runner.run('docker', 'exec', name, 'sh', '-lc', @config[:command],
                             timeout: @config[:timeout],
                             stdout_path: File.join(worker_dir, 'stdout.log'),
                             stderr_path: File.join(worker_dir, 'stderr.log'))
        FileUtils.mkdir_p(File.join(worker_dir, 'results'))
        copy = @runner.run('docker', 'cp', "#{name}:/home/.", File.join(worker_dir, 'results'),
                           timeout: @config[:docker_timeout])
        problems = []
        problems << (result.timed_out ? 'Worker timed out' : "Worker exit code #{result.status}") unless result.success?
        problems << "Result copy failed: #{copy.timed_out ? 'timed out' : copy.stderr.strip}" unless copy.success?
        state = problems.empty? ? 'succeeded' : 'failed'
        update_worker(run_dir, manifest, i, status: state, exit_code: result.status,
                      timed_out: result.timed_out, error: problems.join('; '), finished_at: Time.now.utc.iso8601)
      rescue StandardError => e
        update_worker(run_dir, manifest, i, status: 'failed', error: e.message, finished_at: Time.now.utc.iso8601)
      ensure
        if created && !@config[:keep_containers]
          begin
            removal = @runner.run('docker', 'rm', '-f', name, timeout: @config[:docker_timeout])
            if removal.success?
              @lock.synchronize { @active.delete(name) }
            else
              update_worker(run_dir, manifest, i, status: 'failed',
                            error: "Container cleanup failed: #{removal.timed_out ? 'timed out' : removal.stderr.strip}")
            end
          rescue StandardError => e
            update_worker(run_dir, manifest, i, status: 'failed', error: "Container cleanup failed: #{e.message}")
          end
        end
      end
      @output.puts "Worker #{i + 1}: #{manifest[:workers][i][:status]}"
    end

    def docker!(*args)
      result = @runner.run('docker', *args, timeout: @config[:docker_timeout])
      return result if result.success?
      detail = result.timed_out ? 'timed out' : result.stderr.strip
      raise Error, "docker #{args.first} failed: #{detail}"
    rescue Errno::ENOENT
      raise Error, 'Docker executable not found in PATH'
    end

    def update_worker(run_dir, manifest, i, changes)
      @lock.synchronize do
        manifest[:workers][i].merge!(changes)
        save_manifest(run_dir, manifest)
      end
    end

    def save_manifest(run_dir, manifest)
      path = File.join(run_dir, 'manifest.json')
      temp = "#{path}.tmp"
      File.write(temp, JSON.pretty_generate(manifest) + "\n")
      File.rename(temp, path)
    end

    def cleanup_active
      names = @lock.synchronize { @active.keys }
      names.each { |name| @runner.run('docker', 'rm', '-f', name, timeout: @config[:docker_timeout]) rescue nil }
    end
  end
end

exit DeathStar::App.new(ARGV).run if $PROGRAM_NAME == __FILE__
