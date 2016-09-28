#!/bin/bash

# Defines the virsh-list-all command which lists all active domains on the specified nodes.
# Add this script to your .bashrc in order to have the command available straight after login.
virsh-list-all () {
	local nodes=("pandora0" "pandora1" "pandora2" "pandora3" "pandora4")
	local node
	for node in ${nodes[*]}; do
		echo "$node:"
		virsh -c qemu+ssh://$node/system list
	done
}
