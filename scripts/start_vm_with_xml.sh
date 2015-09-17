#!/bin/bash

# define timer vars
dom_start_time=0
dom_stop_time=0
exec_time=0

# define some constants
PROGRAMNAME=$0

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

function usage {
    echo "usage: $PROGRAMNAME  <vm-name> <xml-config>"
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

vm=$1
xml=$2

# check parameters
if [ -z ${vm+1} ]; then
	echo "ERROR: You have to specify the VM you want to use. Abort!"
	exit
elif [ -z ${xml+1} ]; then
	echo "ERROR: You have to specify the XML you want to use. Abort!"
	exit
fi

# prepare the VM
virsh destroy $vm &> /dev/null
virsh define ${xml} > /dev/null

# start the VM and perform pinning
start_domain $vm
