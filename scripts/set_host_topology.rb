#!/usr/bin/env ruby

require 'nokogiri'
require 'optparse'

HT_ORDER=1

class Host
  attr_accessor :cells

  def initialize(xml_str=nil)
    @xml = Nokogiri::XML(xml_str) unless xml_str == nil
    extract_topology
  end

  private
  def extract_topology
    @cells = []
    @xml.css('cpus').each do |cell|
      cur_cell = []
      cell.children.each do |cpu|
        next unless cpu.to_s[0].eql?("<") # TODO: dirty hack, can we do it better?
        cur_cell << cpu.attributes['id'].to_s.to_i if cpu.attributes['id'].instance_of?(Nokogiri::XML::Attr)
      end
      @cells << cur_cell
    end
  end
end

class Memory
  attr_reader :unit, :size

  def initialize(memory_node)
    @unit = memory_node['unit']
    @size = memory_node.content.to_i
  end
end

class Vcpu
  attr_reader :id
  attr_reader :phys_cpu
  attr_accessor :socket

  def initialize(id, phys_cpu)
    @id = id.to_i
    @phys_cpu = phys_cpu.to_i
    @sibling = nil
    @socket = nil
  end
end

class Domain
  attr_reader :xml

  def initialize(xml_str=nil)
    @xml = Nokogiri::XML(xml_str) unless xml_str == nil
    @vcpus = []
  end

  def to_s
    @xml.to_xml(:save_with => Nokogiri::XML::Node::SaveOptions::AS_XML).sub("\n", "").strip
  end

  def set_vcpus(vcpu_count)
    vcpu = @xml.at_css("vcpu")
    vcpu.attributes['placement'].value = 'static'
    vcpu.content = vcpu_count
  end
  
  def pin_vcpus(cpus)
    # retrieve relevant XML part 
    cputune = @xml.at_css("cputune")
    text_content=cputune.children.first.content
    last_text_content=cputune.children.last.content
    cputune.children.remove

    # create VCPUs
    map_vcpus(cpus)

    # update XML
    @vcpus.each do |vcpu|
      cputune.add_child(Nokogiri::XML::Text.new text_content, @xml)
      child = Nokogiri::XML::Node.new('vcpupin', @xml)
      child['vcpu'] = "#{vcpu.id}"
      child['cpuset'] = "#{vcpu.phys_cpu}"
      cputune.add_child(child)
    end
    cputune.add_child(Nokogiri::XML::Text.new last_text_content, @xml)
  end

  def set_memory(memory)
    ['memory','currentMemory'].each do |nodeName|
    	node = @xml.at_css(nodeName)
  	node.content = (memory*1024).to_i
    end
  end

  def adapt_host_topology(host)
    determine_sockets(host)

    # get Domain's memory info
    memory = Memory.new(@xml.at_css('memory'))

    # create <numa> node from XML
    numa = Nokogiri::XML::Node.new('numa', @xml)
    @cells.each_with_index do |cell, index|
      new_cell = Nokogiri::XML::Node.new('cell', @xml)
      new_cell['id'] = index.to_s 
      new_cell['cpus'] = cell.join(",")
      new_cell['memory'] = (memory.size/@cells.length).to_i
      new_cell['unit'] = memory.unit
      numa.add_child(new_cell)
    end 

    # create <topology> node
    topology = Nokogiri::XML::Node.new('topology', @xml)
    topology['sockets'] = @cells.length.to_s
    topology['cores'] = @cells.max_by(&:length).length.to_s
    topology['threads'] = HT_ORDER

    # remove old nodes
    @xml.css("numa").remove
    @xml.css("topology").remove

    # add <numa> and <topology> node to <cpu> node
    cpu = @xml.at_css("cpu")
    cpu.add_child(numa)
    cpu.add_child(topology)
  end

  private
  def map_vcpus(cpus)
    cpus.each_with_index do |cpu, index|
      @vcpus << Vcpu.new(index, cpu)
    end
  end

  def determine_sockets(host)
    # assign socket to VCPUs
    @vcpus.each do |vcpu|
      host.cells.each_with_index do |cell, index|
        if (cell.include?(vcpu.phys_cpu)) then
          vcpu.socket = index
          break
        end
      end
    end

    # define cells
    @cells = []
    host.cells.each_with_index do |cell, index|
      cur_socket = @vcpus.select { |vcpu| vcpu.socket == index }.map { |vcpu| vcpu.id }
      @cells << cur_socket unless cur_socket.empty?
    end
  end
end


# define command line options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: #{__FILE__} [options] <domain>"

  opts.on("-cCPUs", "--cpus=x,y", Array, "A list of physical CPUs assigned to the VM") do |cpus|
    options[:cpus] = cpus
  end

  opts.on("-vCPUCNT", "--cpucount=CPUCNT", "Amount of CPUs taken from the list") do |cpucnt|
    options[:cpucnt] = cpucnt.to_i
  end

  opts.on("-mMEMORY", "--memory=MEMORY", "Amount of memory assigned to the VM") do |memory|
    options[:memory] = memory.to_i
  end

  opts.on("-oOUTPUT", "--output=OUTPUT", String, "Filename of the new domain definition") do |output|
    options[:output] = output
  end
end.parse!

# retrieve domain name from first command line argument
if ((options[:domain] = ARGV[0]) == nil) then
  puts "ERROR: The 'domain' has to be specified. Abort!"
  exit
end

# retrieve the current XML definition and create domain
xml_str=''
IO.popen("virsh dumpxml #{options[:domain]}", "r+") do |pipe|
  pipe.close_write
  xml_str=pipe.read
end
domain = Domain.new(xml_str)

IO.popen("virsh capabilities", "r+") do |pipe|
  pipe.close_write
  xml_str=pipe.read
end

host = Host.new(xml_str)

domain.set_memory(options[:memory])
domain.set_vcpus(options[:cpucnt])
domain.pin_vcpus(options[:cpus].first(options[:cpucnt]))
domain.adapt_host_topology(host)

if (options[:output]) 
  File.write(options[:output], domain.to_s)
else
  puts domain.to_s
end

