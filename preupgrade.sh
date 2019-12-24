#!/bin/bash
# ---------------------------------------------------------------------------

# Copyright 2019, Rostyslav Yatsyshyn <rostyslav.yatsyshyn@onapp.com>

### COLOURS

BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)
BRIGHT=$(tput bold)
NORMAL=$(tput sgr0)


function header()
{
    echo
    echo ${RED} "Before the upgrade, collecting all the needed info from the Cloud..." ${NORMAL} ; echo
}

### onapp versions
function onapp_version()
{
    local divider===============================
    local divider=$divider$divider$divider
    local format="%-35s %-45s\n"
    width=75
    cp_ver=$(rpm -qa | grep onapp-cp-[4-9]| sed 's/.noarch//g')
    if [ $(echo $cp_ver | cut -b 10,11,12) \> 6.0 ];
    then
        old=0;
    else
        old=1;
    fi;
    store_ver=$(rpm -qa | grep onapp-store-install | sed 's/.noarch//g')
    ramdisk_ver=$(rpm -qa | grep ramdisk-| sed 's/.noarch//g')
    printf "\n%-25s %-25s\n" " " "${RED} ${BRIGHT} Onapp packages versions${NORMAL}"
    printf "%$width.${width}s\n" "$divider"
    printf "$format" "onapp CP version: " $cp_ver
    printf "$format" "onapp storage version: " $store_ver
    printf "$format" "onapp ramdisks versions: " " "
    for i in $ramdisk_ver
    do
    printf "$format" " " $i
    done
    hvs_dbselect
    echo; echo
    printf "%-25s %-25s\n" " " "${RED} ${BRIGHT} Hypervisors and Backup Servers ${NORMAL}"
    printf "%$width.${width}s\n" "$divider"
    printf  "$format" "Hypervisors: " $hvs_all
    printf  "$format" "static KVM: " $hvs_static_kvm
    printf  "$format" "static XEN: " $hvs_static_xen
    printf  "$format" "cloudboot KVM: " $hvs_cboot_kvm
    printf  "$format" "cloudboot XEN: " $hvs_cboot_xen
    printf  "$format" "VMware: " $hvs_vmware
    printf  "$format" "Backup Servers: " $bs_all
    printf  "$format" "static BS: " $bs_static
    printf  "$format" "cloudboot BS: " $bs_cboot
}

function hvs_dbselect()
{
     if [ $old = 1 ]
     then
        #For version <=6.0
        dbselect='from hypervisors where ip_address is not NULL and '
     else
         #For version >6.0
        dbselect="from hypervisors left join integrated_storage_settings on hypervisors.id=integrated_storage_settings.parent_id where ip_address is not NULL and "
     fi;
     ### count HVs
     ###select count(*) from hypervisors where ip_address is not NULL;
     hvs_all=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect backup=0")
     ### static KVM
     hvs_static_kvm=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect host_id is NULL and backup=0 and hypervisor_type='kvm' ")
     ### static XEN
     hvs_static_xen=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect host_id is NULL and backup=0 and hypervisor_type='xen'")
     ### cloudboot KVM
     hvs_cboot_kvm=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect host_id is not NULL and backup=0 and hypervisor_type='kvm'")
     ### cloudboot XEN
     hvs_cboot_xen=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect host_id is not NULL and backup=0 and hypervisor_type='xen'")
     ### VMware
          hvs_vmware=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect host_id is NULL and backup=0 and hypervisor_type='vmware'")
     ### Backup Servers
     bs_all=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect backup=1")
     ### static BS
     bs_static=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect host_id is NULL and backup=1")
     ### cloudboot BS
     bs_cboot=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select count(*) $dbselect host_id is not NULL and backup=1")
}

############# DATA BASE PART #######################

dbph='/onapp/interface/config/database.yml';
dbpass=$(cat $dbph |grep passw|awk '{print $2}'|head -1 |sed -e "s|^'||g; s|'$||g; s|^\x22||g; s|\x22$||g")
dbname=$(cat $dbph |grep database|awk '{print $2}'|head -1)
dbhost=$(cat $dbph |grep 'host:' |awk '{print $2}'|head -1)
dborder='ORDER BY hypervisor_group_id';

header
onapp_version

