#!/bin/bash

#MUST DO the following first:

# service glusterd stop
# service glustereventsd stop

# umount /datadrive
# mdadm -S /dev/md1
# rm -rf /datadrive
# rm -f /etc/mdadm.conf
# Then remove the mount entry from /etc/fstab

# This script built for Ubuntu Server 16.04 LTS => Mod to work with Ubuntu 18.4 
# You can customize variables such as MOUNTPOINT, RAIDCHUNKSIZE and so on to your needs.
# You can also customize it to work with other Linux flavours and versions.
# If you customize it, copy it to either Azure blob storage or Github so that Azure
# custom script Linux VM extension can access it, and specify its location in the 
# parameters of powershell script or runbook or Azure Resource Manager CRP template.   

AZUREVMOFFSET=4

#NODENAME=$(hostname)
#PEERNODEPREFIX=${1}
#PEERNODEIPPREFIX=${2}
#VOLUMENAME=${3}
#NODEINDEX=${4}
#NODECOUNT=${5}

#echo $NODENAME          >> /tmp/vars.txt
#echo $PEERNODEPREFIX    >> /tmp/vars.txt
#echo $PEERNODEIPPREFIX  >> /tmp/vars.txt
#echo $VOLUMENAME        >> /tmp/vars.txt
#echo $NODEINDEX         >> /tmp/vars.txt
#echo $NODECOUNT         >> /tmp/vars.txt

## read back from the template install log
IFS=$'\n'
items=($(cat /tmp/vars.txt))
unset IFS
  
NODENAME=${items[0]}
PEERNODEPREFIX=${items[1]}
PEERNODEIPPREFIX=${items[2]}
VOLUMENAME=${items[3]}
NODEINDEX=${items[4]}
NODECOUNT=${items[5]}



MOUNTPOINT="/datadrive"
RAIDCHUNKSIZE=128

RAIDDISK="/dev/md1"
RAIDPARTITION="/dev/md1p1"

# An set of disks to ignore from partitioning and formatting
#BLACKLIST="/dev/sda|/dev/sdb"
BLACKLIST="xxx"


# make sure the system does automatic update
#sudo apt-get -y update
#sudo apt-get -y install unattended-upgrades

