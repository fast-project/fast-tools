#!/bin/bash

# define timer vars
dom_start_time=0
dom_stop_time=0
exec_time=0

# define some constants
PROGRAMNAME=$0
SHUTDOWN_TIMEOUT=60
SSHUSER=$USER
TIMER="date +%s%N | cut -b1-13"

# define default values
cmd="cat /sys/devices/system/cpu/present"
pinning="0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31"
vcpus=8
guestmem=16384
verbose=false
shutdown=false

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

function usage {
    echo "usage: $PROGRAMNAME  --vm [--cmd] [--guestmem] [-h] [-v]"
    echo "	--vm		name of the VM"
    echo "	--pinning	comma separated list of host CPUs for the pinning"
    echo "	--cmd		command to be executed"
    echo "	--guestmem	guest physical memory in MiB"
    echo "	--vcpus		amount of virtual CPUs"
    echo "	-v/--verbose    be verbose"
    echo "	-h/--help	display help"
    exit 1
}

function list_running_domains {
	virsh list | grep running | awk '{ printf "%s ", $2 }'
}

function vm_running () {
	running_domains=`list_running_domains`
	
	if [[ $running_domains =~ "$1 " ]]; then
		return 0
	else
		return 1
	fi
}

function start_domain () {
	domain=$1
	
	# check distribution
	if cat /etc/*release |grep "SUSE Linux Enterprise Server 11" > /dev/null; then
		test_cmd='nc -z $domain 22'
	else
		test_cmd='nmap -p 22 --open -sV $domain | grep "Host is up" > /dev/null'
	fi
	
	# start domain
	eval $verbose && echo -n "Starting '$domain' ... "

	dom_start_time=$(eval $TIMER)
	virsh start $domain > /dev/null
	eval $verbose && echo "done"


	# wait until online (do not start nc too early)
	sleep 3 
	eval $verbose && echo -n "Wait until '$domain' reachable ... "
	while ! $(eval $test_cmd); do
		sleep 1
	done
	dom_start_time=$(($(eval $TIMER)-dom_start_time))
	
	# be sure domain is online
#	sleep 1
	eval $verbose && echo "done"
}

function stop_domain () {
	domain=$1
	
	# Try to shutdown each domain, one by one.
	running_domains=`list_running_domains`

	# Try to shutdown given domain.
	eval $verbose && echo -n "Shutdown '$domain'  ... "
	dom_stop_time=$(eval $TIMER)
	if vm_running $domain; then
		virsh shutdown $domain > /dev/null
	fi

	# Wait until domain is shut off
	end_time=$(date -d "$SHUTDOWN_TIMEOUT seconds" +%s)
	while [ $(date +%s) -lt $end_time ]; do
		vm_running $domain || break
	done
	
	# be sure domain is offline
	sleep 1

	dom_stop_time=$(($(eval $TIMER)-dom_stop_time))
	
	eval $verbose && echo "done"
}

function set_vcpu () {
	domain=$1
	cpucount=$2
	
	eval $verbose && echo -n "Set vcpus to '$cpucount' ... "
	virsh setvcpus $domain --config --count $cpucount > /dev/null
	eval $verbose && echo "done"
}

function set_guestmem () {
	domain=$1
	guestmem=$2
	eval $verbose && echo $guestmem
	let "guestmem *= 1024"
	
	eval $verbose && echo -n "Set guestmem to '$(($guestmem/1024)) MiB' ... "
	virsh setmaxmem $domain --config $guestmem > /dev/null
	virsh setmem $domain --config $guestmem > /dev/null
	eval $verbose && echo "done"
}

function pin_vcpu () {
	domain=$1
	maxvcpu=$[$2-1]
	pinning=$3

	# extract array from pinning string
	pinning=${pinning//,/ }
	pinningAry=($pinning)
	pinningAryLength=${#pinningAry[@]}
	
	# perform a 1-to-1 pinning
	eval $verbose && echo -n "Perform 1-to-1 pinning of VCPUs ... "
	for cpu in `seq 0 $maxvcpu`; do
		aryPos=$((cpu % pinningAryLength))
		virsh vcpupin $domain --config $cpu ${pinningAry[$aryPos]} > /dev/null
	done
	virsh emulatorpin $domain --config ${pinningAry[0]}-${pinningAry[$maxvcpu]} > /dev/null
	eval $verbose && echo "done"
}

function exec_cmd() {
	domain=$1
	cmd=$2
	eval $verbose && echo "Executing '$cmd' ..."
	exec_time=$(eval $TIMER)
	ssh $SSHUSER@$domain $cmd
	exec_time=$(($(eval $TIMER)-exec_time))
}

# determine options
vm_count=0
if ! options=$(getopt -o hv -l help,vcpus:,shutdown,verbose,vm:,cmd:,guestmem:,pinning: -- "$@")
then
    exit 1
fi
eval set -- $options
while [ $# -gt 0 ]; do
	case $1 in
	-h|--help) 
		usage
		exit
		;;
	-v|--verbose)
		verbose=true
		;;
	--vm)
		vm="$2"
		shift
		;;
	--cmd) 
		cmd="$2"
		shift
		;;
	--pinning) 
		pinning="$2"
		shift
		;;
	--guestmem) 
		guestmem="$2"
		shift
		;;
	--shutdown) 
		shutdown=true	
		;;
	--vcpus)
		vcpus="$2"
		shift
		;;
	(--) shift; break;;
	(-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
	(*) break;;
	esac
	shift
done

# check parameters
if [ -z ${vm+1} ]; then
	echo "ERROR: You have to specify at least the VM you want to use. Abort!"
	exit
fi

# do we only want to shutdown?
if $(eval $shutdown); then
	stop_domain $vm
	
	dom_stop_time=$(echo "scale=3;$dom_stop_time/1000" | bc)
	echo $dom_stop_time
	exit
fi

# prepare the VM
stop_domain $vm
$DIR/set_host_topology.rb --cpucount=$vcpus --cpus=$pinning --output=${vm}_newdef.xml --memory=$guestmem $vm > /dev/null
virsh define ${vm}_newdef.xml > /dev/null && rm ${vm}_newdef.xml

# start the VM and perform pinning
start_domain $vm

# start benchmark
exec_cmd $vm "$cmd"
#

# convert times to seconds
dom_start_time=$(echo "scale=3;$dom_start_time/1000" | bc)
exec_time=$(echo "scale=3;$exec_time/1000" | bc)

echo -e "$dom_start_time"
