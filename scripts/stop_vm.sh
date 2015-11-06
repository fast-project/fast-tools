#!/bin/bash
VM=$1
HOST=$2

function list_running_domains {
	virsh -c qemu+ssh://${HOST}/system list | grep running | awk '{ printf "%s ", $2 }'
}

function vm_running () {
	running_domains=`list_running_domains`
	
	if [[ $running_domains =~ "$1 " ]]; then
		return 0
	else
		return 1
	fi
}

function stop_domain () {
	domain=$1
	
	# Try to shutdown each domain, one by one.
	running_domains=`list_running_domains`

	# Try to shutdown given domain.
	eval $verbose && echo -n "Shutdown '$domain'  ... "
	dom_stop_time=$(eval $TIMER)
	if vm_running $domain; then
		virsh -c qemu+ssh://${HOST}/system shutdown $domain > /dev/null
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


if [ -z ${HOST+1} ]; then
	HOST=localhost
fi

stop_domain $VM $HOST
