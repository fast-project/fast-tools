#!/usr/bin/env ruby

require 'nokogiri'
require 'optparse'

class Domain
  attr_reader :xml

  def initialize(xml_str=nil)
    @xml = Nokogiri::XML(xml_str) unless xml_str == nil
  end

  def to_string
    @xml.to_xml
  end

  def set_vcpus(vcpu_count)
    vcpu = @xml.at_css("vcpu")
    vcpu.attributes['placement'].value = 'static'
    vcpu.content = vcpu_count
  end
  
  def pin_vcpus(cpus)
    cputune = @xml.at_css("cputune")
    text_content=cputune.children.first.content
    last_text_content=cputune.children.last.content
    cputune.children.remove
    cpus.each_with_index do |cpu, index|
      cputune.add_child(Nokogiri::XML::Text.new text_content, @xml)
      child = Nokogiri::XML::Node.new('vcpupin', @xml)
      child['vcpu'] = "#{index}"
      child['cpuset'] = "#{cpu}"
      cputune.add_child(child)
    end
    cputune.add_child(Nokogiri::XML::Text.new last_text_content, @xml)
  end
end


# define command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options]"

  opts.on("-dDOMAIN", "--domain=DOMAIN", String, :required, "Name of the libvirt domain to be modified") do |d|
    options[:domain] = d
  end

  opts.on("-cCPUs", "--cpus=x,y", Array, :required, "A list of physical CPUs assigned to the VM") do |c|
    options[:cpus] = c
  end

  opts.on("-oOUTPUT", "--output=OUTPUT", String, :required, "Filename of the new domain definition") do |o|
    options[:output] = o
  end
end.parse!

if (options[:domain] == nil) then
  puts "ERROR: The 'domain' has to be specified. Abort!"
  exit
end


# retrieve the current XML definition
xml_str=''
IO.popen("virsh dumpxml #{options[:domain]}", "r+") do |pipe|
  pipe.close_write
  xml_str=pipe.read
end

# create new domain from xml-string
domain = Domain.new(xml_str)

domain.set_vcpus(options[:cpus].length)
domain.pin_vcpus(options[:cpus])

File.write(options[:output], domain.to_string) unless options[:output] == nil


