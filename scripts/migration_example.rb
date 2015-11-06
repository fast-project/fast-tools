#!/usr/bin/env ruby

require 'optparse'
require 'thwait'
require 'net/ssh'
require 'etc'

# benchmark configuration
PROC_QUEUE={
  "app0" => "centos7110",
  "app1" => "centos7112", 
  "app2" => "centos7110"
}

DOMAIN_LOCATIONS={
  "centos7110" => "pandora3",
  "centos7111" => "pandora3",
  "centos7112" => "pandora4",
  "centos7113" => "pandora4",
}
MIGRATIONS={
  "centos7111" => {source: "pandora3", dest: "pandora4"},
  "centos7113" => {source: "pandora4", dest: "pandora3"},
}

def exec_cmd_via_ssh(cmd, host)
  Net::SSH.start(host, Etc.getlogin) do |session| 
    puts session.exec!(cmd) 
  end
end

# define command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__}"

  opts.on("-v", "--verbose", "Print debug output") do |v|
      options[:verbose] = v
  end
end.parse!
options[:verbose] = false if options[:verbose].nil?

# start all VMs
start_jobs = []
DOMAIN_LOCATIONS.each do |vm, location|
  start_jobs << Thread.new { `verbose=#{options[:verbose]} #{Dir.pwd}/start_vm_with_xml.sh #{vm} #{vm}.xml #{location}` }
end
ThreadsWait.all_waits(start_jobs)


# start first processes of the queue
running_jobs = []
[PROC_QUEUE.keys[0], PROC_QUEUE.keys[1]].each do |cmd|
  running_jobs << Thread.new { exec_cmd_via_ssh("#{Dir.pwd}/#{cmd}", PROC_QUEUE[cmd]) }
end

# wait for first Job to terminate
ready_job = ThreadsWait.new(running_jobs).next_wait
running_jobs.delete(ready_job)
ready_job.join

# migrate in accordance with the configuration
migrate_jobs = []
MIGRATIONS.each do |vm, config|
  migrate_jobs << Thread.new { `verbose=#{options[:verbose]} #{Dir.pwd}/migrate_vm.sh #{vm} #{config[:source]} #{config[:dest]}` }
  DOMAIN_LOCATIONS[vm] = config[:dest]
end
ThreadsWait.all_waits(migrate_jobs)

# start third job
cmd = PROC_QUEUE.keys[2]
running_jobs << Thread.new { exec_cmd_via_ssh("#{Dir.pwd}/#{cmd}", PROC_QUEUE[cmd]) }

running_jobs.each do |job|
  job.join
end

# stop all VMs
stop_jobs = []
DOMAIN_LOCATIONS.each do |vm, location|
  stop_jobs << Thread.new { `verbose=#{options[:verbose]} #{Dir.pwd}/stop_vm.sh #{vm} #{location}` }
end
ThreadsWait.all_waits(stop_jobs)


