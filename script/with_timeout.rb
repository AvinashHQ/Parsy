# frozen_string_literal: true

require "timeout"

seconds = Integer(ARGV.shift || 90)
abort "usage: ruby script/with_timeout.rb SECONDS command ..." if ARGV.empty?

pid = Process.spawn(*ARGV, pgroup: true)
status = nil
begin
  Timeout.timeout(seconds) { status = Process.wait2(pid).last }
rescue Timeout::Error
  begin
    Process.kill("TERM", -pid)
  rescue Errno::ESRCH
  end
  sleep 2
  begin
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH
  end
  warn "command timed out after #{seconds}s"
  exit 124
end

exit(status.exitstatus || (status.signaled? ? 128 + status.termsig : 1))
