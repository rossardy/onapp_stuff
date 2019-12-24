#!/bin/bash                 $hv_ips
# ---------------------------------------------------------------------------

# Copyright 2014, Borys Drozhak <borys.drozhak@gmail.com>

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License at (http://www.gnu.org/licenses/) for
# more details.

# Usage: ISchecker.sh [ -N|-S ] [ -TD ] [ -I ip|-o ip|-z hvs_id ]
#    or: ISchecker.sh [ -h|-V|--list|--rpmlist|--tips|--update|--help ]
#        --options [-I:o:z:] are filter for check-list of target hypervisors.   [ -I ip_of_hypervisor ]  [ -o ip_of_hypervisor ]  [ -z hvs_zone_id ]
#    or: ISchecker.sh  -d [arg] -o [ip_of_hv]
#    or: ISchecker.sh --vm -i [vm_identifier]
# ---------------------------------------------------------------------------

VERSION='3.0-1'

# Main modes:
# [ -N | --network ]
#        - check MTU conformity for each hvs zone
#        - shows packets errors/dropped/overruns for each interface in onappstore bridge
#        - Link detected for all NICs and interfaces in SAN network
#        - check bond_mode conformity
#        - ping with Jumbo frame(include backups servers) -deadline 1,5 s
#        - report error if onappstoresan bridge is absent
#        - report ssh issues
#        - check multicast enabled snooping on san bridge
# [ -D | --deeply ] - deep mode: ping with 1000 packets with deadline 5 sec ; Works only for Network key
#
# [ -S | --isstate ]
#        - check telnet/ssh connection
#        - status and statistic of nodes
#        - checking Overflowed nodes (100%) inside storage vm
#        - I/O errors on nodes
#        - xfs corrupting and issues
#        - check groupmon/api/redis processes (12/7/4)
#        - check failed API-call transaction:`nodelocalinfo` inside stvms
#        - check isd processes on HV and stvm
#        - check dropbear(ssh) on stvm
#        - check running isd and groupmon at one time
#        - check crond and crontab default values
#        - report overlays on HVs
#        - check diskhotplug metadata lose
#        - report large timeout of onappstore nodes command on HVs
#        - check lock files - pinglock, freeinuselock, diskinfo.txn and sort files [.sort]
#        - check conformity groupmon processes keys in particularly hvs zone
#        - report group/isd issues
#        - check onapp-store versions conformity (controller and package)
#        - check hanged telnet transactions (telnet session which running more then 100 sec and hanged onappstore nodes transactions)
# [ -T ] - check via telnet method (blocked ssh-method)
# [any of keys]   -  check mess of onapp-store packets.

# [-V| --version] -  show current version of ISchecker.
# [--list]        -  shows list of cloudboot HVs
# [--rpmlist]     -  source rpm packets of OnApp Storage Versions
# [--tips]        -  shows tips for troubleshooting of some of IS issues.
# [--update]      -  Update ISchecker to newest version from ischeck repo by re-writing itselt in current directory

# vm/vdisk modes:
#
# -d : {vdisks mode} - checking vdisks ; -o specify ip of HV
#     requiers an argument: [ 'all' | 'degraded' | 'vdisk_indetifier' ]
#     all               - check all vdisks
#     degraded          - check all degraded vdisks
#     vdisk_identifier  - check specified vdisk
# --vm : {vm mode}  - checking vdisks of specified vm by  -i [vm_identifier]

# Exit codes:
#   1 :  no info from db
#   2 :  invalid options
#   3 :  no onapp-store packets

### COLOURS

BLACK=$(tput setaf 0)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
LIME_YELLOW=$(tput setaf 190)
POWDER_BLUE=$(tput setaf 153)
BLUE=$(tput setaf 4)
MAGENTA=$(tput setaf 5)
CYAN=$(tput setaf 6)
WHITE=$(tput setaf 7)
BRIGHT=$(tput bold)
NORMAL=$(tput sgr0)
BLINK=$(tput blink)
REVERSE=$(tput smso)
UNDERLINE=$(tput smul)


function black {
  printf "${BLACK}${1}${NORMAL}"
}


function red {
  printf "${RED}${1}${NORMAL}"
}


function green {
  printf "${GREEN}${1}${NORMAL}"
}


function yellow {
  printf "${YELLOW}${1}${NORMAL}"
}


######
ssh_opt='-o ConnectTimeout=5 -o  ConnectionAttempts=1 -o PasswordAuthentication=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=quiet -o CheckHostIP=no'  # ssh options
ISD='0'; DEEPLY='0'; flag='all'; SSH_TEL_FLAG='telnet';                                                                                                                              # flags
if [ -z "$(echo $0|grep '/')" ] ; then script_path=$(echo "./$0"); else script_path="$0"; fi

function header_fun() {
    echo; red "IS checker, version: " ; yellow $VERSION; echo
    echo "Copyright (C) 2019 Rostyslav Yatsyshyn rossardy@gmail.com" ; echo
}

function clean_up() {
# function for cleaning up variables data. or prepare vars.
# input: $1- list of variables (can be via [, ]); $2 - set mode. $3 and $4 - additional options
# Modes: 'empties' - clean all blanck enters and unset if var is empty; 'unset' - just unset var; 'B|E' - prepare output for catch info via key words with B and E
# Modes: 'add B|E' - update any arguments by getting info between 'name_of_argB and name_of_argE' from data of $3 argument.
# output: new data of variables or unseting vars.
for VARs in  `echo "$1"|sed 's/[ ,]/\n/g'` ; do \
[ "$2" = 'empties' -o "$3" = 'empties' ] && eval "$VARs=\"$(echo "${!VARs}"|grep -v '^$')\""  && [ -z "$(echo ${!VARs})" ] && unset $VARs ;
[ "$2" = 'B|E' ] && if [ -n "${!VARs}" ] ; then echo ${VARs}B ; echo "${!VARs}" ; echo ${VARs}E ; fi;
[ "$2" = 'unset' ]   && unset $VARs ;
[ "$2" = 'add B|E' ] && [ -n "$3" ] &&   eval "$VARs=\"${!VARs}
$(echo "${!3}"|sed -n "/${VARs}B/,/${VARs}E/p" |sed '1d;$d')\"" && [ "$4" != 'noempties' ] && clean_up "$VARs" 'empties';
done ;
}

##### some tips
##############  list of rpm of storage versions from https://onapp.zendesk.com/entries/24287513-OnApp-Storage-Versions
src_rpm='t.src.rpm'; tips_20='onappstore-0.0.1-20'; # temporary values.
tips_s=$(echo "
  OnApp storage / package version              OnApp Version   Date released
${tips_20}16.02.18_15.04.21$src_rpm   4.2.0-13
${tips_20}15.12.02_12.51.42$src_rpm   4.1.2-4
${tips_20}15.10.20_12.27.39$src_rpm   4.1.0-9
${tips_20}15.04.29_18.42.23$src_rpm   4.0.0-3
${tips_20}15.05.21_09.01.12$src_rpm  3.5.0-57.draas
${tips_20}15.04.29_18.42.23$src_rpm   3.5.0-14
${tips_20}15.03.03_10.56.11$src_rpm   3.5.0-13
${tips_20}15.03.03_10.56.11$src_rpm   3.5.0-6
${tips_20}15.03.03_10.56.11$src_rpm   3.5.0-3
${tips_20}15.03.03_10.56.11$src_rpm   3.3.2-19
${tips_20}14.12.24_13.04.03$src_rpm   3.3.2-13
${tips_20}14.12.24_13.04.03$src_rpm   3.3.2-9
${tips_20}14.12.17_16.06.12$src_rpm   3.3.2-8
${tips_20}14.11.25_19.53.24$src_rpm   3.3.2-6        2014-11-28
${tips_20}14.11.17_18.45.19$src_rpm   3.3.2-4        2014-11-19
${tips_20}14.11.17_18.45.19$src_rpm   3.3.2-3
${tips_20}14.10.17_16.10.24$src_rpm   3.3.1-9
${tips_20}14.10.09_11.16.56$src_rpm   3.3.0-22
${tips_20}14.10.03_07.31.37$src_rpm   3.3.0-19 (ISD) 2014-10-06
${tips_20}14.06.17_08.00.01$src_rpm   3.3.0-13       2014-09-16
${tips_20}14.08.04_07.30.01$src_rpm   3.3.0          2014-08-26
${tips_20}14.06.17_08.00.01$src_rpm   3.2.2-4        2014-04-25
${tips_20}14.06.17_08.00.01$src_rpm   3.2.2-3        2014-04-23
${tips_20}14.04.13_23.11.09$src_rpm   3.2.2-1        2014-04-22
${tips_20}14.01.24_10.34.53$src_rpm   3.2.2          2014-03-13
${tips_20}14.01.24_10.34.53$src_rpm   3.2.1          2014-02-05
${tips_20}14.01.24_10.34.53$src_rpm   3.2.0          2014-01-29
${tips_20}14.01.24_10.34.53$src_rpm   3.1.3-6        2014-01-24
${tips_20}14.01.20_17.13.49$src_rpm   3.1.3          2014-01-22
${tips_20}13.12.11_14.30.01$src_rpm   3.1.2          2013-12-12
${tips_20}13.10.25_23.53.09$src_rpm   3.1.1          2013-11-20
${tips_20}13.10.25_23.53.09$src_rpm   3.1            2013-11-12
${tips_20}13.10.25_23.53.09$src_rpm   3.0.11-ref1    2013-10-28
${tips_20}13.09.30_14.30.01$src_rpm   3.0.11         2013-9-30
${tips_20}13.08.19_16.03.16$src_rpm   3.0.10         2013-08-20
${tips_20}13.07.25_23.00.02$src_rpm   3.0.9          2013-07-26
${tips_20}13.05.31_13.10.17$src_rpm   3.0.8          2013-06-05
${tips_20}13.05.15_00.00.11$src_rpm   3.0.7          2013-05-15
${tips_20}13.04.17_16.58.47$src_rpm   3.0.6          2013-04-18
${tips_20}13.04.09_10.41.01$src_rpm   3.0.5          2013-04-09
${tips_20}13.03.15_13.59.42$src_rpm   3.0.4          2013-03-26
${tips_20}13.03.15_13.59.42$src_rpm   3.0.3          2013-03-18
${tips_20}13.02.27_08.19.07$src_rpm   3.0.2          2013-03-06
${tips_20}13.02.20_19.32.43$src_rpm   3.0.1
${tips_20}13.02.20_19.32.43$src_rpm   3.0.0 / GA     2013-02-20") ;
clean_up 'src_rpm tips_20' 'unset';
#### some troubleshooting from George Artemyev :
knowdb='reed more on: https://onapp.zendesk.com/entries/';
list_by_George=$(echo "
List of some issues with IS you can face:

-- Overlay is earlyboot feature which allows to overlay cloudboot image with any customised hardware drivers to be executed before the IS service is started..
${knowdb}103733083-Overlay-feature-in-Intergrated-storage

-- Here is the list of most popular cases towards incorrect amount of groupmon processes..
${knowdb}104893666-Incorrect-amount-of-groupmon-processes

-- Sometimes all copies of one or more stripes become degraded (in status 4) and as a result you are not able to start up VM or repair such disk..
${knowdb}104894576-All-replicas-of-one-more-stripes-are-degraded

-- Issue of Some missing drives found occurs after changing configuration towards physical disks from the customer side..
${knowdb}104895356--Some-missing-drives-found-old-records-in-database-

-- Sometimes in CP UI you may see the next error message: Storage API call failed: list index out of range (PUT :8080/is/Node/ {\"state\":3})..
${knowdb}104897296-CP-UI-displays-Storage-API-call-failed-list-index-out-of-rangenv-Integrated-Storage-

-- In CP GUI you may see the next warning (for example): 172.16.171.208:8080/is/Controller RestClient::InternalServerError 500 Internal Server Error
${knowdb}101205643-Incorrect-alerts-in-CP-GUI-in-3-3-0-19-RestClient-InternalServerError-500-Internal-Server-Error-

-- If ISchecker reports locks files.
It is needed to stop groupmon/isd/storaheAPI processes after that remove these files (from /tmp/) directory and start processes.

-- Failed to detect control path for vdisk . onappstore activate failed for vdisk -
${knowdb}104068323-onappstore-activate-failed-for-vdisk-Failed-to-detect-control-path-for-vdisk-Integrated-storage-

-- How to restart groupmon correctly..
${knowdb}88214227-Howto-correctly-restart-groupmon-service-on-HVs-and-storage-controllers

-- Failed to enable master sync status on masters
${knowdb}93012948--Failed-to-enable-master-sync-status-on-masters-Integrated-Storage-

-- Vdisk migration failure between datastores
${knowdb}93008528-Vdisk-migration-failure-between-datastores-Integrated-Storage-

-- Cannot online vdisk (Failed to set diskhandler)
${knowdb}93919298-cannot-online-vdisk-Failed-to-set-diskhandler-
")

############## fun of colors for echo
BOLD='\033[1m' ; RED='\033[0;31m' ; YELLOW='\033[0;33m' ; NORMAL='\033[0m' ;
function RED    { echo -e ${RED}${BOLD}$@${NORMAL}; } ; function REDn   { echo -en ${RED}${BOLD}$@${NORMAL}; } ; function YELLOW { echo -ne ${YELLOW}${BOLD}$@${NORMAL}; }; function REDc   { echo -e "${RED}${BOLD}$@${NORMAL}"; }

function library_ssh_color_funs {
function RED() { echo  '\033[0;31m\033[1m'"$@"'\033[0m'; } ; function REDn() { echo -n '\033[0;31m\033[1m'"$@"'\033[0m'; } ;              # standart color_fun ; for colorise but on HV when check stvms
function YELLOW() { echo -n '\033[0;33m\033[1m'"$@"'\033[0m'; };                                                                          # standart color_fun ; then all info will echo -e on CP.
}
############ --Help
function help_fun {
  usageHelp="Usage: ISchecker.sh [ -N|-S ] [ -TD ] [ -I ip|-o ip|-z hvs_id ]
   or: ISchecker.sh [ -h|-V|--list|--rpmlist|--tips|--update|--help ]
       --options [-I:o:z:] are filter for check-list of target hypervisors.   [ -I ip_of_hypervisor ]  [ -o ip_of_hypervisor ]  [ -z hvs_zone_id ]
   or: ISchecker.sh  -d [arg] -o [ip_of_hv]
   or: ISchecker.sh --vm='vm_identifier'
"
[ "$1" == 1 ] &&  echo "
$usageHelp
  -N,  --network    [ -N ]                      check only 'network' configurations. [ping -c 1 -w 1.5]
  -D,  --deeply     [ -D ]                      check ping beetwen HVs by 1000 packets per 0.001 sec, deadline 5 sec [only for network] [-i 0.001 -c 1000 -w 5]

  -S,  --isstate    [ -S ]                      check only IS state without network part.
  -T,               [ -T ]                      check by telnet method (instead of ssh)

  -z,               [ -z hvs_zone_id ]          filter: check only particular hvs zone[id]. 0=NULL     (hvs zone by hvs zone id)
  -I,               [ -I ip_of_hv ]             filter: check HVs zone which contain the specified IP. (hvs zone by hypervisor ip)
  -o,  --only       [ -o ip_of_hv ]             filter: check only HV which specified by IP.
_______________________________________________________________________________________________________________________________________________________________

  -d : {vdisks mode} - checking vdisks ; -o specify ip of HV
      requiers an argument: [ 'all' | 'degraded' | 'vdisk_indetifier' ]
      all               - check all vdisks
      degraded          - check all degraded vdisks
      vdisk_identifier  - check specified vdisk
  --vm : {vm mode}  - checking vdisks of specified vm by  -i [vm_identifier]
_______________________________________________________________________________________________________________________________________________________________

  -V,  --version    [ -V ]                      Shows current version of ISchecker.sh
  -h,  --help       [ -h ]                      usage.
       --list       [ --list ]                  List of existing cloudboot HVs. (can be filtered)
       --ips        [ --ips ]                   List of ips of HVs and related storage controllers. (can be filtered)
       --rpmlist    [ --rpmlist ]               List of OnApp Storage Versions (package versions).
       --tips       [ --tips ]                  List of articles with info for troubleshooting of some IS problems.
       --update     [ --update ]                Update ISchecker to newest version from repo by re-writing itself in curent directory. [path:'$script_path']
"
[ "$1" == 2 ] &&  echo "$usageHelp
" && exit 2
exit 0
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
    printf "\n%-25s %-25s\n" " " "${RED} Onapp packages versions${NORMAL}"
    printf "%$width.${width}s\n" "$divider"
    printf "$format" "onapp CP version: " $cp_ver
    printf "$format" "onapp storage version: " $store_ver
    printf "$format" "onapp ramdisks versions: " " "
    for i in $ramdisk_ver
    do
    printf "$format" " " $i
    done
}

############# DATA BASE PART #######################

dbph='/onapp/interface/config/database.yml';
dbpass=$(cat $dbph |grep passw|awk '{print $2}'|head -1 |sed -e "s|^'||g; s|'$||g; s|^\x22||g; s|\x22$||g")
dbname=$(cat $dbph |grep database|awk '{print $2}'|head -1)
dbhost=$(cat $dbph |grep 'host:' |awk '{print $2}'|head -1)
dborder='ORDER BY hypervisor_group_id';

if [ $old ]
then
#For version <=6.0
dbselect='from hypervisors where online=1 and mac  "<> ''" and host_id is not NULL'
else
#For version >6.0
dbselect="from hypervisors left join integrated_storage_settings on hypervisors.id=integrated_storage_settings.parent_id where mac <> '' and host_id is not NULL"
fi;

############# Print list of HVs ######################

###### advance printing fun
function advance_print_fun() {
  # function fixed printing of output info;
  # $2 = 1 - for mysql output (dbhv|dbhvoff) - sed Makes straight columns
  # $2 = 2 - print info with markdown ``` $1 ```
  [ "$2" = 1 ] && echo "$1" |sed -e 's|^\([0-9.]\+\)\t\([0-9]\+\)\t\([0-9]\+\)\t\([0-9NUL]\+\)\t|\1\t   \2\t   \3\t   \4\t    |g ; s/1$/ Backups Server/g; s/0$//g' ;
  [ "$2" = 2 ] && echo && echo '```' && echo "$1" && echo '```' && echo ;
}

function hvs_list()
{
    local divider===============================
    local divider=$divider$divider$divider
    header="%-10s %8s %13s %15s %3s\n"
    format="%-10s %8s %13s %15s %3s\n"
    width=150

    hvs_ips_online=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select ip_address, host_id, label, mtu, mac $dbselect and online=1")
    hvs_ips_offline=$(mysql -N -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select ip_address, host_id, label, mtu, mac $dbselect and online=0")

    printf "$header" "IP Address" "host_id" "Label" "MTU" "MAC"
    j=0;temp=''
    for i in $hvs_ips_online; do for j in {1..5}; do if  [ "$" != 5 ] temp=$temp' '$i; esle tempo=( $temp ); printf "$format" $tempo[0] $tempo[1] $tempo[2] $tempo[3] $tempo[4] $tempo[5]; fi ;done; temp=''; done


}

#################  Tips function
function tips() {
[ "$1" = Source ]  && echo "$tips_s" && echo && exit 0
[ "$1" = IS_tips ] && echo "$list_by_George" && echo && exit 0
[ "$1" = version ] && header_fun && exit 0
}

function make_sequence() {
# takes a list then gets only numbers finally returns a numbers sequences which can genarate the original list of numbers.   example: '1,2,3,4,5,7,9' -> '{1..5},7,9'
# $1 should be a list with numbers!  (-d [ ,] )
# $2 = flag for language. for example bash ; python . If you want your customs
# $3 = sequence separator by default for bash '..'
# $4 = sequence brackets (begin)  by default for bash '{'
# $5 = sequence brackets (ending) by default for bash '}'
# $6 = separator for numbers by default for bash ',' . space by default for set mode

if [ "$2" == 'bash' -o "$2"  == '' ] ; then \
 # {1..9},2,3,4,{4..7}
 local seq_brackers_b='{'
 local seq_separator='..'
 local seq_brackers_e='}'
 local separator=','
elif [ "$2" == 'set' ] ; then \
 # {seq_brackers_b}[0-9]{seq_separator}[0-9]{seq_brackers_e}{separator}
  local seq_brackers_b="$3"
  local seq_separator="$4" ; [ -z "$seq_separator" ] && seq_separator='none'
  local seq_brackers_e="$5"
  local separator="$6"
fi;
if [ -z "$separator" ] ; then seq_brackers_b='{';seq_separator='..';seq_brackers_e='}';separator=',' ;fi  # set by default if there is not enough keys
local ar=($(echo $1|sed 's/[^0-9 ,]//g' |sed 's/[ ,]\+/ /g'|tr " " "\n"|sort -gu|tr "\n" " "))   # crreate massive with list of numbers (only number and uniq)
# echo $1|sed 's/[^0-9 ,]//g' |sed 's/[ ,]\+/ /g'|tr " " "\n"|sort -gu|tr "\n" " "
local min='No' # flag as min-variable
local total=() # return massive - output-variable
 if (( ${#ar[*]} <= 3 )) ; then  echo -n ${ar[*]}|sed "s/ /${separator}/g";

 else \
 for ((i=0; i<${#ar[*]}; i++));

   do if [ $min != 'No' ] ;
        then \
           if (($min + 1 == ${ar[$i]} && $i != ${#ar[*]} - 1 && ${ar[$i]} + 1 == ${ar[$i+1]} )) ;
            then min=${ar[i]} ;
           elif (( $i != ${#ar[*]} - 1 && ${ar[$i]} + 1 == ${ar[$i+1]} )) ;
            then total+=(${ar[i]}) ;
                 (( $i < ${#ar[*]} - 2 )) && (( ${ar[$i]} + 1 == ${ar[$i+1]} && ( ${ar[$i]} + 2 != ${ar[$i+2]} || $i == ${#ar[*]} - 1 ) )) && \
                  total+=($separator) ;
                 min=${ar[$i]};

             else  (( ${ar[$i - 1]} +1 == ${ar[$i]} && ${total[ ${#total[*]} - 1 ]}  < ${ar[$i]} - 1 )) && \
                      total+=($seq_separator) ;
                   total+=(${ar[i]}) ;

                   if (( $i < ${#ar[*]} - 2 ));
                    then (( ${ar[$i]} + 1 < ${ar[$i+1]} || ${ar[$i]} + 2 < ${ar[$i+2]} )) &&  total+=($separator) ;
                    elif [ "${total[${#total[*]}-2]}" == "$seq_separator" ] ; then (( $i == ${#ar[*]} - 2 )) && total+=($separator) ;
                    elif (( $i != ${#ar[*]} - 1 &&  ${ar[$i]} + 1 < ${ar[$i+1]} )) ; then [ "${total[${#total[*]}-2]}" != "$seq_separator" ] && total+=($separator) ;fi;

                   min='No' ; # echo 'else-set-No'
             fi;
      else min=${ar[$i]};
           total+=(${ar[i]}) ;

           if (( $i != ${#ar[*]} - 1 &&  ${ar[$i]} + 1 < ${ar[$i+1]} )) ; then total+=($separator) ;
           elif (( $i != ${#ar[*]} - 2 &&  ${ar[$i]} + 2 < ${ar[$i+2]} ))  ;  then total+=($separator) ;
           elif (( $i == ${#ar[*]} - 2 )) ; then  total+=($separator) ; fi;
        fi;
 done 2>/dev/null
seq_separator="$(echo $seq_separator|sed 's/\./\\./g')"

if [ -z "$separator" ] ;
  then echo -n ${total[*]}|sed "s/ \(${seq_separator}\) /\1/g" ;   # if sepator is a space will fix space between seq_brackets
else echo -n ${total[*]}|tr -d ' ' ; fi  |sed "s/\([0-9]\+${seq_separator}[0-9]\+\)/${seq_brackers_b}\1${seq_brackers_e}/g"
fi;
}

# ips sort fun
function ip_sort_fun()
{
# input:  $1 = list of ips(without empties!) ; $2 = part of ip which should be sorted f.e. 4 = /24
# output: sorted ips in one line   f. e. $1 = 10.200.1.1; 10.200.1.5 $2=4 --> 10.200.1.[1,5]
local ip_end ip24 ip24_sort;   # ip24_sor contains sequence of variable ips
local ip_cut1=$(echo `bash -c "echo {$2..4}"`|sed ' s/ /,/g');       # var for cut - exmpl for $2=3: '3,4' ; $2=4: '4'
local ip_cut2=$(echo `bash -c "echo {$(echo $(($2+1)))..5}"`|sed ' s/ /,/g' ); # exmpl for $2=3: '4' ; $2=2: '3,4'
local ip_begin=$(echo "$1"| sed 's/ /\n/g'|sort| sed 's/\./ /g'| cut -d ' ' -f $ip_cut1 --complement| sed 's/\( \|$\)/./g'|sort -u);
for ip_b in $ip_begin ;
   do ip_end=$(echo "$1"|grep -- "$ip_b"|sed 's/\./ /g'|cut -d ' ' -f $ip_cut2|sort -u|sed 's/^/./g; s/ /./g');
     for ip_e in $ip_end;
       do ip24_sort=$(echo "$1"|sed 's/ /\n/g'|grep -- "^$ip_b"|grep -- "$ip_e$"|sort -u|sed 's/\./ /g'|cut -d ' ' -f $2|sort -u) ;
       ip24=$(echo $ip_b'{'$(make_sequence "$(echo $ip24_sort|sed 's/ /,/g')" 'bash' )'}'$ip_e| sed 's/\(^\.\|\.$\)//g');
       if echo $ip24 | grep -E '\{[0-9]{1,3}\}' 1>/dev/null ; then echo -n $ip24' '| tr -d '{}' ;
       else echo -n $ip24' '; fi  |sed 's/{\({[0-9]\+\.\.[0-9]\+}\)}/\1/g'  # removed {{[0-9]..[0-9]}}
     done;
  done;
}

#################  Check keys:
checkargs () {                                                                                                                        # check args
[[ $OPTARG =~ - ]] && echo "Unknown argument $OPTARG for an option '$OPTION'!" && help_fun 2;
}
checkopts () {                                                                                                                        # check options
  case "$1" in
letters ) checkargs;
      [[ $OPTARG =~ [[:digit:]] ]] && echo "Unknown argument $OPTARG for an option '$OPTION'! Found out digits"                                              && help_fun 2;;
zone    ) [ -z "$(echo $OPTARG |grep '^[0-9]\{1,2\}$')" ] && echo "Unknown argument $OPTARG for an option '$OPTION'! Should be [0-99]"                       && help_fun 2;
          [ "$zone" = 0 ] && zone=NULL ;;
flag    ) [ "$flag" != all ] && echo 'not allowed to use these keys simultaneously [-N|-S|-d|--vm]'                                                          && help_fun 2;;
ip      ) checkargs;
          [ -z "$(echo $OPTARG|grep '^[1-9][0-9]\{0,2\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$')" ] && echo "Incorrect IP address for option '$OPTION'!" && help_fun 2;;
zoneIP  ) [ -z "$zone" ] && no_info;
          [ "$zone" = 0 ] && zone=NULL ;;
disks   ) if [ -n "$(echo $OPTARG|grep '[0-9a-z]\{8\}')" -o "$OPTARG" == 'all' -o "$OPTARG" == 'degraded' ] ; then echo 1>/dev/null ;
             else echo "Incorrect name of vdisk or mode [all|degraded] for an option '$OPTION'!" ;                                                             help_fun 2; fi ;;
  esac
}

function d_mode_flags_fun() {
  #  create flag for d mode;  input $OPTARG  - argument of mode for d option.
  if [ "$1" = all ]  ; then FLAGS+="all_disks" ;
  elif [ "$1" = degraded ]; then  FLAGS+="degraded_disks";
  else FLAGS+="vdisk"; VDISKS="$1"; fi;
}

[ -n "$(echo $@|grep '[NS] [^-]')" ] && echo 'Invalid option. Found out arguments for N|S options' && help_fun 2;
[ -n "$(echo $@|sed  's/ /\n/g'|grep '^-$')" ] && echo 'Invalid option. Found out Blank key -' && help_fun 2;
[ -n "$1" ] && [ -z "$(echo $1|grep '^-')" ] && echo 'Invalid first option. Use -h' && help_fun 2;
[ -n "$(echo $@|sed  "s/ /\n/g"|grep  '^-[^-]'|sed "s/-//g;s/\([[:alpha:]]\)/\1\n/g"|grep -Ev '^$|[0-9]'|sort -u -c|grep -vP '^[ ]{6}1')" ] && echo 'Error: duplicate keys. Use -h' && help_fun 2;
[ -n "$(echo $@|sed  "s/ /\n/g"|grep  '^--'|sort -u -c|grep -vP '^[ ]{6}1')" ] && echo 'Error: duplicate long keys. Use --help' && help_fun 2;
[ -n "$(echo $@|sed  "s/ /\n/g"|grep  '^-[^-]'|sed "s/-//g;s/\([[:alpha:]]\)/\1\n/g"|grep -Ev '^$|[0-9]'|grep 'z\|I\|o'|sed 's/[zo]/I/g'|sort -u -c|grep -vP '^[ ]{6}1')" ] && \
echo 'Error: not allowed to use 2 keys simultaneously (-Izo). Use -h' && help_fun 2;
[ -n "$(echo $@|grep '\-[NS]\{0,1\}[tzIo][ ]\{0,1\}[a-zA-Z1-9.]\{1,16\} [^-]')" ] && echo "Find out double argument for some of options [t|z|I|o]" && help_fun 2;
[ -n "$(echo $@|grep ':')" ] &&  echo "Find out incorrect symbol - ':'" && help_fun 2;
while getopts 'VNDSh-z:I:t:o:Td:i:' OPTION ; do
  case "$OPTION" in
    N  ) checkopts flag; flag='network'      ;;
    D  ) DEEPLY=1;                           ;;
    S  ) checkopts flag; flag='telnet'       ;;
    o  ) checkopts 'ip'; FLAGS+="only" ; zoneIP="$OPTARG";;
    h  ) help_fun '1'                        ;;
    z  ) checkopts zone;zone="$OPTARG"       ;;
    I  ) checkopts ip;zoneIP="$OPTARG"       ;;
    t  ) checkopts zone;t="$OPTARG"          ;;
    V  ) tips 'version'                      ;;
    T  ) FLAGS+="ontelnet"                   ;;
    d  ) checkopts disks; checkopts flag; flag='disks' ; d_mode_flags_fun "$OPTARG" ;;
    -  ) [ $OPTIND -ge 1 ] && optind=$(expr $OPTIND - 1 ) || optind=$OPTIND
         eval OPTION="\$$optind"
         OPTARG=$(echo $OPTION | cut -d'=' -f2)
         OPTION=$(echo $OPTION | cut -d'=' -f1)
         case $OPTION in
             --network      ) checkopts 'flag' ;flag='network'  ;;
             --deeply       ) DEEPLY=1;                         ;;
             --isstate      ) checkopts 'flag' ;flag='telnet'   ;;
             --zone         ) checkopts 'zone' ;zone="$OPTARG"  ;;
             --zonebyip     ) checkopts 'ip'   ;zoneIP="$OPTARG";;
             --only         ) checkopts 'ip'   ;FLAGS+="only"; zoneIP="$OPTARG" ;;
             --vm           ) FLAGS+="vm_mode";checkopts flag; VM_identifier="${OPTARG//[\'\"]/}";;
             --teltime      ) checkopts 'zone' ;t="$OPTARG"     ;;
             --list         ) HVslist='list'                    ;;
             --ips          ) FLAGS+="take_ips"                 ;;
             --rpmlist      ) tips 'Source'                     ;;
             --tips         ) tips 'IS_tips'                    ;;
             --version      ) tips 'version'                    ;;
             --update       ) update_script                     ;;
             --test         ) help_fun '3'                      ;;
             --help         ) help_fun '1'                      ;;
             * )  echo "Invalid options (long) " ; help_fun '2' ;;
         esac
       OPTIND=1
       shift
      ;;
    \? )  echo "Invalid options (short) " ; help_fun 2 ;;
    esac
done


header_fun
onapp_version
#hvs_list

hvs_ips=$(mysql -u root -p"$dbpass" "$dbname" -h "$dbhost" -e "select ip_address $dbselect and online=1")
echo ; yellow 'HVS output: ' ; echo -n '  for i in ' ; ip_sort_fun "$hvs_ips" '4' ; echo '; do echo $i;  ssh $i uptime ; done'$'\n';
st_vm_ips=$(for i in $hvs_ips; do curl --silent $i:8080/is/Node |ruby -rjson -e 'print JSON.pretty_generate(JSON.parse(STDIN.read))' 2> /dev/null |grep "ipaddr"|grep -v .254|sort|uniq|sed 's/"ipaddr"://g; s/[",]//g'; done)
st_vm_ips=$(echo "$st_vm_ips"| tr ' ' '\n' | sort -u | tr '\n' ' ')
parsing=$(echo $st_vm_ips |sed 's/10.200.//g; s/[[:space:]]/,/g')
final_range=$(echo "for i in" 10.200.{$parsing}"; do echo \$i ; ssh \$ssh_key \$i uptime ; done")
yellow 'Stvms output: ' ; echo $final_range;

echo 'ssh_key='"'$ssh_opt'" ; echo


### KEYS

if [ "$HVslist" = list ] ; then  printf '%-8b\t' 'ip_address' ' host_id   mtu    hvs_zone    label' ; echo;
    echo 'Online:' ;  advance_print_fun "$dbhv" '1'; echo;
    if [ -n "$dbhvoff" ] ; then echo 'Offline:' ; advance_print_fun "$dbhvoff" '1' ; fi ;
     exit 0;
fi;