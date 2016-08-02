#!/bin/bash
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DOMAIN=fast-vm-base
HOSTS=( fast-01 fast-02 fast-03 )
HOST_CNT=${#HOSTS[@]}

MOSQUITTO_SUB=/cluster/fast/mosquitto/mosquitto_sub
MOSQUITTO_PUB=/cluster/fast/mosquitto/mosquitto_pub

MIGRATE_STRING=$( cat <<END

---
task: migrate vm
vm-name: fast-vm-base
destination: %s
parameter:
  migration-type: warm
...
END
)

STOP_STRING=$( cat <<END

---
id: test-id
task: stop vm
list:
  - vm-name: %s
...
END
)

START_STRING_WITH_XML=$( cat <<END

---
task: start vm
vm-configurations:
  - xml: "<domain type='kvm'>
  <name>fast-vm-base</name>
  <uuid>8e969da1-79ba-488d-a950-ecc32d19737b</uuid>
  <memory unit='KiB'>1048576</memory>
  <currentMemory unit='KiB'>1048576</currentMemory>
  <memtune>
    <hard_limit unit='KiB'>35651584</hard_limit>
  </memtune>
  <vcpu placement='static'>8</vcpu>
  <os>
    <type arch='x86_64' machine='pc-i440fx-2.5'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <cpu mode='custom' match='exact'>
    <model fallback='allow'>SandyBridge</model>
  </cpu>
  <clock offset='utc'>
    <timer name='rtc' tickpolicy='catchup'/>
    <timer name='pit' tickpolicy='delay'/>
    <timer name='hpet' present='no'/>
  </clock>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <pm>
    <suspend-to-mem enabled='no'/>
    <suspend-to-disk enabled='no'/>
  </pm>
  <devices>
    <emulator>/cluster/qemu-2.5.1.1/bin/qemu-system-x86_64</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2' cache='none'/>
      <source file='/cluster/vm-images/ubuntu15010/fast-vm-base.qcow2'/>
      <target dev='vda' bus='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x08' function='0x0'/>
    </disk>
    <disk type='block' device='cdrom'>
      <driver name='qemu' type='raw' cache='none'/>
      <target dev='hdb' bus='ide'/>
      <readonly/>
      <address type='drive' controller='0' bus='0' target='0' unit='1'/>
    </disk>
    <controller type='usb' index='0' model='ich9-ehci1'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x7'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci1'>
      <master startport='0'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0' multifunction='on'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci2'>
      <master startport='2'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x1'/>
    </controller>
    <controller type='usb' index='0' model='ich9-uhci3'>
      <master startport='4'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x2'/>
    </controller>
    <controller type='pci' index='0' model='pci-root'/>
    <controller type='ide' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <controller type='virtio-serial' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </controller>
    <interface type='bridge'>
      <mac address='52:54:00:86:f1:7f'/>
      <source bridge='br0'/>
      <model type='rtl8139'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='mouse' bus='ps2'/>
    <input type='keyboard' bus='ps2'/>
    <graphics type='spice' autoport='yes'/>
    <sound model='ich6'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </sound>
    <video>
      <model type='qxl' ram='65536' vram='65536' vgamem='16384' heads='1' primary='yes'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x07' function='0x0'/>
    </memballoon>
  </devices>
</domain>"
    pci-ids:
      - vendor: 0x15b3
        device: 0x1002
...
END
)


function waitForSuccess {
	HOST=$1
	if ${MOSQUITTO_SUB} -C 1 -t fast/migfra/${HOST}/result | grep "success" > /dev/null; then
		return 1
	else
		return 0
	fi
}

# start $DOMAIN
function startDomain {
	HOST=${1}
	echo -n "Step ${step}: INFO: Start ${DOMAIN} on ${HOST} "
	waitForSuccess ${HOST} &
	${MOSQUITTO_PUB} -h fast-login -t fast/migfra/${HOST}/task -m "${START_STRING_WITH_XML}"
	wait %1 && echo " - failed" && echo "Step ${step}: ERROR: Could not start ${DOMAIN} on ${HOST}" && exit
	echo "- done"
}

# start $DOMAIN
function stopDomain {
	HOST=${1}
	echo -n "Step ${step}: INFO: Stop ${DOMAIN} on ${HOST}"

	printf -v msg "${STOP_STRING}" "${DOMAIN}"
	waitForSuccess ${HOST} &
	${MOSQUITTO_PUB} -h fast-login -t fast/migfra/${HOST}/task -m "${msg}"
	wait %1 && echo " - failed" && echo "Step ${step}: ERROR: Could not stop ${DOMAIN} on ${HOST}" && exit
	echo " - done"
}

# migrate $DOMAIN
function migrateDomain {
	SOURCE=${1}
	DEST=${2}

	echo -n "Step ${step}: INFO: Migrate ${DOMAIN} from ${SOURCE} to ${DEST}"
	printf -v msg "${MIGRATE_STRING}" "${DEST}"
	waitForSuccess ${SOURCE} &
	${MOSQUITTO_PUB} -h fast-login -t fast/migfra/${SOURCE}/task -m "${msg}"
	wait %1 && echo " - failed" && echo "Step ${step}: ERROR: Could not migrate ${DOMAIN} from ${SOURCE} to ${DEST}" && exit
	echo " - done"
}


# check if IB is available
function checkIB {
	HOST=$1
	local RET
	echo -n "Step ${step}: INFO: Check IB on ${HOST}"
	RET=$(ssh ${HOST} ibstatus &> /dev/null)
	if [ $? -ne 0 ]; then
		echo " - failed "
		echo "Step ${step}: ERROR: IB not available on ${HOST}"
		exit
	else
		echo " - done"
		return
	fi
}
step=0

for host in ${!HOSTS[@]}; do
	NEXT_IDX=$(( (host+1) % ${HOST_CNT} ))
	CUR_HOST=${HOSTS[host]}
	NEXT_HOST=${HOSTS[NEXT_IDX]}

	startDomain ${CUR_HOST}
       checkIB ${DOMAIN}
	migrateDomain ${CUR_HOST} ${NEXT_HOST}
       checkIB ${DOMAIN}
	stopDomain ${NEXT_HOST}

	step=$((step+1))
done
