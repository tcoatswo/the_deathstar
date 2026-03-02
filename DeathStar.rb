#!/usr/bin/env ruby
#
# DeathStar (v1.1)
# Author: Tyler Coatsworth
#
# Original concept: shard a target list across multiple Docker containers.
# This update preserves default behavior but adds:
# - environment-variable configuration
# - safer cleanup (only containers we create)
# - basic validation + optional public-target confirmation
# - removes global "stop all containers" behavior

require 'fileutils'
require 'ipaddr'

# ---------------------------
# Colors
# ---------------------------

def colorize(number, text)
  "\e[#{number}m#{text}\e[0m"
end

def red(text)    = colorize(31, text)

def green(text)  = colorize(32, text)

def amber(text)  = colorize(33, text)

def teal(text)   = colorize(36, text)

def blue(text)   = colorize(34, text)

# ---------------------------
# Config (defaults preserve original behavior)
# ---------------------------

IP_LIST    = ENV.fetch('IP_LIST', '/home/ubuntu/IPlist.txt')
OUTPUT_DIR = ENV.fetch('OUTPUT_DIR', '/home/ubuntu/SCAN-RESULTS/')
IMAGE      = ENV.fetch('IMAGE', 'ubuntu:v10')
EXEC_CMD   = ENV.fetch('EXEC_CMD', 'python start.py')

SHARD_SIZE = Integer(ENV.fetch('SHARD_SIZE', '10'))
MAX_MINUTES = Integer(ENV.fetch('MAX_MINUTES', '30'))
CONFIRM = ENV['CONFIRM']

TMP_SHARD = ENV.fetch('TMP_SHARD', '/tmp/deathstar_shard.txt')

raise "SHARD_SIZE must be > 0" if SHARD_SIZE <= 0
raise "MAX_MINUTES must be > 0" if MAX_MINUTES <= 0

# ---------------------------
# Helpers
# ---------------------------

def system_ok(cmd)
  ok = system(cmd)
  raise "Command failed: #{cmd}" unless ok
  ok
end

def docker_capture(cmd)
  `#{cmd}`.to_s
end

def deathstar_container_name(i)
  "deathstar#{i}"
end

def list_deathstar_containers
  out = docker_capture("docker ps -a --format '{{.Names}}'")
  out.lines.map(&:strip).select { |n| n.start_with?('deathstar') }
end

def cleanup_deathstars
  names = list_deathstar_containers
  return if names.empty?

  puts teal("STATUS: Cleaning up #{names.length} deathstar container(s)...")
  names.each do |name|
    system("docker rm -f #{name} > /dev/null 2>&1")
  end
end

def read_targets(path)
  raise "IP_LIST not found: #{path}" unless File.exist?(path)
  lines = File.read(path).lines.map { |l| l.strip }.reject(&:empty?)
  raise "IP_LIST is empty: #{path}" if lines.empty?
  lines
end

def looks_like_public_ip?(s)
  ip = IPAddr.new(s) rescue nil
  return false unless ip
  # Treat RFC1918 + loopback + link-local as non-public
  return false if ip.private? || ip.loopback? || ip.link_local?
  true
end

def confirm_if_public(targets)
  public_hits = targets.select { |t| looks_like_public_ip?(t) }
  return if public_hits.empty?
  return if CONFIRM.to_s.strip.upcase == 'YES'

  msg = <<~MSG
    WARNING: Your target list includes #{public_hits.length} public IP(s).
    This tool is intended for authorized testing only.

    To proceed, set CONFIRM=YES (recommended for automation) or type YES interactively.
  MSG

  puts red(msg)

  if $stdin.tty?
    print amber('Type YES to continue: ')
    answer = $stdin.gets.to_s.strip
    raise 'Aborted.' unless answer == 'YES'
  else
    raise 'Aborted (non-interactive). Set CONFIRM=YES to proceed.'
  end
end

# ---------------------------
# Core logic
# ---------------------------

def shard_count(target_count)
  (target_count.to_f / SHARD_SIZE).ceil
end

def write_shard(targets, start_index)
  shard = targets.slice(start_index, SHARD_SIZE) || []
  File.write(TMP_SHARD, shard.join("\n") + "\n")
  shard
end

def create_start_dockers(n)
  (1..n).each do |i|
    name = deathstar_container_name(i)
    system_ok("docker run --name #{name} -d -it #{IMAGE} > /dev/null")
  end
end

def copy_list_into_dockers(targets, n)
  idx = 0
  (1..n).each do |i|
    shard = write_shard(targets, idx)
    raise "Unexpected empty shard at #{i}" if shard.empty?

    name = deathstar_container_name(i)
    system_ok("docker cp #{TMP_SHARD} #{name}:/IPlist.txt")

    idx += SHARD_SIZE
  end
  FileUtils.rm_f(TMP_SHARD)
end

def exec_laser_startup(n)
  (1..n).each do |i|
    name = deathstar_container_name(i)
    system_ok("docker exec -d #{name} #{EXEC_CMD}")
    puts green("FIRING: #{name}")
  end
end

def recursive_timed_copy(n)
  FileUtils.mkdir_p(OUTPUT_DIR)
  puts amber("STATUS: Copying results once per minute for up to #{MAX_MINUTES} minute(s).")

  (1..MAX_MINUTES).each do |minute|
    (1..n).each do |i|
      name = deathstar_container_name(i)
      dest = File.join(OUTPUT_DIR, "#{name}-results")
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(dest)
      system("docker cp #{name}:/home/ #{dest} > /dev/null 2>&1")
      puts green("Copying Files from: #{name}")
    end

    puts amber("... Results from #{minute} minute(s)")
    sleep(60)
  end
end

# ---------------------------
# Main
# ---------------------------

puts teal('STATUS: Initializing Deathstar...')

cleanup_deathstars

targets = read_targets(IP_LIST)
confirm_if_public(targets)

n = shard_count(targets.length)
puts amber("Preparing to create #{n} deathstar(s) (#{SHARD_SIZE} targets per shard)")

create_start_dockers(n)

puts amber('---[LOCKING COORDINATES]---')
puts blue("Using IP_LIST: #{IP_LIST}")
puts blue("Using IMAGE:   #{IMAGE}")
puts blue("Using EXEC_CMD: #{EXEC_CMD}")
puts blue("Using OUTPUT_DIR: #{OUTPUT_DIR}")
puts

copy_list_into_dockers(targets, n)
puts green('STATUS: Shards loaded.')

puts teal('Countdown to the destruction of Alderaan:')
puts red('3...')
sleep(1)
puts amber('2...')
sleep(1)
puts green('1...')
sleep(1)
puts red('---[FIRING DEATH STAR]---')

exec_laser_startup(n)

puts red('---[COLLECTING RESULTS]---')
recursive_timed_copy(n)

puts teal('STATUS: Shutting down Deathstar...')
cleanup_deathstars
