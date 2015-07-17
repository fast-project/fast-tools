#!/bin/bash

# define some constants
PROGRAMNAME=$0
SHUTDOWN_TIMEOUT=60
SSHUSER=$USER

# define default values
cmd="cat /sys/devices/system/cpu/present"
pinning="0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31"
guestmem=16384
vcpus=8

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

function usage {
    echo "usage: $PROGRAMNAME  --vm [--cmd] [--vcpus] [--guestmem] [-h]"
    echo "	--vm		name of the VM"
    echo "	--vcpus		VCPU count"
    echo "	--pinning	comma separated list of host CPUs for the pinning"
    echo "	--cmd		command to be executed"
    echo "	--guestmem	guest physical memory in MiB"
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

	# start domain
	echo -n "Starting '$domain' ... "
	virsh start $domain > /dev/null
	echo "done"
	
	# wait until online
	echo -n "Wait until '$domain' reachable ... "
#	while ! nc -z $domain 22; do
	while ! nmap -p 22 --open -sV $domain | grep "Host is up" > /dev/null; do
		sleep 1
	done
	
	# be sure domain is online
	sleep 1
	echo "done"
}

function stop_domain () {
	domain=$1
	
	# Try to shutdown each domain, one by one.
	running_domains=`list_running_domains`

	# Try to shutdown given domain.
	echo -n "Shutdown '$domain'  ... "
	if vm_running $domain; then
		virsh shutdown $domain > /dev/null
	fi

	# Wait until domain is shut off
	end_time=$(date -d "$SHUTDOWN_TIMEOUT seconds" +%s)
	while [ $(date +%s) -lt $end_time ]; do
		vm_running $domain || break
		sleep 1
	done
	
	# be sure domain is offline
	sleep 1
	echo "done"
}

function set_vcpu () {
	domain=$1
	cpucount=$2
	
	echo -n "Set vcpus to '$cpucount' ... "
	virsh setvcpus $domain --config --count $cpucount > /dev/null
	echo "done"
}

function set_guestmem () {
	domain=$1
	guestmem=$2
	echo $guestmem
	let "guestmem *= 1024"
	
	echo -n "Set guestmem to '$(($guestmem/1024)) MiB' ... "
	virsh setmaxmem $domain --config $guestmem > /dev/null
	virsh setmem $domain --config $guestmem > /dev/null
	echo "done"
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
	echo -n "Perform 1-to-1 pinning of VCPUs ... "
	for cpu in `seq 0 $maxvcpu`; do
		aryPos=$((cpu % pinningAryLength))
		virsh vcpupin $domain --config $cpu ${pinningAry[$aryPos]} > /dev/null
	done
	virsh emulatorpin $domain --config ${pinningAry[0]}-${pinningAry[$maxvcpu]} > /dev/null
	echo "done"
}

function exec_cmd() {
	domain=$1
	cmd=$2
	echo "Executing '$cmd' ..."
	ssh $SSHUSER@$domain $cmd
}

# determine options
vm_count=0
if ! options=$(getopt -o h -l help,vm:,cmd:,guestmem:,vcpus:,pinning: -- "$@")
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
	--vm)
		vm="$2"
		shift
		;;
	--cmd) 
		cmd="$2"
		shift
		;;
	--vcpus) 
		vcpus="$2"
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

# ensure *all* VMs are shut off
#for vm in `list_running_domains`; do
#	stop_domain $vm
#done

# prepare the VM
stop_domain $vm
#set_guestmem $vm $guestmem
#set_vcpu $vm $vcpus
#pin_vcpu $vm $vcpus $pinning
$DIR/set_host_topology.rb --cpus=$pinning --output=${vm}_newdef.xml --memory=$guestmem $vm
virsh define ${vm}_newdef.xml && rm ${vm}_newdef.xml

# start the VM and perform pinning
dom_start_time=$(date +%s)
start_domain $vm
dom_start_time=$(($(date +%s)-dom_start_time))

# start benchmark
exec_time=$(date +%s)
exec_cmd $vm "$cmd"
exec_time=$(($(date +%s)-exec_time))
#
## stop benchmark
dom_stop_time=$(date +%s)
stop_domain $vm
dom_stop_time=$(($(date +%s)-dom_stop_time))

printf "%3d %3d %3d\n" "$dom_start_time" "$dom_stop_time" "$exec_time"
