#!/bin/bash
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOMAIN=fast-vm-base
HOSTS=( fast-01 fast-02 fast-03 )
HOST_CNT=${#HOSTS[@]}

MOSQUITTO_SUB=/cluster/fast/mosquitto/mosquitto_sub
MOSQUITTO_PUB=/cluster/fast/mosquitto/mosquitto_pub

QUIT_STRING=$( cat <<END

---
task: quit
...
END
)


for host in $@; do
	${MOSQUITTO_PUB} -h fast-login -t fast/migfra/${host}/task -m "${QUIT_STRING}"
done
