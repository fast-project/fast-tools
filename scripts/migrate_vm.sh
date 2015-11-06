#!/bin/bash
VM=$1
SOURCE=$2
DEST=$3

# check parameters
if [ -z ${VM} ]; then
	echo "ERROR: You have to specify the VM you want to use. Abort!"
	exit
elif [ -z ${SOURCE} ]; then
	echo "ERROR: You have to specify the SOURCE host. Abort!"
	exit
elif [ -z ${DEST} ]; then
	echo "ERROR: You have to specify the DESTINATION host. Abort!"
	exit
fi

eval $verbose && echo -n "Migrating '${VM}' from '${SOURCE}' to '${DEST}' ... "
virsh -c qemu+ssh://${SOURCE}/system migrate ${VM} qemu+ssh://${DEST}/system > /dev/null
eval $verbose && echo "done"
