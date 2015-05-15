#!/bin/bash

# define some constants
MAXMEM=16384
MINCPU=1
MAXCPU=32
PROGRAMNAME=$0
SHUTDOWN_TIMEOUT=60
SSHUSER='dummy'

# define dummy cmd
cmd0="cat /sys/devices/system/cpu/present"
cmd1="cat /sys/devices/system/cpu/present"

function usage {
    echo "usage: $PROGRAMNAME  [--vm0/1] [--cmd0/1] [-h]"
    echo "	--vm0/1		name of VM 0/1"
    echo "	--cmd0/1	command to be executed on VM 0/1"
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
	virsh start $domain > /dev/null
	
	# wait until online
	while ! nc -z $domain 22; do
		sleep 1
	done
	
	# be sure domain is online
	sleep 1
}

function stop_domain () {
	domain=$1
	
	# Try to shutdown each domain, one by one.
	running_domains=`list_running_domains`

	# Try to shutdown given domain.
	if vm_running $domain; then
		virsh shutdown $domain > /dev/null
	else
		return
	fi

	# Wait until domain is shut off
	end_time=$(date -d "$SHUTDOWN_TIMEOUT seconds" +%s)
	while [ $(date +%s) -lt $end_time ]; do
		vm_running $domain || break
		sleep 1
	done
	
	# be sure domain is offline
	sleep 1
}

function set_vcpu () {
	domain=$1
	cpucount=$2

	virsh setvcpus $domain --config --count $cpucount > /dev/null
}

function pin_vcpu () {
	domain=$1
	maxvcpu=$[$2-1]

	# perform a 1-to-1 pinning
	for cpu in `seq 0 $maxvcpu`; do
		virsh vcpupin $domain --live $cpu $cpu > /dev/null
	done
}

function exec_cmd() {
	ssh $SSHUSER@$domain $cmd0
}

# determine options
vm_count=0
if ! options=$(getopt -o h -l help,vm0:,vm1:,cmd0:,cmd1: -- "$@")
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
	--vm0)
		vm_count=$[$vm_count+1]
		vm0="$2"
		shift
		;;
	--vm1) 
		vm_count=$[$vm_count+1]
		vm1="$2"
		shift
		;;
	--cmd0) 
		cmd0="$2"
		shift
		;;
	--cmd1) 
		cmd1="$2"
		shift
		;;
	(--) shift; break;;
	(-*) echo "$0: error - unrecognized option $1" 1>&2; exit 1;;
	(*) break;;
	esac
	shift
done

# ensure *all* VMs are shut off
for vm in `list_running_domains`; do
	echo -n "Shutting down '$vm' ... "
	stop_domain $vm
	echo "done"
done

# use one VM only
function one_process() {
	domain=$1
	cmd=$2

	for cpucount in `seq $MINCPU $MAXCPU`; do
		set_vcpu $domain $cpucount
		start_domain $domain
		pin_vcpu $domain $cpucount
		exec_cmd $domain $cmd
		stop_domain $domain
	done 
}



# start benchmark in accordance with VM count
case $vm_count in 
	1)
		if [[ $vm0 ]]; then
			one_process $vm0 $cmd0
		else 
			one_process $vm1 $cmd0
		fi
		;;
	2)
		echo "Starting two processes ..."
		;;
	*)
		echo "ERROR: You need to specify at least one VM. Abort!"
		;;
esac