{
        check_os() {
            grep -q -s ubuntu /proc/version && _RET=$? || _RET=$?
            isubuntu=$_RET
        }

        scan_for_new_disks() {
            # Looks for unpartitioned disks
            declare -a RET
            DEVS=($(ls -1 /dev/sd*|egrep -v "${BLACKLIST}"|egrep -v "[0-9]$"))
            for DEV in "${DEVS[@]}";
            do
                # Check each device if there is a "1" partition.  If not,
                # "assume" it is not partitioned.
                if [ ! -b ${DEV}1 ];
                then
                    RET+="${DEV} "
                fi
            done
            echo "${RET}"
        }

        get_disk_count() {
            DISKCOUNT=0
            for DISK in "${DISKS[@]}";
            do 
                DISKCOUNT+=1
            done;
            echo "$DISKCOUNT"
        }

        create_raid0_ubuntu() {
            dpkg -s mdadm && _RET=$? || _RET=$?
            if [ $_RET -eq 1 ];
            then 
                echo "installing mdadm"
                sudo apt-get -y -q install mdadm
            fi
            echo "Creating raid0"
            udevadm control --stop-exec-queue
            echo "yes" | mdadm --create "$RAIDDISK" --name=data --level=0 --chunk="$RAIDCHUNKSIZE" --raid-devices="$DISKCOUNT" "${DISKS[@]}"
            udevadm control --start-exec-queue
            mdadm --detail --verbose --scan > /etc/mdadm.conf
        }


        do_partition() {
        # This function creates one (1) primary partition on the
        # disk, using all available space
            DISK=${1}
            echo "Partitioning disk $DISK"
            echo -ne "n\np\n1\n\n\nw\n" | fdisk "${DISK}" 
        #> /dev/null 2>&1

        #
        # Use the bash-specific $PIPESTATUS to ensure we get the correct exit code
        # from fdisk and not from echo
        if [ ${PIPESTATUS[1]} -ne 0 ];
        then
            echo "An error occurred partitioning ${DISK}" >&2
            echo "I cannot continue" >&2
            exit 2
        fi
        }

        add_to_fstab() {
            UUID=${1}
            MOUNTPOINT=${2}
            grep -q -s "${UUID}" /etc/fstab && _RET=$? || _RET=$?
            if [ $_RET -eq 0 ];
            then
                echo "Not adding ${UUID} to fstab again (it's already there!)"
            else
                LINE="UUID=${UUID} ${MOUNTPOINT} ext4 defaults,noatime 0 0"
                echo -e "${LINE}" >> /etc/fstab
            fi
        }

        configure_disks() {
            ls "${MOUNTPOINT}" && _RET=$? || _RET=$?
            if [ $_RET -eq 0 ]
            then 
                return
            fi
            DISKS=($(scan_for_new_disks))
            echo "Disks are ${DISKS[@]}"
            declare -i DISKCOUNT
            DISKCOUNT=$(get_disk_count) 
            echo "Disk count is $DISKCOUNT"
            if [ $DISKCOUNT -gt 1 ];
            then
                create_raid0_ubuntu
                do_partition ${RAIDDISK}
                PARTITION="${RAIDPARTITION}"
            else
                DISK="${DISKS[0]}"
                do_partition ${DISK}
                PARTITION=$(fdisk -l ${DISK}|grep -A 1 Device|tail -n 1|awk '{print $1}')
            fi

            echo "Creating filesystem on ${PARTITION}."
            mkfs -t ext4 ${PARTITION}
            mkdir "${MOUNTPOINT}"
            read UUID FS_TYPE < <(blkid -u filesystem ${PARTITION}|awk -F "[= ]" '{print $3" "$5}'|tr -d "\"")
            add_to_fstab "${UUID}" "${MOUNTPOINT}"
            echo "Mounting disk ${PARTITION} on ${MOUNTPOINT}"
            mount "${MOUNTPOINT}"
        }

        open_ports() {
            index=0
            while [ $index -lt $NODECOUNT ]; do
			    echo "Node ${index}"
				thisNode="${PEERNODEIPPREFIX}.$(($index+$AZUREVMOFFSET))"
			    echo "Node ${thisNode}"

                if [ $index -ne $NODEINDEX ]; then
				    echo "Node ${thisNode} is a peer"
                    iptables -I INPUT -p all -s "${thisNode}" -j ACCEPT
                    echo "${thisNode}    ${thisNode}" >> /etc/hosts
                else
				    echo "Node ${thisNode} is me"
                    echo "127.0.0.1    ${thisNode}" >> /etc/hosts
                fi
                let index++
            done
            iptables-save
        }

        disable_apparmor_ubuntu() {
            /etc/init.d/apparmor teardown
            update-rc.d -f apparmor remove
        }

        configure_network() {
            open_ports
            disable_apparmor_ubuntu
        }

        install_glusterfs_ubuntu() {
            dpkg -l | grep glusterfs && _RET=$? || _RET=$?
            if [ $_RET -eq 0 ];
            then
                return
            fi

            if [ ! -e /etc/apt/sources.list.d/gluster* ];
            then
                echo "adding gluster ppa"
                apt-get  -y install software-properties-common
                apt-add-repository -y ppa:gluster/glusterfs-3.10
                apt-get -y update
            fi
            
            echo "installing gluster"
            apt-get -y install glusterfs-server
            
            return
        }

        configure_gluster() {
            echo "gluster step1"

            which glusterd
            _RET=$?
            if [ $_RET -ne 0 ];
            then
                install_glusterfs_ubuntu
                systemctl enable glusterd
                systemctl enable glustereventsd
            fi

            systemctl start glusterd
            systemctl start glustereventsd

			echo "gluster step2"
            GLUSTERDIR="${MOUNTPOINT}/brick"
            ls "${GLUSTERDIR}" && _RET=$? || _RET=$?

            if [ $_RET -ne 0 ];
            then
                mkdir "${GLUSTERDIR}"
            fi

            if [ $NODEINDEX -lt $(($NODECOUNT-1)) ];
            then
                return
            fi
            
            echo "gluster step3"
            allNodes="${NODENAME}:${GLUSTERDIR}"
			echo $allNodes
            retry=10
            failed=1

            while [ $retry -gt 0 ] && [ $failed -gt 0 ]; do
                failed=0
                index=0
                echo retrying $retry 
                while [ $index -lt $(($NODECOUNT-1)) ]; do
					glustervm=${PEERNODEPREFIX}${index}
					echo $glustervm

                    ping -c 3 $glustervm
                    gluster peer probe $glustervm && _RET=$? || _RET=$?
                    if [ $_RET -ne 0 ];
                    then
                        failed=1
                        echo "gluster peer probe $glustervm failed"
                    fi

                    gluster peer status
                    gluster peer status | grep $glustervm && _RET=$? || _RET=$?
                    
                    if [ $_RET -ne 0 ];
                    then
                        failed=1
                        echo "gluster peer status $glustervm failed"
                    fi
                    
					if [ $retry -eq 10 ]; then
                        allNodes="${allNodes} $glustervm:${GLUSTERDIR}"
                    fi
                    let index++
                done
                sleep 30
                let retry--
            done

            echo "gluster step4"
			echo $allNodes
            echo "Sleeping for 10 seconds before creating/starting the volume..."
            sleep 10s
            
            echo "==> WARNING: Due to the split-brain warning prompted by gluster and it seems there is no force/silent option, will use the yes command to force it..."
            #echo "# gluster volume create ${VOLUMENAME} rep 2 transport tcp ${allNodes}"
            #echo "# gluster volume start ${VOLUMENAME}"
            # this volume create will fail due to a prompt warning about splitbrain. Is there a force/silent option?
            yes | gluster volume create ${VOLUMENAME} rep 2 transport tcp ${allNodes} 
            gluster volume info 
            gluster volume start ${VOLUMENAME} 
            echo "gluster complete"
        }

        # "main routine"
        check_os
        configure_network
        configure_disks
        configure_gluster

}  > /tmp/gluster-setup.log
