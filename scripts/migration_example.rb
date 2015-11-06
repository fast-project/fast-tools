#!/usr/bin/env ruby

require 'optparse'
require 'thwait'

# benchmark configuration
PROC_QUEUE=["app0", "app1", "app2"]

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


# define command line options
options = {}

OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__}"

  opts.on("-v", "--verbose", "Print debug output") do |v|
    options[:verbose] = v 
  end
end.parse!

# start all VMs
DOMAIN_LOCATIONS.each do |vm, location|
  puts "`#{Dir.pwd}/start_vm_with_xml.sh #{vm} #{vm}.xml #{location}`"
end


# start first processes of the queue
running_jobs = []
running_jobs << Thread.new { puts `#{Dir.pwd}/#{PROC_QUEUE[0]}` }
running_jobs << Thread.new { puts `#{Dir.pwd}/#{PROC_QUEUE[1]}` }

# wait for first Job to terminate
ready_job = ThreadsWait.new(running_jobs).next_wait
running_jobs.delete(ready_job)
ready_job.join

# migrate in accordance with the configuration
migrate_jobs = []
MIGRATIONS.each do |vm, config|
  migrate_jobs << Thread.new { puts "`#{Dir.pwd}/migrate_vm.sh #{vm} #{config[:source]} #{config[:dest]}`" }
  DOMAIN_LOCATIONS[vm] = config[:dest]
end
ThreadsWait.all_waits(migrate_jobs)

# start third job
running_jobs << Thread.new { puts `#{Dir.pwd}/#{PROC_QUEUE[2]}` }

running_jobs.each do |job|
  job.join
end

# stop all VMs
DOMAIN_LOCATIONS.each do |vm, location|
  puts "`#{Dir.pwd}/stop_vm.sh #{vm} #{vm}.xml #{location}`"
end


