#!/bin/bash
# ---------------------------------------------------------------------------

# Copyright 2019, Rostyslav Yatsyshyn <rossardy@gmail.com>

# This program is free software: you can redistributef it and/or modify
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

function redb {
  printf "${RED}${BRIGHT}${1}${NORMAL}"
}

function green {
  printf "${GREEN}${1}${NORMAL}"
}


function yellow {
  printf "${YELLOW}${1}${NORMAL}"
}


function library_ssh_color_funs {
function red() { echo  '\033[0;31m\033[1m'"$@"'\033[0m'; } ; function redn() { echo -n '\033[0;31m\033[1m'"$@"'\033[0m'; } ;              # standart color_fun ; for colorise but on HV when check stvms
function yellow() { echo -n '\033[0;33m\033[1m'"$@"'\033[0m'; };                                                                          # standart color_fun ; then all info will echo -e on CP.
}

### Standard table outputs

divider===============================
divider=$divider$divider$divider
width=75

######
ssh_opt='-o ConnectTimeout=5 -o  ConnectionAttempts=1 -o PasswordAuthentication=no -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=quiet -o CheckHostIP=no'  # ssh options
ISD='0'; DEEPLY='0'; flag='all'; SSH_TEL_FLAG='telnet';                                                                                                                              # flags
if [ -z "$(echo $0|grep '/')" ] ; then script_path=$(echo "./$0"); else script_path="$0"; fi

function header_fun() {
    echo; red "IS checker, version: " ; yellow $VERSION; echo
    echo "Copyright (C) 2019 Rostyslav Yatsyshyn rossardy@gmail.com" ; echo
    echo "ISchecker will use onapp-store ver ${YELLOW}[ $(echo $verstore) ]${NORMAL} for checking cloud."; echo
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
       --versions   [ --versions ]             List of OnApp Storage Versions (package versions).
       --update     [ --update ]                Update ISchecker to newest version from repo by re-writing itself in curent directory. [path:'$script_path']
"
[ "$1" == 2 ] &&  echo "$usageHelp
" && exit 2
exit 0
}

### onapp versions

function onapp_version()
{
    local format="%-35s %-45s\n"
    printf "%s\n" "${RED}Onapp packages versions${NORMAL}"
    printf "%$width.${width}s\n" "$divider"
    printf "$format" "onapp CP version: " $onapp_cp_ver
    printf "$format" "onapp storage version: " $onapp_store_ver
    printf "$format" "onapp ramdisks versions: " " "
    for i in $onapp_ramdisk_ver
    do
    printf "$format" " " $i
    done
    exit 0
}

############# DATA BASE PART #######################
function no_info () {
if [[ $FLAGS =~ 'vm_mode' ]] ; then echo "Looks like there is not IS-vdisks for checking"; fi;
if [ "$HVslist" = list ] ;
 then red 'No cloudboot HV(s) ' $(if [ -n "$zone" ] ; then echo "in hvs_zone '$zone'"; elif [ -n "$zoneIP" ] ; then echo "related to HV '$zoneIP'"; else echo 'in your cloud';fi ) && exit 1;
else red 'No info from DB.' && echo 'Please check cloud for existing cloudboot HVs or hypervisors_zone_id value' && echo 'Try --list' &&  exit 1 ;  fi ; }

dbph='/onapp/interface/config/database.yml';
dbpass=$(cat $dbph |grep passw|awk '{print $2}'|head -1 |sed -e "s|^'||g; s|'$||g; s|^\x22||g; s|\x22$||g")
dbname=$(cat $dbph |grep database|awk '{print $2}'|head -1)
dbhost=$(cat $dbph |grep 'host:' |awk '{print $2}'|head -1)
dbuser=$(cat $dbph |grep 'username:' |awk '{print $2}'|head -1)
dbprefix='select ip_address, host_id, mtu, hypervisor_group_id, label, backup '
dborder='ORDER BY hypervisor_group_id';

### Recognise onapp versions

onapp_cp_ver=$(rpm -qa | grep onapp-cp-[4-9]| sed 's/.noarch//g')
    if [ $(echo $onapp_cp_ver | cut -b 10,11,12) \> 6.0 ];
    then
        old=0;
    else
        old=1;
    fi;
onapp_store_ver=$(rpm -qa | grep onapp-store-install | sed 's/.noarch//g')
onapp_ramdisk_ver=$(rpm -qa | grep ramdisk-| sed 's/.noarch//g')

if [[ $old -eq 1 ]]
then
#For version <=6.0
dbselect="from hypervisors where mac  <> '' and host_id is not NULL"
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
             --versions     ) onapp_version                     ;;
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

 [ "$flag" = 'disks' ] && [ -z "$(echo $@|grep 'o [1-9]')" ] && echo "Please specify HV by -o option"   && help_fun 2 ;
[[ $FLAGS =~ 'vm_mode' ]] && [ -z "$(echo $VM_identifier|grep -- '[a-z0-9]\{14\}')" ] && echo "Please specify identifier of the VM --vm='<identifier>' (14 symbols)"$'\n'   && help_fun 2 ;

# echo $FLAGS ; echo $VM_identifier
##### Onapp store versions
[ "$(echo "$onapp_store_ver"|wc -l)" -gt 1 ] && echo && RED 'MESS in onapp-store packeges:' && echo "$onapp_store_ver" && echo && onapp_store_ver_report=1;
verstore="$(echo "$onapp_store_ver"|sort -u|sed -n {1p}|cut -d '-' -f 4) " ;                                                                           # take onappstore-version
echo "$onapp_store_ver"|sort -u|sed -n {1p}|grep -e '3.3.0-19' -e '3.3.0-22' -e '3.[4-9].[0-9]' -e '3.3.[1-9]' -e '[4-9].[0-9].[0-9]' 1>/dev/null && ISD=1;
[ "$ISD" == 1 ] && SSH_TEL_FLAG='ssh';                                                                                           # script works by ssh to stvm only for onapp store versions which based on ISD
onapp_store_ver_dig=$(echo "$onapp_store_ver" |sed 's/install-/\n/g;s/.noa/\n/g'|grep [0-9] |head -n 1)                                                 # source rpm of onapp-store
if [ -n "$onapp_store_ver" ] ;
 then if [ "$onapp_store_ver_report" = 1 ] ; then echo 'ISchecker will use onapp-store ver [ '$verstore'] for check cloud.' ; yellow 'NOTE: Can be issues with checking cloud due isd/groupmon differences'; echo;
      else echo onapp-store ver: \[ $onapp_store_ver_dig \] ; fi;
      cloud_boot_enabled="$(cat /onapp/interface/config/on_app.yml  2>/dev/null |grep '^cloud_boot_enabled:'|cut -d ' ' -f 2)";
      [ "$cloud_boot_enabled" != 'true' ] && yellow 'Cloudboot is not enabled. Status='"$cloud_boot_enabled"  && echo && exit 3;
      is_storage_enabled=$(cat /onapp/interface/config/on_app.yml  2>/dev/null|grep '^storage_enabled'|cut -d ' ' -f 2);
      [ "$is_storage_enabled" != 'true' -a "$HVslist" != 'list' ] && yellow 'IS storage is not enabled. Status='"$is_storage_enabled" && echo && exit 3;
 else RED 'Please run script from CP where installed onapp-store package!'; exit 3
fi;

### Start header function
header_fun

## part for --ips key  ## begin
if [[ $FLAGS =~ 'take_ips' ]] ;                                                                 # get ips of HVs and storage controllers
 then echo ;
filter=''; filter_1='';
 [ -n "$zone" ]   && filter="and (hypervisor_group_id=$zone "  && filter_1+="${filter})" && filter+="or h.backup=1)"
 if [ -n "$zoneIP" ] ; then filter="and (h.hypervisor_group_id IN (select hypervisor_group_id from hypervisors where ip_address='$zoneIP') " ;  filter_1+="${filter})" ; filter+="or h.backup=1)";
 [[ $FLAGS =~ 'only' ]] && filter="and (h.ip_address='$zoneIP' "  && filter_1="${filter})" && filter+="or h.backup=1)" ; fi;

###HV IPs###############

hvs_ips=$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "select ip_address $dbselect and online=1 $filter_1"|sed '1d')
[ -z "$hvs_ips" ] && HVslist='list' && no_info

hvs_ips=$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "select ip_address $dbselect and online=1 $filter_1 group by hypervisors.id"|sed '1d')

echo ; yellow 'HVS output: ' ; echo -n '  for i in ' ; ip_sort_fun "$hvs_ips" '4' ; echo '; do echo $i;  ssh $i uptime ; done'$'\n';

###Storage controllers IPs###############
hvs_ips=$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "select ip_address $dbselect and online=1 $filter"|sed '1d')

st_vm_ips=$(for i in $hvs_ips; do curl --silent $i:8080/is/Node |ruby -rjson -e 'print JSON.pretty_generate(JSON.parse(STDIN.read))' 2> /dev/null |grep "ipaddr"|grep -v .254|sort|uniq|sed 's/"ipaddr"://g; s/[",]//g'; done)
st_vm_ips=$(echo "$st_vm_ips"| tr ' ' '\n' | sort -u | tr '\n' ' ')
parsing=$(echo $st_vm_ips |sed 's/10.200.//g; s/[[:space:]]/,/g')
final_range=$(echo "for i in" 10.200.{$parsing}"; do echo \$i ; ssh \$ssh_key \$i uptime ; done")
yellow 'Stvms output: ' ; echo $final_range;

echo 'ssh_key='"'$ssh_opt'" ; echo
 # echo ; echo 'TEST- stvms data' ; echo 'host_id  storage_controllers' ;echo "$stvms_data";
unset filter filter_1 hvs_ips st_vm_ips parsing final_range;
 exit 0 ; fi;
##  end of --ips

### KEYS

## part for vm/disk mode -- Begin
if [[ $FLAGS =~ 'vm_mode' ]] ;                                                                                                           # take info of vdisis and target HV. -- vm mode.
    then \
vm_mode_vdisks=$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "select d.identifier from disks d, data_stores ds where virtual_machine_id IN (select id from virtual_machines where identifier='$VM_identifier') and d.data_store_id = ds.id and ds.identifier NOT LIKE 'onapp-%'"| sed '1d');

[ -z "$vm_mode_vdisks" ] && yellow "there is no vm with identifier='$VM_identifier' in DB" && echo && exit 1 ;
zoneIP=$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "select ip_address from hypervisors where id IN (select hypervisor_id from virtual_machines where identifier='$VM_identifier')" | sed '1d');
FLAGS+="only";flag='disks'; fi;
[ -n "$zoneIP" -a -z "$(echo $FLAGS|grep only)" ] && zone=$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "select hypervisor_group_id from hypervisors where ip_address='$zoneIP' and mac <> '' and host_id is not NULL" | sed '1d') && \
checkopts zoneIP;
[ "$flag" = 'disks' ] && dbhv_all="$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "$dbprefix $dbselect" | sed '1d')";

if [ -z "$zone" ] ;
    then DBSELECT=$(echo "$dbprefix $dbselect and online=1  $dborder");
    else DBSELECT=$(echo "$dbprefix $dbselect and online=1 and hypervisor_group_id=$zone and online=1 $dborder"); # DB select for zone modes
fi;

if [[ $FLAGS =~ 'vm_mode' ]] ;                                                                                                           # print  info of vm/vdisks from DB
    then \
echo ; echo "VM '$VM_identifier' info:" ;
mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "select v.id as vm_id, v.memory, v.built, v.locked, v.booted, v.state, v.deleted_at, t.id as template_id, t.file_name, t.parent_template_id from virtual_machines v, templates t where v.identifier='$VM_identifier' and v.template_id = t.id"
echo ; echo vdisks info: ;
mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "select d.id, d.identifier, d.disk_vm_number, d.primary, d.disk_size, d.file_system, d.data_store_id, ds.identifier as ds_identifier, ds.hypervisor_group_id as hvs_zone from disks d, data_stores ds where virtual_machine_id IN (select id from virtual_machines where identifier='$VM_identifier') and d.data_store_id = ds.id"
fi;

[[ $FLAGS =~ 'only' ]] && if [ "$flag" != 'disks' ] ;
then DBSELECT=$(echo "$dbprefix $dbselect and ip_address='$zoneIP' and host_id is not NULL or backup=1 and mac <> '' and online=1 and host_id is not NULL") ;
else DBSELECT=$(echo "$dbprefix $dbselect and ip_address='$zoneIP' ") ;
fi

dbhv="$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "$DBSELECT" | sed '1d')";                                                              # data of hvs
dbhvoff="$(mysql -u "$dbuser" -p"$dbpass" "$dbname" -h "$dbhost" -e "$(echo "$DBSELECT"| sed 's/ine=1/ine=0/g')"| sed '1d')";                           # Data of offline hvs (if zone - filter by zone)


if [[ $FLAGS =~ 'only' ]] ; then [ -z "$(echo $dbhv $dbhvoff|grep -- "$zoneIP")" ] && no_info ;
else [ -z "$(echo "$dbhv"|grep -v NULL)" ] && [ "$zone" != NULL -a "$zone" != 0 ]  && no_info ; fi;
unset zone zoneIP;

if [ "$HVslist" = list ] ; then printf "%s\n"   "${RED}Cloudboot HVs with IS enabled: ${NORMAL}" ; printf "%$width.${width}s\n" "$divider"; printf '%-8b\t' 'ip_address' ' host_id   mtu    hvs_zone    label' ; echo;
    echo 'Online:' ;  advance_print_fun "$dbhv" '1'; echo;
    if [ -n "$dbhvoff" ] ; then echo 'Offline:' ; advance_print_fun "$dbhvoff" '1' ; fi ;
     exit 0;
fi;

function group_sort_fun() {
  # input:  values of groupmon processe from HVs and stvms ()
  # output: group_all_alarm - if mismatch - report in values and sort by zone / by HV /and sort ip of stvms
for i in `echo "$1"|awk '{print $1}'|sort -u| sed 's/hv_zone=//g'`;
    do  group_c="$(echo "$1"|grep -- "hv_zone=$i "| grep -o -P '(?<=groupmon ).*(?=$)'|sort -u)";
        [ "$(echo "$group_c"|wc -l)" -gt 1 ] && \
group_all_alarm="$group_all_alarm
$(echo)
$(echo 'In Hvs zone = '$i)" && \
        for  b in `bash -c "echo {1..$(echo "$group_c"|wc -l)}"`;  do \
group_key=$(echo $(echo "$group_c"|sed -n {"$b"p}|sed 's/224.3.28.[0-9]\+,\?//g') $(ip_sort_fun  "$(echo -n "$group_c"|sed -n {"$b"p}|grep -o '224.3.28.[0-9]\+')" 4))
group_all_alarm="$group_all_alarm
$(echo "--group settings: 'groupmon $group_key' For stvm:")";
             group_hv=$(echo "$1" | grep -- "hv_zone=$i "|grep -- "groupmon $(echo "$group_c"|sed -n {"$b"p})"|awk '{print $3}'|sort -u) ;
             for c in `echo "$group_hv"`; do \
group_all_alarm="$group_all_alarm
 $(echo -n "$c"': ' $(ip_sort_fun "$(echo "$1" | grep -- "hv_zone=$i "|grep -- "$c" |grep -- "groupmon $(echo "$group_c"|sed -n {"$b"p})"|awk '{print $4}'|tr -d 'stvm:()')" '4'); echo;)";
              done;
        done;
done;
}

function report_nodes_issues() {
# fun for report readble nodes issues.
# input:  $1 = nodes_statistic  or nodes_table ; $2 = mode(1 or 2).
# output: show readble report of issues
if [ "$2" = 1 ] ; then \
for node_zone in `echo "$1"|awk '{print $3}'|sort -u` ;
 do nodes_by_zone=$(echo "$1"|grep -- "$node_zone$"| awk '{print $2}'|sort -u)  ;                                                       # sort by zone.
if [ "$(echo "$nodes_by_zone"|wc -l)" -gt 1 ] ;
 then echo "Different amount of ACTIVE nodes in $node_zone";                                                                              # check zone on different active node's amount
 for nodes_amount in  `echo "$nodes_by_zone"|sort` ; do echo -n "ACTIVE($nodes_amount): ";                                                # sort by Active nodes amount by hv_zone
 nodes_issues=$(echo "$1"|grep -- "$nodes_amount $node_zone$");
 [ -n "$(echo "$nodes_issues"|grep -v '^10.200.')" ] && echo -n "HV(s): " &&  ip_sort_fun "$(echo "$nodes_issues"|grep -v '^10.200.'|sort| awk '{print $1}')" '4' ;  # ip_sort of HVs ip
 [ -n "$(echo "$nodes_issues"|grep '^10.200.')" ] && echo -n "stvm(s): " && ip_sort_fun "$(echo "$nodes_issues"|grep '^10.200.'|sort| awk '{print $1}')" '3' ;       # ip_sort of stvm
 echo; unset nodes_issues; done ;
fi;
done ;unset nodes_by_zone ; fi;

if [ "$2" = 2 ]; then \
  for node_zone in `echo "$1"|grep -v 'NO ACTIVE NODES!'|awk '{print $5}'|sort -u` ;                                                                               # sort by zone
   do echo "Bad node(s) status in $node_zone";
      for node_status in `echo "$1"|grep -v 'NO ACTIVE NODES!'|grep -- "$node_zone$"|sort -u|awk '{print $1}'|sort -u` ;                                         # sort by node
        do echo -n $node_status "($(echo "$1"|grep -- "$node_zone$" | grep -- "$node_status"|awk '{print $3}'|sort -u))";                                          # print node(ip)
echo -en "\t" ; echo -n ' status(s):('$(echo $(echo "$1"|grep -- "$node_zone$" | grep -- "$node_status" | awk '{print $2}'|sort -u))') ';                          # print statuses of target node
echo -en "\t" ; echo -n 'on HV(s)|stvm(s): '; ip_sort_fun "$(echo "$1"|grep -- "$node_zone$"|grep -- "$node_status"|awk '{print $4}'|sort -u)" '4'; echo;          # print sorted ips
   done; done;

  if [ -n "$(echo "$1"|grep 'NO ACTIVE NODES!')" ] ; then  echo 'NO ACTIVE NODES!';
   for node_zone in `echo "$1"|grep 'NO ACTIVE NODES!'|awk '{print $5}'|sort -u` ;
     do  node_ips=$(echo "$1"|grep 'NO ACTIVE NODES!'|grep -- "$node_zone$"|awk '{print $4}'|sort -u);
     echo -n "--in $node_zone: ";
     [ -n "$(echo "$node_ips"|grep -v '10.200.')" ] &&  echo -n 'HV(s) ' ; ip_sort_fun "$(echo "$node_ips" | grep -v '10.200.')" '4';
     [ -n "$(echo "$node_ips"|grep '10.200.')" ]    &&  echo -n 'stvm(s) ' ; ip_sort_fun "$(echo "$node_ips" | grep '10.200.')" '3';
     unset node_ips; echo ;
   done; fi;
fi;
}

clean_up 'usageHelp dbph dbselect dbhost dbname dbpass dborder DBSELECT' 'unset';

if [ always == always ] ;                                                                                                                       # the begining - new shell
then \

##########################  Take info from HV  -- IS state check:    ################################
  function take_hv_info_ssh_fun {
    # function gets info from HV
    # input:  ISD - flag of new IS daemon ; storage version. clean_up fun availeble
    # output: status of nodes; group|redis|API|isd|crond processes; locks files; IS versions controller|packege ; amount of free devs ; stvm - count of stvms ; diskhotplug issues and info
    ISD="$1"; verstore="$2";
    csvm='/onappstore/VMconfigs/';  stvm=0;
    [ -d "$csvm" ] &&  stvm=$(ls $csvm |grep 'NODE[0-9]\+-STORAGENODE[0-9]\+' |wc -l) && echo 'STVM NUMBER:'$stvm ;                              # count of storage vms
    if [ "$stvm" -gt 0 ] ;
       then diskhot=$(/usr/pythoncontroller/diskhotplug list);
            if [ -n "$diskhot" ] ;
               then [ $(echo "$diskhot"|grep 'Controller' -c) != "$stvm" ] && echo 'DISKHOTPLUG ERROR:mismatch -- Controller(s) from diskhotplug utility:'$(echo "$diskhot"|grep 'Controller' -c) 'should be stvm='$stvm;
                    Dhotdisks=$(echo "$diskhot" |grep  /dev/|grep -vE '\(SCSIid:[[:print:]]+NodeID:[0-9]+\)' | awk '{print $4}'| sed -e 's|/dev/||g' );
                    [ -n "$Dhotdisks" ] && echo 'DISKHOTPLUG ERROR:disk(s)_err -- Disk(s) without ICSIid or NodeID: ' $Dhotdisks ;
                    echo 'DISKHOTPLUGBG' ; echo "$diskhot" ; echo 'DISKHOTPLUGED';                                                               # print diskhotplug list
               else [ -z "$(echo $verstore|grep '3.0.[0-9]-')" ] && echo 'DISKHOTPLUG ERROR:nodata -- Absent MetaData for diskhotplug utility';  fi;
            fi ;

    [ -e /tmp/pinglock ]      && [ $(expr $(date +%s) - $(stat -c%Y /tmp/pinglock)) -ge 180 ]      && echo LOCK-PG pinglock;                     # take lock files which exist more then 180sec
    [ -e /tmp/freeinuselock ] && [ $(expr $(date +%s) - $(stat -c%Y /tmp/freeinuselock)) -ge 180 ] && echo LOCK-PG freeinuselock;
    echo is_ver     "$(cat /onappstore/package-version.txt   |grep 'Source RPM'|sed 's/Source RPM/\nSource RPM/g'|grep Source)";                 # take is_ver for each HV
    echo is_con_ver "$(cat /onappstore/controllerversion.txt |grep 'Source RPM'|sed 's/Source RPM/\nSource RPM/g'|grep Source)";                 # take is_ver for each HV
    if [ -d /tmp/NBDdevs/freedevs/ ] ; then echo free_devs "$(ls /tmp/NBDdevs/freedevs/|wc -l 2>/dev/null)" ;  else echo free_devs NODIR; fi;    # amount of free nbd devs
    if [ "$ISD" = 1 ] ;
      then echo hv_lockssort $(ls /tmp/|grep '.sort$') ;
           cron_tab=$(cat /etc/crontab|grep pythoncontroller);
           hv_overlay=$(echo $(ls -l /.rw/bootscripts/  |grep -v '[0-9] custom$\|^total \|~';ls -l /.rw/overlay/ 2>/dev/null)| grep -v '^$\|~');    # checking overlays on HV
           for i in localupdate check_active_sync timeout_nodes nbd_stats stale_devices;
              do   [ -z "$(echo "$cron_tab" |grep -- "$i"|grep '*/[1-2] * * * *')" ] && echo crontabER $i;
           done ;
    fi;
    [ -n "$hv_overlay" ] && echo 'OVERLAY WARN';

    onappstore nodes&
    ps aux|grep -E 'redis-server|groupmon|isd|storageAPI|crond|telnet'|grep -v grep;

    PIDJ=$(jobs -nl|grep 'onappstore nodes'|awk '{print $2}');                                                                                               # take process id of backg task
    while [ -n "$(ps x |awk '{print $1}'|grep -- "$PIDJ" )" -a "$count" != 28 ] ; do ((count++)); sleep 0.25  ; done                                         # waiting for 7 seconds if process still running
    if [ -n "$(ps x  |awk '{print $1}'|grep -- "$PIDJ")" ] ; then   kill -9 $PIDJ  $(ps aux|grep 'onappstore nodes'|awk '{print $2}') 2>/dev/null ; else echo NODECONTROL ; fi;      # kill bg process if it stil exist or return control
  }

function status_nodes_hv_fun() {
# function calculate info from HV
     [ "$tssh" -gt 20 ] && RED 'Please wait due Large time for get info via ssh';
     hv_stats=$(ssh $ssh_opt root@$hv "$(typeset -f take_hv_info_ssh_fun clean_up);take_hv_info_ssh_fun $ISD $verstore");                                         # get info from hv
  [ -z "$(echo "$hv_stats"|grep 'NODECONTROL')" ] && hv_alarm1=$(echo -e "$hv_alarm1""\n""Large time response from onappstore nodes on HV $hv");         # report hv onappstore commands timeout
  diskhot=$(echo "$hv_stats" |sed -n '/DISKHOTPLUGBG/,/DISKHOTPLUGED/p' |sed '1d;$d');
  diskhot_errors=$(echo "$hv_stats"|grep 'DISKHOTPLUG ERROR:') ; [ -n "$diskhot_errors" ] && if [ "$ISD" = 1 ] ; then hv_alarm='RED'; else hv_alarm='yellow' ; fi;
  [ -n "$diskhot_errors" ] && diskhot_errors_report="$diskhot_errors_report
  $(echo "$diskhot_errors"|sed "s/DISKHOTPLUG ERROR:/HV:\($hv\) /g")";                                                            # prepare report of diskhotplug issues.
  hv_locks=$(echo "$hv_stats"|grep -E 'LOCK-PG (freeinuselock|pinglock)'|grep -v bash|sed 's/LOCK-PG //g');                       # take lock files which exist more then 180sec
  [ -n "$hv_locks" ] && hv_alarm='RED' && locks_file_alarm=$(echo -e "$locks_file_alarm""\n"'HV:('$hv') -- '$hv_locks) ;
  [ "$ISD" = 1 ] && hv_lockssort=$(echo "$hv_stats"| grep 'hv_lockssort'|sed 's/hv_lockssort//g');
  [ -n "$hv_lockssort" ] && hv_alarm='RED' && locks_file_alarm=$(echo -e "$locks_file_alarm""\n"'HV:('$hv') -- '$hv_lockssort) ;  # set alarm and report lock issues
  stvm=$(echo "$hv_stats"|grep 'STVM NUMBER:'|grep -Po '[0-9]+') ; [ -z "$stvm" ] && stvm=0;                                      # take amount of storage controllers
  is_ver=$(echo -e "$is_ver""\n"$hv "$(echo "$hv_stats"|grep is_ver|sed 's/is_ver//g')");                                         # echo $is_ver; # get is ver
  is_con_ver=$(echo -e "$is_con_ver""\n"$hv "$(echo "$hv_stats"|grep is_con_ver|sed 's/is_con_ver//g')");                         # echo $is_con_ver;
  hv_active=$(echo "$hv_stats"  |grep 'status: ACTIVE' |uniq -c | awk  '{print $3,$1}'|sed 's/ /:/');                             # active nodes
  hv_partial=$(echo "$hv_stats" |grep PARTIAL          |uniq -c | awk  '{print $3,$1}'|sed 's/ /:/');                             # partial nodes
  hv_delay=$(echo "$hv_stats"   |grep DELAY            |uniq -c | awk  '{print $3,$1}'|sed 's/ /:/');                             # delay ping nodes
  hv_inactive=$(echo "$hv_stats"|grep INACTIVE         |uniq -c | awk  '{print $3,$1}'|sed 's/ /:/');                             # active nodes
  hv_outspace=$(echo "$hv_stats"|grep OUT_OF_SPACE     |uniq -c | awk  '{print $3,$1}'|sed 's/ /:/');                             # out of space nodes
  hv_group=$(echo "$hv_stats"   |grep groupmon         |cut -d '/' -f 7  |uniq -c|sed 's/onappstoresan/*san/g') ;                 # groupmon
  hv_redis=$(echo "$hv_stats"   |grep redis-server     |awk '{print $11}'|cut -d '/' -f 4);                                       # redis
  hv_hanged_process=$(echo $(echo "$hv_stats"|grep [t]elnet| grep -v 'grep telnet'|grep bash)$(echo "$hv_stats"|grep ' telnet 10.200.'|sed 's/\([0-9]\{0,4\}:[0-9]\{2\} telnet\)/\n\1/g'|grep tel|sed 's/ /\n/g'|grep ':'|sed 's/:[0-9]\{2\}//g'|grep -E '[0-9]{3,}'));
  [ -n "$hv_hanged_process" ] && hv_alarm='RED' ;
  nodes_issues=$(echo $(echo "$hv_stats" |grep -E 'PARTIAL|DELAY|INACTIVE|OUT_OF_SPACE' -C 1) | sed 's/Node: //g;s/status://g;s/IP addr://g;s/\(10\.200\.[0-9]\+\.[0-9]\+\)/\1\n/g;s/^[ -]\+//g');
  clean_up 'nodes_issues' 'empties'
  [ -n "$nodes_issues" ] && nodes_issues=$(echo "$nodes_issues"|sed "s/$/ $hv hv_zone=$(echo "$DBHV" | cut  -f 4)/g" ) &&  nodes_table="$nodes_table
 $nodes_issues"; unset nodes_issues;                                                                                              # for report of bad status of nodes
  if [ -n "$hv_active" ] ; then nodes_statistic=$(echo -e "$nodes_statistic""\n"$hv $hv_active hv_zone=$(echo "$DBHV" | cut  -f 4)|sed 's/ACTIVE://g') ;
   else nodes_table="$nodes_table
$(echo "NO ACTIVE NODES! $hv hv_zone=$(echo "$DBHV" | cut  -f 4)")"; fi;                                                  # add to nod_table records about count of ACTIVE nodes if amout of its is 0;
  if [ "$ISD" = 0 ] ;                                                                                                             # groupmon / isd
    then  if [ -n "$hv_group" ] ;
              then  hv_group_all=$(echo -e "$hv_group_all""\n"'hv_zone='$(echo "$DBHV"|cut -f 4) ' -- HV:('$hv') stvm:(10.200.'$Hid.254\) $hv_group);
                    if [ $(echo "$hv_group"|sed 's/ group/\ngroup/g'|sed '1!d; s/ //g') != 7 ] ;                                                             # reeport if less then 7
                      then  group_report=$(echo -e "$group_report""\n"HV: $hv ' -- ''Groupmon processes:' $(echo "$hv_group"|sed 's/ group/\ngroup/g'|sed '1!d; s/ //g')) ;
                            hv_alarm='yellow' ; group_alarm=1;
                      else group_alarm=;
                    fi;
              else  hv_alarm='RED'; group_alarm=1;
                    group_report=$(echo -e "$group_report""\n"HV: $hv ' -- ''No groupmon processes!' ) ;
          fi;
    else  hv_isd_procs=$(echo "$hv_stats"|grep 'isd '|grep -v grep | awk '{print $11, $12}'|grep -v '^$') ;                                                   #  check isd process
          if [ -n "$hv_isd_procs" ] ;  then if [ -z "$(echo "$hv_isd_procs"|grep -- '-C')" ] ;
                                              then  hv_alarm='yellow' ; isd_report=$(echo -e "$isd_report""\n"'HV: '$hv' -- No option "-C" for isd process!' ) ;
                                              else isd_alarm=; fi;
            else hv_alarm='RED'; isd_alarm=1;
                 isd_report=$(echo -e "$isd_report""\n"'HV: '$hv' -- No isd process!' ) ;
          fi;
          [ -n "$hv_group" -o -n "$hv_redis" ] && group_alarm=1 && hv_alarm='RED' && group_report=$(echo -e "$group_report""\n"HV: $hv ' -- Running Groupmon|redis processes with isd!') ;
          hv_crond=$(echo "$hv_stats"|grep crond|grep -v grep | awk '{print $11}'|grep -v '^$');                                                    # check crond
          if [ -n "$hv_crond" ] ;
            then hv_cron_tab_err=$(echo "$hv_stats"|grep crontabER|sed 's/crontabER //g'|grep -v '^$');
                   [ -n "$hv_cron_tab_err" ] && hv_cron_report=$(echo -e "$hv_cron_report""\n"HV: $hv ' -- Not default values or missing records in /etc/crontab for:' $(echo $hv_cron_tab_err|sed 's/ /;/g')) && hv_alarm='RED';
            else hv_alarm='RED';hv_cron_report=$(echo -e "$hv_cron_report""\n"HV: $hv ' -- No crond process!');
          fi;
          hv_overlay=$(echo "$hv_stats"|grep 'OVERLAY WARN');                                                                                       # overlays warning
          [ -n "$hv_overlay" ] &&  hv_overlay_report="$hv_overlay_report $hv;";
  fi;
  hv_API=$(echo "$hv_stats"     |grep storageAPI       |awk '{print $12}'|cut -d '/' -f 4|uniq -c)                                                  # api
  if [ -n "$hv_API" ] ;
      then if [ $(echo $hv_API |sed 's/ /\n/g'|sed '1!d; s/ //g') -lt '12' ] ;                                                                      # reeport if less then 12
              then api_report=$(echo -e "$api_report""\n"HV: $hv ' -- ''API processes:' $(echo "$hv_API" |sed 's/ /\n/g'|sed '1!d')) ;
                   hv_alarm='yellow'; api_alarm=1; [ -n "$group_alarm" -o -n "$isd_alarm" ] && hv_alarm='RED';
              else api_alarm=;
          fi;
      else hv_alarm='RED'; api_alarm=1; api_report=$(echo -e "$api_report""\n"HV: $hv ' -- ''No API processes!' ) ;
  fi;
  if [ "$ISD" = 0 ] ;
    then [ -n "$hv_delay" -o -z "$hv_active" -o -z "$hv_group" -o -z "$hv_API" -o -z "$hv_redis" ] && hv_alarm='RED';                               # RED Warning if has issues
    else [ -n "$hv_delay" -o -z "$hv_active" -o -z "$hv_API" ] && hv_alarm='RED'; fi;
  [ "$hv_alarm" != 'RED' ] && [ -n "$hv_delay" -o -n "$hv_partial" -o -n "$hv_outspace" ] && hv_alarm='yellow';                                     # yellow Warning if has issues
  free_devs=$(echo "$hv_stats"|grep free_devs|grep -Po [0-9]+);
  [ -n "$free_devs" ] && [ "$free_devs" -lt 20 ] && [ "$hv_alarm" != 'RED' ] && hv_alarm='yellow' ;

  status_nodes_hv_print_fun;

   [ "$stvm" != 0 ] && telnet_connect_fun;                                                                               # run telnet fun if there is at some storage vms
}

function status_nodes_hv_print_fun() {
# function is printing  HV state. running on CP in one shell as status_nodes_hv_fun
   echo 'Check IS state:';
   echo -n -check HV: -- nodes: { $hv_active $hv_inactive;                                                                                         # output for hv status of node fun
   [ -n "$hv_partial" -o -n "$hv_delay" -o "$hv_outspace" ] && yellow  ' '$hv_partial $hv_delay $hv_outspace ;
   echo -n ' '} -- Running processes: {' ' ;
 if [ "$ISD" = 0 ] ;
   then hv_group_sort=$(echo $(echo $hv_group|sed 's/224.3.28.[0-9]\+[, ]\?//g') "$(ip_sort_fun  "$(echo -n $hv_group |grep -o '224.3.28.[0-9]\+')" 4|sed 's/\[\([1-9]\+\)\]/\1/g')"); # sort ip of multicast channel
   if [ -z "$group_alarm" ] ; then echo -n "$hv_group_sort" ; else yellow "$hv_group_sort" ; fi ;
   echo -n ' -- '; fi;
   if [ -z "$api_alarm" ] ;   then echo -n $hv_API ;   else yellow $hv_API ;   fi ;
   echo -n ' -- ' ;
 [ "$ISD" = 1 ] && if [ -z "$isd_alarm" ] ; then echo -n $hv_isd_procs '}  '| sed "s/\/onappstore\/bin\///g"; else echo -n '}  ' ; fi;
 [ "$ISD" = 0 ] &&  echo -n $hv_redis } ' ' ;
   [ "$hv_alarm" == yellow ] && yellow ' 'WARNING!;
   [ "$hv_alarm" == RED ] && redb ' 'WARNING!;                                                                                                     # output for hv status of node fun
 [ "$ISD" = 1 -a -n "$hv_overlay" ] && yellow ' -has Overlay' ;
   echo;
   [ -n "$hv_hanged_process" ] && RED 'Found out Hanged telnet process(es)!' && hv_hanged_process_report=$(echo -e "$hv_hanged_process_report""\n"'Hanged telnet transaction(s) on HV:'\($hv\));
   if [ -n "$free_devs" ] ;
      then [ "$free_devs" -lt 20 ] && RED "Small amount of free nbd devices. Free devs: $free_devs" && free_devs_alart=$(printf '%-17b\t' "$free_devs_alart""\n""HV:($hv)" Free_nbd_devs:$free_devs );
      else [ -n "$hv_stats" ] && RED 'No directory /tmp/NBDdevs/freedevs/ !' && free_devs_alart=$(printf '%-17b\t' "$free_devs_alart""\nHV:($hv)" 'No directory /tmp/NBDdevs/freedevs/');
   fi;
   if [ "$ISD" = 1 ] ; then \
      [ -n "$hv_group" -o -n "$hv_redis" ] &&  redn 'Found out groupmon or redis-server processes: ' && yellow $hv_group ';' $hv_redis && echo;    # error if running group on isd
      [ -z "$hv_crond" ] && RED 'crond process is not running!';                                                                                   # red when no crond process on HV with isd
      [ -n "$hv_cron_tab_err" ] &&  RED 'Not default values or missing records in /etc/crontab for:' "$hv_cron_tab_err";                           # if not default values
      [ -n "$diskhot_errors" ] && RED "$diskhot_errors" ;
      else  [ -n "$diskhot_errors" ] && yellow "$diskhot_errors" && echo ;   fi;
   [ -n "$hv_lockssort" ] && RED "Found out '.sort' file(s):" $hv_lockssort 'in /tmp/ directory';
   [ -n "$hv_locks" ] && RED 'Lock(s) file(s) which exist more then 3 minutes:' $hv_locks 'in /tmp/ directory';                    # print hanged locks files.
   echo  "should be running storage vms: $stvm";

}

function take_info_inside_stvm() {
  ps w|grep -E 'group|redis|API|isd|dropbear';
  [ -e /tmp/freeinuselock ] && [ $(expr $(date +%s) - $(stat -c%Y /tmp/freeinuselock)) -ge 180 ] && echo LOCK-PG freeinuselock;
  [ -e /tmp/pinglock ] && [ $(expr $(date +%s) - $(stat -c%Y /tmp/pinglock)) -ge 180 ] && echo LOCK-PG pinglock ;
  for disk_txn in `ls /DB/NODE-*/*.txn |grep '.txn$'` ;  do [ $(expr $(date +%s) - $(stat -c%Y $disk_txn)) -ge 180 ] && echo LOCK-DISK-TXN  $disk_txn; done 2>/dev/null
  ls /DB/NODE* |grep 'ls:'|grep 'Input/output error'
  for i in `ls /onappstore/DB/Node/` ;
    do  echo -n $i ' ' $(cat /onappstore/DB/Node/$i/status|sed 's/1/ACTIVE/g;s/2/PARTIAL/g;s/3/DELAYED_PING/g;s/4/OUT_OF_SPACE/g;s/0/INACTIVE/g;s/^/status: /g') ' ' ; # take nodes status from FS.
         cat /onappstore/DB/Node/$i/ipaddr ; done ; echo;
  dmesg|grep XFS|grep error|sort -u;
  df -h;
}

function take_stvm_info_ssh() {
# $ssh_opt # clean_up availeble
stvm="$1"; ssh_opt="$2"; Hid="$3"; ISD="$4" ; hv="$5" ; DBHV="$6";
library_ssh_color_funs                                                                                                                    # standart color_fun ; for colorise but on HV when check stvms

echo "stvm_ssh_outputB";
for T in `bash -c "echo {1..$stvm}"`;
do if ssh -q $ssh_opt 10.200.$Hid.$T exit ;
    then stvm_info_all_ssh=$(ssh $ssh_opt 10.200.$Hid.$T "$(typeset -f take_info_inside_stvm); take_info_inside_stvm");
         telinfo_proc=$(echo "$stvm_info_all_ssh"|grep -E 'group|redis|API|LOCK-PG|LOCK-DISK-TXN|isd |dropbear '|grep -v 'grep');         # take list of processes and locks files
         tel_ioerr=$(echo "$stvm_info_all_ssh"  |grep 'ls:'|grep 'Input/output error';)                                                   # I/O errors on Node. Cant read Node by 'ls'
         telinfo_node=$(echo "$stvm_info_all_ssh"|grep -E 'status' |grep 'status: ');                                                     # take status of nodes
         tel_xfs_err_all=$(echo "$stvm_info_all_ssh" |grep -i error|grep -v grep|sort -u);                                              # xfs errors from dmesg
         telinfo_df_all=$(echo "$stvm_info_all_ssh"|grep vd|grep NODE);                                                                   # take: df -h
      calculate_stvm_info "ssh" "$ISD" "$telinfo_node" "$hv" "$DBHV";
    else redn "Cant log in via ssh to" ; yellow " 10.200.$Hid.$T!" ; echo ;stvms="${stvms} $T";  fi;
done ; [ -n "$stvms" ] && yellow "Will try via telnet. stvms:($stvms )" && echo;
echo; echo "stvm_ssh_outputE";
echo STVMSS $stvms;
echo stvm_ssh_reportsB;                                                                                                                   # transmit all values from this bash
  clean_up 'telinfo_df_report group_report dropbear_alarm isd_report locks_file_alarm tel_ioerr_report xfs_alarm nodes_table nodes_statistic api_report' 'B|E' 'empties' ;  # transmit all reports by adding word keys B|E
echo stvm_ssh_reportsE;                                                                                                                   # transmit

}

function calculate_stvm_info() {
  # function calculates info for each storage controller and prints it;       # has clean_up
  # input:  ssh_tel_flag - flag of ssh or telnet geting tool; telinfo_proc ; tel_xfs_err_all; telinfo_node; telinfo_df_all; ISD || running on hv and inside stvm
  # output: generate output of stvm; calculate report for several items
ssh_tel_flag="$1"; if [ "$ssh_tel_flag" == 'ssh' ] ; then ISD="$2";  telinfo_node="$3" ; hv="$4"  DBHV="$5"; fi;
               tel_locks=$(echo "$telinfo_proc"|grep 'LOCK-PG'|grep -vE '&&|^$|grep'|sed 's/LOCK-PG //g'|grep -v '^$');   # get lock files if exist
               tel_txn_disks=$(echo "$telinfo_proc"|grep '^LOCK-DISK-TXN'| sed 's/LOCK-DISK-TXN//g');
               if [ -n "$tel_txn_disks" ] ; then  locks_file_alarm=$(echo -e "$locks_file_alarm""\n"'HV:('$hv') storage vm:(10.200.'$Hid.$T')' -- "$tel_txn_disks") ; tel_alarm='yellow' ; fi;
               if [ -n "$tel_locks" ] ; then  locks_file_alarm=$(echo -e "$locks_file_alarm""\n"'HV:('$hv') storage vm:(10.200.'$Hid.$T')' -- $tel_locks) ; tel_alarm='RED' ; fi ;  #
               tel_xfs_err=$(echo "$tel_xfs_err_all"|grep -E vd[a-z]);   tel_xfs_errs=$(echo "$tel_xfs_err_all"|grep -v vd[a-z]|grep -v '^$');                                                                                                     # corrupted nodes due xfs
               [ -n "$tel_xfs_err" ] && tel_disk_xfs_err=$(echo "$tel_xfs_err" |sed 's/ /\n/g'|grep -E vd[a-z]|sort -u|sed 's/(//g; s/)://g'|grep -v '^$'  ) ;        # name of disks where xfs corrupted
               for xfs_check_d in `echo "$tel_xfs_err"|grep -Eo '(vd[a-z])'|sort -u` ;
                  do [ -z "$(echo "$telinfo_df_all"|grep -- "/dev/${xfs_check_d}")" ] && xfs_check=1;             # validity check xfs issue records from dmesg  (check mounting node, if not - report error)
               done;
               telinfo_df=$(echo "$telinfo_df_all" |grep '100%' |sed 's/\r//'|awk '{print $6,$5}'|sed 's/\n//g')                                                        # 100% usage Hdisk(node)
               if [ -n "$telinfo_df" ] ; then telinfo_df_report="$telinfo_df_report
               $(echo 'HV:('$hv') stvm:(10.200'.$Hid.$T') Node(s):' $telinfo_df |sed -e 's|/DB/|-- |g')"; telinfo_df=$(echo 'overflow: {' "$telinfo_df" }) ; fi;        # report overflowed nodes
               telinfo_node_stat=$(echo "$telinfo_node"| sed 's/\(status: [A-Z_]\+ \)/\n\1\n/g');
               tel_active=$(echo "$telinfo_node_stat"    |grep 'status: ACTIVE'  |uniq -c|awk  '{print $3,$1}'|sed 's/ /:/; s/\n//')                                    # count of active node
               tel_partial=$(echo "$telinfo_node_stat"   |grep PARTIAL           |uniq -c|awk  '{print $3,$1}'|sed 's/ /:/; s/\n//')                                    # count of  partial
               tel_delay=$(echo "$telinfo_node_stat"     |grep DELAY             |uniq -c|awk  '{print $3,$1}'|sed 's/ /:/; s/\n//')                                    # count of delay
               tel_inactive=$(echo "$telinfo_node_stat"  |grep INACTIVE          |uniq -c|awk  '{print $3,$1}'|sed 's/ /:/; s/\n//')                                    # count of inactive
               tel_outspace=$(echo "$telinfo_node_stat"  |grep OUT_OF_SPACE      |uniq -c|awk  '{print $3,$1}'|sed 's/ /:/; s/\n//')                                    # count of out of space
               tel_redis=$(echo "$telinfo_proc"     |grep redis-server      |awk '{print $5}'|cut -d '/' -f 4);                                                         # redis
               tel_group=$(echo "$telinfo_proc"     |grep groupmon          |cut -d '/' -f 7|uniq -c)                                                                   # count of gropmon processes
        nodes_issues=$(echo "$telinfo_node"  |grep -E 'PARTIAL|DELAY|INACTIVE|OUT_OF_SPACE' | sed 's/ status: //g;s/ [ -]\+/ /g'); clean_up 'nodes_issues' 'empties';
        [ -n "$nodes_issues" ] && nodes_issues=$(echo "$nodes_issues"|sed "s/$/ 10.200.$Hid.$T hv_zone=$(echo "$DBHV" | cut  -f 4)/g") && nodes_table="$nodes_table
$nodes_issues"   && unset nodes_issues;
        if [ -n "$tel_active" ] ; then nodes_statistic=$(echo -e "$nodes_statistic""\n"10.200.$Hid.$T $tel_active hv_zone=$(echo "$DBHV" | cut  -f 4) |sed 's/ACTIVE://g') ;
        else  nodes_table="$nodes_table
$(echo "NO ACTIVE NODES! 10.200.$Hid.$T hv_zone=$(echo "$DBHV" | cut  -f 4)")"; fi;                                                                              # add to nod_table records about count of ACTIVE nodes if amout of its is 0

        if [ "$ISD" = 0 ] ;                                                                                                                                             # group|redis or isd|dropbear
            then  if [ -n "$tel_group" ] ;
                      then tel_group_all=$(echo -e "$tel_group_all""\n"'hv_zone='$(echo "$DBHV"|cut -f 4) ' -- HV:('$hv') stvm:(10.200.'$Hid.$T\) $tel_group);
                           if [ $(echo "$tel_group"|sed 's/ group/\ngroup/g'|sed '1!d; s/ //g') != 7 ] ;                                                               # report if less then 7
                            then group_report=$(echo -e "$group_report""\n"HV: $hv ' -- ''Groupmon processes:' $(echo "$tel_group"|sed 's/ group/\ngroup/g'|sed '1!d; s/ //g') -- storage vm: 10.200.$Hid.$T) ;
                                 tel_alarm='yellow' ; group_alarm=1;
                            else unset group_alarm;
                           fi;
                       else  tel_alarm='RED' ; group_alarm=1; group_report=$(echo -e "$group_report""\n"HV: $hv ' -- ''No Groupmon processes:' -- storage vm: 10.200.$Hid.$T) ;
                  fi;
            else tel_isd_procs=$(echo "$telinfo_proc" |grep 'isd '      | awk '{print $5, $6}'| grep -v grep |sed 's/\/onappstore\/bin\///g') ;                                  # check isd daemon
                 tel_dropbear=$(echo "$telinfo_proc"  |grep 'dropbear ' | awk '{print $5, $6}'    |grep -v grep| sort -u |sed -e 's|^ +||g; s|/usr/sbin/||g; s|[0-9]+ ||g') ;  # check droppbear(ssh)

                 [ -z "$tel_dropbear" ] && tel_alarm='yellow' && dropbear_alarm=$(echo -e "$dropbear_alarm""\n"'HV:' $hv ' -- stvm: 10.200.'$Hid.$T' -- No dropbear proces!');
                 if [ -n "$tel_isd_procs" ] ; then if [ -z "$(echo "$tel_isd_procs"|grep -- '-C')" ] ;
                                                    then  tel_alarm='yellow' ;isd_alarm=1; isd_report=$(echo -e "$isd_report""\n"'HV: '$hv' stvm: 10.200.'"$Hid.$T"' -- No option "-C" for isd process!' ) ;
                                                    else isd_alarm=; fi;
                    else tel_alarm='RED' ; isd_alarm=1; isd_report=$(echo -e "$isd_report""\n"'HV: '$hv ' -- stvm:' 10.200.$Hid.$T -- No isd process!) ;
                 fi;
                 [ -n "$tel_group" -o -n "$tel_redis" ] && isd_alarm=1 && tel_alarm='RED' && group_report=$(echo -e "$group_report""\n"HV: $hv ' -- Running Groupmon|redis processes with isd!' -- storage vm: 10.200.$Hid.$T) ;
        fi;
               tel_api=$(echo "$telinfo_proc"       |grep storageAPI        |cut -d '/' -f 7|uniq -c)  ;
          if [ -n "$tel_api" ] ;                                                                                                                                                 # count api processes
             then if [ $(echo $tel_api |sed 's/ /\n/g'|sed '1!d; s/ //g') -lt '4' ] ;                                                                                            # report if less then 4
                    then api_report=$(echo -e "$api_report""\n"HV: $hv ' -- ''API processes:' $(echo $tel_api |sed 's/ /\n/g'|sed '1!d') -- storage vm: 10.200.$Hid.$T) ;
                         tel_alarm='yellow'; api_alarm=1; [ -n "$group_alarm" -o -n "$isd_alarm" ] && tel_alarm='RED';
                    else api_alarm=;
                  fi;
             else  tel_alarm='RED'; api_alarm=1; api_report=$(echo -e "$api_report""\n"HV: $hv ' -- ''No API processes:' -- storage vm: 10.200.$Hid.$T) ;
          fi;
              if [ "$ssh_tel_flag" == 'ssh' ] ; then  tel_dif_err=$(ssh $ssh_opt 10.200.$Hid.$T "onappstore nodelocalinfo uuid=\$(ls /DB|grep NODE| sed 's/NODE-//g'|grep -o '[0-9]\+$'|head -n 1)");  fi;
              # echo ---$tel_dif_err---;
              [ -n "$(ssh $ssh_opt 10.200.$Hid.$T "ls /DB/NODE* 2>/dev/null"|grep -v '^$')" ] && \
              [ "$(echo "$tel_dif_err"|sed 's/\(result=\(SUCCES\|FAILURE\)\)/\1\n/g'|grep 'result')" == 'result=FAILURE' ] &&  api_report=$(echo -e "$api_report""\n"HV: $hv stvm: 10.200.$Hid.$T 'API-call failed! '$(echo $tel_dif_err|grep result)) && tel_alarm='RED' && api_alarm=1;
###### stvm output:
               echo -n 10.200.$Hid.$T -- nodes: { $tel_active;                                                                                                                   # start print telnet fun info
               [ -n "$tel_partial" -o -n "$tel_delay" -o -n "$tel_outspace" ] && tel_alarm='yellow' && yellow ' '$tel_partial $tel_delay $tel_inactive $tel_outspace;
               echo -n ' '} -- Running processes: {' ';
               if [ "$ISD" = 0 ] ;
                     then  if [ -z "$group_alarm" ] ; then echo -n $tel_group ; else yellow $tel_group ; fi ;
                     echo -n ' -- ';
               fi;
               if [ -z "$api_alarm" ] ;   then echo -n $tel_api ;   else yellow $tel_api;    fi ;
               if [ "$ISD" = 0 ] ;
                 then  echo -n ' -- ' $tel_redis;
                 else  echo -n '  -- ' ;
                       echo -n $tel_isd_procs ;
                       echo -n ' -- ' ;
                       echo -n $tel_dropbear ;
               fi ;
                  echo -n ' }  ' ;
               [ -n "$telinfo_df" ] && yellow ' '$telinfo_df;
               [ -n "$tel_ioerr" -o "$xfs_check" = 1 ] && tel_alarm='RED';
               [ "$tel_alarm" == yellow ] &&  yellow ' 'WARNING!;
               [ "$tel_alarm" == RED ]    &&  redn ' 'WARNING!;
               [ -n "$(echo "$tel_dif_err" |grep 'result=FAILURE')" -a "$api_alarm" == 1 ] && redn ' API-call failed! ';
               [ "$ISD" = 1 ] && [ -n "$tel_group" -o -n "$tel_redis" ] && echo && redn 'Found out groupmon or redis-server processes:' && yellow "$tel_group" ';' "$tel_redis" ;   # error if running group on isd
               [ -n "$tel_locks" ] && echo && redn '-Lock(s) file(s) which exist more then 3 minutes:' $tel_locks 'in /tmp/ directory';                                             # print hanged locks files.
               [ -n "$tel_txn_disks" ] && echo && yellow '-Lock(s) vdisk(s) file(s) which exist more then 3 minutes:' "$tel_txn_disks" ;

               if [ -n "$tel_ioerr" ] ;
                  then  echo; redn "$tel_ioerr" |sed 's/ls/ ls/g';
                        [ -n "$diskhot" ] && [ -z "$(echo tel_ioerr_report|grep $hv)" ] && tel_ioerr_report=$(echo -e "$tel_ioerr_report""\n"Diskhotplug list on $hv"\n""$diskhot");
                        tel_ioerr_nodes=$(echo "$tel_ioerr"|sed 's/ /\n/g'|grep NODE|cut -d '-' -f 2|sed 's/://g');
                        tel_ioerr_report=$(echo -e "$tel_ioerr_report""\n"--On HV: $hv 'storage vm:' 10.200.$Hid.$T "\n"'Corrupted disk(s) in storage vm:' $(echo "$telinfo_df_all"|grep -- "$tel_ioerr_nodes"|awk '{print $1}'|cut -d '/' -f 3));
                        for ionerrodes in `echo "$tel_ioerr_nodes"` ;
                            do tel_ioerr_disk=$(echo "$telinfo_df_all"|grep "$ionerrodes"|awk '{print $1}'|cut -d '/' -f 3);
                               tel_grep_m=' `- ';
                               if [ "$ssh_tel_flag" == 'telnet' ] ;
                                then tel_ioerr_map=$(ssh $ssh_opt root@$hv "cat /onappstore/VMconfigs/NODE$T-*|sed 's/ /\n/g' |grep $tel_ioerr_disk -B 5 |grep STORAGEDEV |cut -d '/' -f 4" |sed -e 's|\x22||g');
                                     tel_ioerr_dmmap=$(ssh $ssh_opt root@$hv dmsetup ls --tree |grep "$tel_ioerr_map" -A 1|grep -E "$tel_ioerr_map|$tel_grep_m");
                                else tel_ioerr_map=$(cat /onappstore/VMconfigs/NODE$T-*|sed 's/ /\n/g' |grep $tel_ioerr_disk -B 5 |grep STORAGEDEV |cut -d '/' -f 4|sed -e 's|\x22||g');
                                     tel_ioerr_dmmap=$(dmsetup ls --tree |grep "$tel_ioerr_map" -A 1|grep -E "$tel_ioerr_map|$tel_grep_m");
                               fi;
                               if echo $tel_ioerr_dmmap|grep "$tel_grep_m" 1>/dev/null ;
                                  then tel_ioerr_dmapU=$(echo "$tel_ioerr_dmmap" |grep "$tel_grep_m"| cut -d ' ' -f 3 |sed 's/[(/)]//g'|grep -v '^$') ;
                                       if [ "$ssh_tel_flag" == 'telnet' ] ;
                                        then  tel_ioerr_Hdisk=$(echo 'Hard disk on HV:'$(ssh $ssh_opt root@$hv "ls -l /dev |grep sd" |grep "$(echo $tel_ioerr_dmapU|cut -d ':' -f 1)" | grep "$(echo $tel_ioerr_dmapU|cut -d ':' -f 2)" |sed 's/ /\n/g'| grep sd));
                                        else tel_ioerr_Hdisk=$(echo 'Hard disk on HV:'$(ls -l /dev |grep sd |grep "$(echo $tel_ioerr_dmapU|cut -d ':' -f 1)" | grep "$(echo $tel_ioerr_dmapU|cut -d ':' -f 2)" |sed 's/ /\n/g'| grep sd));
                                       fi;
                                       [ -z "$(echo $tel_ioerr_Hdisk |grep sd)" ]  && tel_ioerr_Hdisk=$(echo 'Hard disk on HV: no link to device in /dev/');
                                  else tel_ioerr_Hdisk=$(echo 'Cant find out link for hard disk on HV by dmsetup ls --tree|grep' $tel_ioerr_map) ;
                               fi;

  tel_ioerr_report=$(echo -e "$tel_ioerr_report""\n"'Device for' $tel_ioerr_disk\($ionerrodes\) 'from storage vm config: ' $tel_ioerr_map"\n"'Dmsetup for hard disk:' $tel_ioerr_dmmap"\n"$tel_ioerr_Hdisk) ;
                        done ;
                        if [ -n "$diskhot" ] ; then for erdisk in `echo "$diskhot" |cut -d ' ' -f 4|grep dev` ;
                                                      do if [ "$ssh_tel_flag" == 'telnet' ] ;
                                                      then [ -z "$(ssh $ssh_opt root@$hv fdisk $erdisk -l 2>/dev/null)" ] && tel_ioerr_Harddisks=("$tel_ioerr_Harddisks"' '"$erdisk") ;
                                                      else [ -z "$(fdisk $erdisk -l 2>/dev/null)" ] && tel_ioerr_Harddisks=("$tel_ioerr_Harddisks"' '"$erdisk") ; fi;
                                                   done ;
                                                   [ -n "$tel_ioerr_Harddisks" ] && tel_ioerr_report=$(echo -e "$tel_ioerr_report""\n"'No info from fdisk -l for disk(s)':$tel_ioerr_Harddisks) ;

                                               else [ -z "$(echo $verstore|grep '3.0.[0-9]-')" ] && tel_ioerr_report=$(echo -e "$tel_ioerr_report""\n"On $hv' doesnt work diskhotplug utility') ;
                        fi;
               fi;

               if [ -n "$tel_ioerr" -o "$xfs_check" = 1 ] ; then \
                  if [ -n "$tel_xfs_errs" ] ; then \
                    echo ; redn "$(echo "$tel_xfs_errs"|grep -v vd[a-z]|sort -u|grep -v '^$')" ; xfs_alarm=$(echo -e "$xfs_alarm""\n"'on HV:('$hv') in stvm:(10.200.'$Hid.$T') from dmesg:'"\n""$tel_xfs_errs"); fi;
                xfs_count=0;
               [ -n "$tel_disk_xfs_err" ] && for xfs_disks in "$tel_disk_xfs_err" ;
                                                 do ((xfs_count++))
                                                    tel_node_xfs_err="$(echo "$telinfo_df_all" |grep "$xfs_disks" |sed "s/\r//g")"; [ -z "$tel_node_xfs_err" ] && tel_node_xfs_err="$(echo \[$xfs_disks'] -- not mounted inside stvm')";
                                                    echo && redn $(echo "$tel_xfs_err"|sed 's/at line/\n/g'|grep 'XFS\|/dev/') -- "$(echo "$tel_node_xfs_err"|sed 's/\r//g')";
                          [ -n "$tel_xfs_err" ]  && xfs_alarm=$(echo -e "$xfs_alarm""\n" 'HV:('$hv') stvm:(10.200.'$Hid.$T') -- from dmesg:'"\n"$(echo "$tel_xfs_err"|sed 's/at line/\n/g'|grep 'XFS\|/dev/'));
                                                    xfs_alarm=$(echo -e "$xfs_alarm""\n" 'HV:('$hv') stvm:(10.200.'$Hid.$T') -- '$(echo "$tel_node_xfs_err"|sed 's/\r//g'));
                                                    unset tel_node_xfs_err;
                                                 done;
              fi; unset xfs_count;
              echo;
clean_up 'tel_ioerr_nodes tel_ioerr xfs_check tel_alarm tel_xfs_errs tel_disk_xfs_err tel_xfs_err api_alarm' 'unset';
}

###########################  Take info from storage vms on HV via Telnet   ##############################
function telnet_connect_fun() {
# function get and calculate info from storage vms . running on CP.
 [[ $FLAGS =~ 'ontelnet' ]] && SSH_TEL_FLAG=telnet;
  if  [ "$SSH_TEL_FLAG" == 'ssh' ] ; then \
    allinf_stvm_ssh=$(ssh $ssh_opt root@$hv "$(typeset -f take_stvm_info_ssh library_ssh_color_funs clean_up take_info_inside_stvm calculate_stvm_info);take_stvm_info_ssh $stvm \"$ssh_opt\" $Hid $ISD $hv \"$DBHV\" ") ; #all data from stvms
    clean_up 'stvm_ssh_output stvm_ssh_reports' 'add B|E' 'allinf_stvm_ssh' 'empties'                                                                      ### update values with report and print data.
    clean_up 'telinfo_df_report group_report dropbear_alarm isd_report locks_file_alarm tel_ioerr_report xfs_alarm nodes_statistic nodes_table api_report' 'add B|E' 'stvm_ssh_reports' # updare argumets with data in stvm_ssh_reports. if argumens hasn't data - unset. also mode empties.
    echo -e "$stvm_ssh_output";    # print info(state) of stvms (should works with collors)
    clean_up 'stvm_ssh_output stvm_ssh_reports' 'unset';                                                                                                     # unset data from curent stvm
    stvmss=$(echo "$allinf_stvm_ssh"|grep STVMSS| sed 's/STVMSS//g'|grep '[0-9]\+'|grep -v '^$');
    unset t1 telinfo_node tel_alarm xfs_count telinfo_node_stat ;
                                      else stvmss=$(bash -c "echo {1..$stvm}");
  fi;
 [ -n "$stvmss" ] && for T in `echo "$stvmss"|sed 's/ /\n/g'`;                                                                                                                    # start cycle for each storage vm
      do  t1=$(ssh  $ssh_opt root@$hv "echo| telnet 10.200.$Hid.$T 2>&1|grep 'conn\|ted'") ;                                                                                      # test telnet attempt
       if t2=$(echo "$t1" |grep Connected) ;
          then telinfo_proc=$(ssh $ssh_opt root@$hv "(echo 'ps w; \
           [ -e /tmp/freeinuselock ] && [ \$(expr \$(date +%s) - \$(stat -c%Y /tmp/freeinuselock)) -ge 180 ] && echo LOCK-PG freeinuselock;\
           [ -e /tmp/pinglock ] && [ \$(expr \$(date +%s) - \$(stat -c%Y /tmp/pinglock)) -ge 180 ] && echo LOCK-PG pinglock' ;\
                     sleep '0.2')|telnet 10.200.$Hid.$T" 2>&1 |grep -E 'group|redis|API|LOCK-PG|LOCK-DISK-TXN|isd |dropbear '|grep -v 'ps w'|sed 's/\r//');                      # take list of processes and locks files

               tel_ioerr=$(ssh $ssh_opt root@$hv "(echo 'ls /DB/NODE*'; sleep '0.1')|telnet 10.200.$Hid.$T" 2>&1 |sed 's/\r//' |grep 'ls:'|grep 'Input/output error';)           # I/O errors on Node. Cant read Node by 'ls'
               telinfo_node=$(ssh $ssh_opt root@$hv "(echo 'onappstore nodes'; sleep $t)|telnet 10.200.$Hid.$T" 2>&1 |grep -v 'Connection'  |sed 's/\r//');                      # take status of nodes
  if [ -z "$(echo $telinfo_node |grep 'status:')" ]  ;
     then telinfo_node=$(ssh $ssh_opt root@$hv "(echo 'onappstore nodes'; sleep $(($t+2)))|telnet 10.200.$Hid.$T" 2>&1 |grep -v 'Connection' |sed 's/\r//');     # take status of nodes(repeat)
          hv_stats=$(ssh $ssh_opt root@$hv "ps aux|grep telnet");
          hv_hanged_process=$(echo $(echo "$hv_stats"|grep [t]elnet| grep -v 'grep telnet'|grep bash)$(echo "$hv_stats"|grep ' telnet 10.200.'|sed 's/\([0-9]\{0,4\}:[0-9]\{2\} telnet\)/\n\1/g'|grep tel|sed 's/ /\n/g'|grep ':'|sed 's/:[0-9]\{2\}//g'|grep -E '[0-9]{3,}'));
      if [ -n "$hv_hanged_process" ] ; then  tel_alarm='RED' ; RED 'Remained Hanged telnet process!' ;
           hv_hanged_process_report=$(echo -e "$hv_hanged_process_report""\n"'Hanged telnet transaction(s) on HV:'\($hv\)); fi;
  fi;
               telinfo_node=$(echo $(echo "$telinfo_node" |grep -E 'status' -C 1) | sed 's/Node: //g;s/status:/ status:/g;s/IP addr://g;s/\(10\.200\.[0-9]\+\.[0-9]\+\)/\1\n/g';) # prepare nodes table
               tel_xfs_err_all=$(ssh $ssh_opt root@$hv "(echo 'dmesg|grep XFS|grep error'; sleep '0.2')|telnet 10.200.$Hid.$T" 2>&1 |grep -i error|grep -v grep|sort -u|sed 's/\r//'); # xfs errors from dmesg
               telinfo_df_all=$(ssh $ssh_opt root@$hv "(echo 'df -h'; sleep '0.1')|telnet 10.200.$Hid.$T" 2>&1 |grep vd|sed 's/\r//')                                            # take: df -h

               calculate_stvm_info "telnet";                                                                                                                  # running calculate output for each stvm.
          else RED "$t1"|grep 'No route to host\|Connection refused'; [ "$?" != 0 ] && echo "$t1";
               NoConnectStVm_alarm=1; NoConnectStVm=$(echo -e "$NoConnectStVm""\n"'HV:('$hv')' $t1);
       fi ; unset tel_alarm tel_disk_xfs_err;
      done ;
unset t1 telinfo_node tel_alarm xfs_count stvmss ;
}

################################################################################################################################################################
function take_hv_info_net_fun() {
  # function get info about all interfaces in onappstore bridge and check ping of SAN network relates to this HV. running on HVs and collect data to TT arg. (by ssh from CP) (start fun-network_check_fun)
  # input:   pathes of multicast snooping ; ping range for this HV; hvs zone id; Hid='host id of HV'; DBHV='info of HV from DB'
  # output: (visible out of ssh) TT-check interface part ; net_allmtu-data of all mtu and interfaces ; ping_report-stores all issues with ping in SAN network; all_bond-data of all bond in cloud.
  # output:   check enables multicast snooping.
pth_multicast='/sys/devices/virtual/net/onappstoresan/bridge/multicast_snooping'
pth_multicast1='/sys/class/net/onappstoresan/bridge/multicast_snooping'
dbond='/proc/net/bonding/';
hv="$1" ; ping_host_range="$2" ;hv_zone_id="$3" ; Hid="$4"; DBHV="$5" ; hv_backup="$6" ;DEEPLY="$7" ;
  i1=$(brctl showstp onappstoresan |grep -v '^ \|^$'|awk '{print $1}');                                                          # take list of interfaces in san bridge

  if [ -n "$i1" ] ;
      then   printf '%8b\t' '-MTU from DB:' MTU:$(echo "$DBHV" | cut  -f 3) "\t"; echo $(uptime |grep -o -P '(?<=up).*(?=, +[0-9]+ user)'|sed  's/, \+[0-9]\+:[0-9]\+//g; s/^/Uptime:/g') ;
           nbond=$(echo "$i1"|grep bond);                                                                                        # take name of bond which added to bridge
             pbond=$(echo $dbond$nbond|sed  's/\.[0-9]\+$//g');                                                                # add path of bond to pbond
             [ -f "$pbond" ] && \
                 bond_mode=$(cat $pbond|grep 'Bonding Mode') && \
                       bond_nics=$(echo $(cat $pbond |grep Interface|awk '{print $3}')) && \
             i2=$(cat $pbond |grep eth|grep -v 'Currently Active Slave:'|awk '{print $3}');                                      # take list of interfaces in bond if exist
             i="$i1 $i2";                                                                                                        # add to check list of interface all slave interface of bond
             [ -f "$pbond" ]  && \
                          echo $nbond -- "$bond_mode" NICs:\("$bond_nics"\);                                                     # print info of bond

             echo "$i1" | grep bond  1>/dev/null  && \
                all_bond=$(echo -e $hv"\t"zone_id=$hv_zone_id"\t"$bond_mode);                                                    # -$all_bond for report

             centos_ver=$(cat /etc/redhat-release | awk '{ print$4 }' | cut -b 1)
             for b in `echo "$i"`;
                  do net_ifcon=$(ifconfig $b)
                     if  [[ $centos_ver -eq 6 ]]
                         then net_mtu=$(echo "$net_ifcon" |grep MTU|sed 's/ /\n/g'|grep MTU);
                              [ "$b" == onappstoresan ] && net_mtu_san=$(echo $net_mtu|cut -d ':' -f 2);
                         else net_mtu=$(echo "$net_ifcon" |grep mtu|sed 's/ /\n/g'|grep mtu -A1 | sed -n 2p);
                              [ "$b" == onappstoresan ] && net_mtu_san=$(echo $net_mtu);
                     fi
                     net_errors=$(echo "$net_ifcon" |grep error|grep -v 'errors:0 dropped:0 overruns:0'|sed 's/ packets/_packets/g; s/ /\n/g'|grep -vE ':0|fr');            #
                     net_nolink=$(ethtool  $(echo $b|sed 's/\.[0-9]\+$//g')|grep 'detected: no');
                     printf '%-8b\t' $b  $net_mtu $net_errors;
                     echo "$net_nolink";
                     [ "$hv_zone_id" == NULL -a "$hv_backup" == 1 ] && hv_zone_id=BS;
                     net_allmtu=$(printf '%-8b\t' "$net_allmtu""\n"$hv hv_zone=$hv_zone_id $b $net_mtu $(echo $net_nolink|sed 's/ /_/g'));  # variable of all NICs with mtu info
             done ;

  ############# ping part
      if [ "$DEEPLY" = 0 ] ; then key='-c 1 -w 1.5'; issue="Failed to pass 1 packet for 1.5 second to" ; else key='-i 0.001 -c 1000 -w 5 -q ' ; issue='Issues with ping'; fi ;    # if enabled deeply mode - check ping of 1000 packets
         [ "$hv_zone_id" == BS ] && hv_zone_id=NULL;

         echo -n 'Try to ping range 10.200.{'$(echo $ping_host_range|sed 's/ /,/g')'}.254: ';
         for r_ping in  `echo "$ping_host_range"`;
             do  ping -I onappstoresan -s $((net_mtu_san - 28)) -M do 10.200.$r_ping.254 $key 1>/dev/null ;
                 if [ "$?" != 0 ] ;
                     then  net_err=1 ; echo;
                           echo -n "$issue" '10.200.'$r_ping'.254 with MTU:'$net_mtu_san;
                           ping_report=$(printf '%-10b\t' "$ping_report""\n"HV:\($hv\) 10.200.$Hid.254 'Cant ping' 10.200.$r_ping.254 'with MTU:'$net_mtu_san '|hv_zone_id='$hv_zone_id);
                 fi;
             done;
         [ "$net_err" != 1 ] && echo -n 'Can ping SAN network via onappstoresan with MTU:'$net_mtu_san. ;

############### check multicast snooping
         [ -f "$pth_multicast" ]   && [ "$(cat $pth_multicast)" ==  1 ]  && multicast_snoop_err=$(echo -e "$multicast_snoop_err""\n"$hv $pth_multicast = 1|grep -v '^$');
         [ -f "$pth_multicast1" ]  && [ "$(cat $pth_multicast1)" ==  1 ] && multicast_snoop_err=$(echo -e "$multicast_snoop_err""\n"$hv $pth_multicast1 = 1|grep -v '^$');

      else  echo 'Cant find out onappstoresan bridge! WARNING!';
  fi; echo;
######### output: values of all HVs. for checking mtu/bond confirmity ; report ping issues. and enabled multicast snooping
clean_up 'ping_report all_bond net_allmtu multicast_snoop_err' 'B|E' 'empties' ;

ip_addr=$(ifconfig mgt|grep Mask|awk {'print $2'}|sed 's/addr://')
mask=$(ifconfig mgt|grep Mask|awk {'print $4'}|sed 's/Mask://')
default_gw=$(ip r |grep default| sed 's/[[:alpha:]]//g')

#BOLD='\033[1m' ; RED='\033[0;31m' ; yellow='\033[0;33m' ; NORMAL='\033[0m' ;
#function RED    { echo -e ${RED}${BOLD}$@${NORMAL}; }

#####Calculation of mgt address###########
IFS=. read -r i1 i2 i3 i4 <<< "$ip_addr"
IFS=. read -r m1 m2 m3 m4 <<< "$mask"
res=$(printf "%d.%d.%d.%d\n" "$((i1 & m1))" "$((i2 & m2))" "$((i3 & m3))" "$((i4 & m4))")

#####Calculation of gateway address###########
IFS=. read -r g1 g2 g3 g4 <<< "$default_gw"
res1=$(printf "%d.%d.%d.%d\n" "$((g1 & m1))" "$((g2 & m2))" "$((g3 & m3))" "$((g4 & m4))")

if [ $res == $res1 ]

then

    echo "mgt IP and Gateway are in the same subnet"

else

    RED "mgt IP and Gateway are not in the same subnet"

fi

}


 function network_check_fun() {
hv_zone_id=$( echo "$DBHV" | cut  -f 4);
         if [ "$hv_zone_id" == NULL -a "$hv_backup" == 1 ] ;
             then    ping_host_range=$(echo "$dbhv" |grep -vP "\t$Hid\t[1-9][0-9]{3}\t" |awk '{print $2}') ;
             else    ping_host_range=$(echo "$dbhv" |grep -P "\t[1-9][0-9]{3}\t$hv_zone_id\t|\t1$" |grep -vP "\t$Hid\t[1-9][0-9]{3}\t" |awk '{print $2}' );
         fi ;                                                                                                                                 # if backup - all range
 # function prepares ip-range for take_hv_info_net_fun and gets info from there, then to process values and print info. Function works only if flag=network or flag=all
TT=$(ssh $ssh_opt root@$hv "$(typeset -f take_hv_info_net_fun clean_up); take_hv_info_net_fun $hv \"$ping_host_range\" $hv_zone_id $Hid \"$DBHV\" $hv_backup $DEEPLY" ) ; # get data of take_hv_info_net_fun
clean_up 'ping_report all_bond net_allmtu multicast_snoop_err' 'add B|E' 'TT' ;                                                               # update reports arguments with info from $TT(data of net fun)

[ -n "$(echo $TT|grep 'Cant find out onappstoresan bridge!')" ] && hv_alarm1="$hv_alarm1
$(echo 'bridge onappstoresan doesn not exist on HV:('$hv')!')";

TT=$(echo "$TT" |sed '/all_bondB/,/all_bondE/{d}; /ping_reportB/,/ping_reportE/{d}; /net_allmtuB/,/net_allmtuE/{d}; /multicast_snoop_errB/,/multicast_snoop_errE/{d}'); # remove data B|E (report data) from TT

# print out output from take_hv_info_net_fun with color
for string in `bash -c "echo {1..$(echo "$TT"|wc -l)}"`;
    do  printTT="$(echo "$TT"|sed -n {"$string"p})" ;
      if   [ -n "$(echo $printTT|grep 'Link detected')" ];  then echo -n "$(echo "$printTT" |grep -o -P '(?<=^).*(?=Link)')" ;  RED 'Link detected: no' ;
      elif [ -n "$(echo $printTT|grep 'Cant')" ];       then RED "$printTT" ;
      elif [ -n "$(echo $printTT|grep 'Issues with\|Failed to')" ];       then TT_temp_ping="$TT_temp_ping
$printTT" ;
      elif [ -n "$(echo $printTT|grep 'Try to ping ')" ]; then echo "$printTT" |grep -v '.{}.'|sed 's/{\([0-9]\{1,3\}\)}/\1/g' ;
      else echo "$printTT" ;  fi ;
done;
if [ "$DEEPLY" = 0 ] ; then issue="Failed to pass 1 packet for 1.5 second to" ; else  issue='Issues with ping'; fi ;
  clean_up 'TT_temp_ping' 'empties';
[ -n "$TT_temp_ping" ] && red "$issue" "$(ip_sort_fun "$(echo "$TT_temp_ping"|grep -o '10.200.[0-9]\+.254')" '3')" 'with' "$(echo "$TT_temp_ping"|grep -o 'MTU:[0-9]\+'|uniq)" ; # print ping issues
unset TT_temp_ping;
# echo 'ping report:'; echo "$ping_report"; echo 'All bond:' ; echo "$all_bond" ;  echo 'All mtu:' ; echo "$net_allmtu" ; echo multicast: ; echo "$multicast_snoop_err";  # -- checking
}

function disk_get_info() {
  # fun of calculating/getting info and printing. Runing on CP
  # NODES_TABLE arg and all_info_of_vdisks should be availeble.
  # inptut: 1 = 'identifier of vdisk'; 2 = 'full table of hvs' ; 3 = 'diskinfo' ; 4 = 'cached=true' ;
if [ -n "$3" ] ;  then vdisk_info="$3" ;
   [ "$4" == 'cached=true' ] && cached=" cached=true";
                  else red 'Something went wrong';
fi ;

vdisk_resynchstatus="$(echo "$all_info_of_vdisks"|grep ' resynchstatus '|grep -- "$1"| awk '{$1="";$2="";print}')";



 if [ -n "$(echo $vdisk_info|grep -i 'FAILURE\|error\|failed')" ] ;
    then  red " FAILURE!" ; echo "$vdisk_info"; echo --;
    else  vdisk_membership_info="$(echo "$vdisk_info"| sed 's/ /\n/g' |  grep 'members[h=]'|grep -v info|sed 's/=/ /g;s/,/ /g')"
          vdisk_memberinfo=$(echo "$vdisk_info"| sed 's/ /\n/g' |grep 'member' |sed -e "s|\(u'[0-9]\+'\)|\n\1|g"|grep -v memberinfo|
                    sed "s/\(u'\|'\)//g;s/,/ /g;s/\(nodestatus:[0-9]\|snap_limit:[0-9]\+\|membership_gen_count:[0-9]\+\|frontend:\|port:[0-9]\+\)//g;s/:{/ /g;s/}//g;s/=/ /g;;s/[ ]\+/ /g"|
                    grep -v members|grep -v '[0-9]\+:[0-9]'| sed 's/\(\[10\.200.\+\) \(10\.200.\+\]\)/\1,\2/g' |awk '{print $1, $2, $6, $3, $5, $4 }' |sort -k 4);         # example: 4291780412 status:1  [10.200.3.254]  st_mem:0  seqno:2092032

       # --> here needs to add checking if dmcache enabled using vdisk_memberinfo

       vdisk_nodes=$(echo "$NODES_TABLE" | grep -e  $(echo "$vdisk_membership_info" |grep 'membership' |sed 's/membership //g;s/ / -e /g') );  # table of vdisks's nodes (cuted from NODES_TABLE)

      for node_ip in `echo "$vdisk_nodes"|awk '{print $3}'|sort -u`; do \
          staff=$(ssh $ssh_opt root@$node_ip "ls /DB/NODE-*/$1*" 2>/dev/null|sed "s/\//\n/g;s/NO/\nNO/g;s/\($1\)/\n\1/g"|grep -e NODE -e "$1") # take staff-file
          vdisk_staff="${vdisk_staff}
          $(echo "$staff"|grep -v 'NODE-'|uniq)" ;

          [ -n "$(echo "$staff"|grep 'NODE-')" ] && nodes_staff="$(echo "$staff"|grep 'NODE-'|sed 's/NODE-'//g) $nodes_staff";
          unset staff;
      done ;


          vdisk_status=$(echo "$vdisk_info"|sed 's/ /\n/g'|grep '^status=[0-9]'|sed 's/status=0/OFFLINE/g;s/status=1/ONLINE/g');                  # status of vdisk (online/offline)
          vdisk_snapshots=$(echo "$vdisk_info"|sed 's/ /\n/g'|grep '^snapshots='|sed 's/snapshots=//g;s/,/ /g');                                  # snapshots of target vdisk
          vdisk_snap_stat=$(echo "$vdisk_info"|sed 's/ /\n/g'|grep '^snapshot='|grep -o [1-9]|sed 's/1/snapshot/g');
          vdisk_hostids=$(echo "$vdisk_info"|sed 's/ /\n/g'|grep '^hostids=[0-9]'|sed 's/hostids=//g');                                           # host id of hypervisor where vdisk is onlined
          vdisk_parent=$(echo "$vdisk_info"|sed 's/ /\n/g'|grep '^parent='|sed 's/^parent=//g');
          vdisk_insyncstatus=$(echo "$vdisk_info"|sed 's/ /\n/g'|grep '^insyncstatus='|sed 's/^insyncstatus=//g; s/1/healthy/g;s/0/degraded/g'|sed 's/\([2-9]\)/insynchstatus=\1/g');  # insyncstatus of vdisk from diskinfo
          if [ -n "$(echo "$vdisk_resynchstatus"|grep vdiskstate=Degraded|grep 'status={[^}]')" ] ; then vdisk_repair_status=1; else vdisk_repair_status=0; fi;   # 1 means the vdisk is repairing now
          clean_up 'vdisk_status vdisk_snapshots vdisk_snap_stat vdisk_hostids vdisk_parent vdisk_insyncstatus'  'empties' ;
          [ -n "$(echo $vdisk_hostids|grep ',')" ] && vdisk_hostids=$(echo "{$vdisk_hostids}");
          [ -n "$vdisk_snapshots" ] && vdisk_snapshots=$(echo "snapshots:{$vdisk_snapshots}")

          target_hv_host_id=$(echo "$vdisk_memberinfo"|awk '{print $3}'|grep '.254'|sort -u|sed 's/10.200.//g;s/.254//g;'|tr -d '[]')                         # host_id of HV where vdisk is onlined
          vdisk_target_hv=$(echo "$2"|sed 's/ /-/g;s/\t/=/g'|grep -- ".[0-9]\{1,3\}=$target_hv_host_id=[0-9]\{4,\}="|sed 's/=/ /g'|awk '{print $1}' );          # grep HV by host_id
          if [ "$vdisk_status" = 'ONLINE' ] ;      then echo -n " $vdisk_status on HV:["$vdisk_target_hv"]";          else echo -n " $vdisk_status" ;fi;        # print vdisk status
          if [ "$vdisk_snap_stat" = 'snapshot' ] ; then echo -n " parent={" ; yellow "$vdisk_parent" ; echo -n "} " ; else  echo -n ' '${vdisk_snap_stat}$vdisk_snapshots' ' ; fi;  # print parent or snapshotes
          echo -n $vdisk_insyncstatus[$vdisk_repair_status];                                                                                                                      # print vdisk insyncstatus 1=helathy ; 0=degraded
          if [ -n "$(echo "$vdisk_resynchstatus"|grep 'result=SUCCESS')" ] ; then \
             [ -n "$(echo "$vdisk_resynchstatus"|grep 'result=SUCCESS'|grep '[0-9]\{6,\}')" ] && \
                      echo "$vdisk_resynchstatus"| sed "s/'//g"|sed 's/\(, status[:=]\)/\n\1/g;s/\(vdiskstate\|replication\)[:=]/\n/g'|grep -v drstatus=|grep status[:=]|
             sed 's/status[:=]//g'|tr -d '{}'| sed 's/:u/>>/g';
           else yellow ' Cant take resynchstatus!'; fi ;                           # print resynchstatus

          red "$cached"; echo;

          for node in `echo "$vdisk_memberinfo"|awk '{print $1}'`; do \
          state=$(echo "$NODES_TABLE"|grep -- "$node"| awk '{print $2}')
          node_ip_addr=$(echo "$NODES_TABLE"|grep -- "$node"| awk '{print $3}'|sort -u)
          rspamd_pids="$(echo $(ssh $ssh_opt root@$node_ip_addr ps w|grep -- "$node"|grep -- "$vdisk"|awk '{print $1}')|sed 's/ /,/g')";
          vdisk_socket=$(ssh $ssh_opt root@$node_ip_addr "ls /var/run/vdiskctrl/$node/control_$vdisk 2>/dev/null") ;                                   # socket. should be warning if pids exist but no socket file
          vdisk_storage=$(ssh $ssh_opt root@$node_ip_addr "ls /DB/NODE-$node/storage/$vdisk/storage 2>/dev/null") ;                                    # check storage file
          vdisk_xml_data=$(ssh $ssh_opt root@$node_ip_addr cat /DB/NODE-$node/vdisks/$vdisk.xml 2>/dev/null);                                          # check vdisk xml file and save data.
          vdisk_xml_syncstatus=$(echo $vdisk_xml_data|sed 's/>/>\n/g; s/</\n</g'| sed -n '/<syncstatus>/,/<\/syncstatus>/p'|sed '1d;$d'|grep -o '[0-9]\+')
          echo -n "$node"'-'$node_ip_addr;                                                                                                              # print node|ip_of|node and another info
          echo -n ' '"$(echo "$vdisk_memberinfo"|grep -- "$node"|awk '{$1="";print}')";

      if ssh $ssh_opt -q root@$node_ip_addr exit  ; then \
          if [ -n "$(echo $rspamd_pids|grep [0-9])" ] ; then echo -n " ($rspamd_pids)" ; else echo -n ' (no_rspamd)';  fi;                            # print rspamd pids processes which running on taget stvm
          if [ -n "$vdisk_socket" -o -n "$vdisk_storage" -o -n "$vdisk_xml_data" ] ; then \
            echo -n ' files:('
            [ -n  "$vdisk_socket" ] && echo -n 'socket,';
            [ -n "$vdisk_storage" ] && echo -n 'storage,';
            [ -n "$vdisk_xml_data" ] && echo -n "xml[$vdisk_xml_syncstatus]";
            echo -n ')' ; else yellow ' no_files' ; fi |sed 's/,)/)/g' ;
      else redn ' no_connect_to_controller' ; fi;

          [ "$state" != 'ACTIVE' ]  && yellow " $state" ;
          [ -z  "$vdisk_socket" -a  -n "$(echo $rspamd_pids|grep [0-9])" ] && redn " no_socket!"
          echo;
          unset state node_ip_addr rspamd_pids vdisk_storage vdisk_socket vdisk_xml_data vdisk_xml_syncstatus;
          done|sed 's/[ ]\+/\t/g; s/\(^[0-9]\{9\}\)-/\1 -/g; s/\(^[0-9]\{7\}\)-/\1   -/g; s/\(^[0-9]\{8\}\)-/\1  -/g ; s/-/|/g;s/\(status:[0-9]\)\t/\1   /g; s/\(\.[0-9]\.[0-9]]\)\t/\1\t\t/g ; s/\(seqno:0\)/\1\t/g; s/\(seqno:[0-9]\+[ ]\)/\1\t/g; s/L\t/L /g' # `readble printing` status of nodes

          echo;

          if [ -n "$(echo "$vdisk_staff"|grep -- "$1")" ] ; then \
          echo -n 'Staff: ' $(echo "$vdisk_staff"|grep -v NODE |sort -u | grep -- "$1" |uniq);                           # print staff
          echo -n ';  on nodes:{' ; echo -n $nodes_staff|sed 's/[ ]\+$//g; s/ /,/g'; echo '}' ; unset nodes_staff;
                                                            else echo errors:;echo; vdisk_alarm=1;
          red 'Cant find out staff file!'; fi;

    excessive_members=$(diff -r <(echo "$vdisk_membership_info"|grep 'members '| sed 's/ /\n/g;s/[a-z]\+//g'|sort) <(echo "$vdisk_membership_info"|grep 'membership'| sed 's/ /\n/g;s/[a-z]\+//g'|sort));
    if [ -n "$(echo "$excessive_members"|grep '<\|>')" ] ; then \
      if [ -n "$(echo "$excessive_members"|grep '<')" ] ; then [ "$vdisk_alarm" != 1 ] && echo errors: && vdisk_alarm=1;
          redn "Excessive members:"    ;
       for node_bad in $(echo "$excessive_members" |grep '<'|sed 's/<//g'|sort -u) ;
           do  echo " $node_bad[$(echo "$NODES_TABLE"|grep -- "$node_bad"| awk '{print $3}'|sort -u )]"|sed 's/\[\]/\[no info\]/g' ; done; fi;
      if [ -n "$(echo "$excessive_members"|grep '>')" ] ; then [ "$vdisk_alarm" != 1 ] && echo errors: && vdisk_alarm=1;
          redn "Excessive membership:" ;
       for node_bad in $(echo "$excessive_members" |grep '>'|sed 's/>//g'|sort -u) ;
           do  echo " $node_bad[$(echo "$NODES_TABLE"|grep -- "$node_bad"| awk '{print $3}'|sort -u )]"|sed 's/\[\]/\[no info\]/g'; done; fi;

          echo "$vdisk_membership_info" | sed 's/ /\t/;s/s\t/s\t\t/g' # `readble printing` members
    fi;
  fi; clean_up 'vdisk_insyncstatus vdisk_membership_info vdisk_info vdisk_memberinfo vdisk_status vdisk_snapshots vdisk_snap_stat vdisk_hostids vdisk_parent cached target_hv_host_id vdisk_nodes vdisk_staff vdisk_alarm vdisk_resynchstatus' 'unset';
}

function get_all_vdisks_info_fun() {
# input 1=$VDISKS 2='cached=true'
echo '$1' = $1
echo '$2' = $2
if [ "$2" == 'cached=true' ] ;
   then for vdisk in `echo "$1"|sed 's/ /\n/g'`;
             do  onappstore diskinfo uuid="$vdisk"  cached=true |sed "s/^/$vdisk diskinfo /g" &
          done; wait;
   else  for vdisk in `echo "$1"|sed 's/ /\n/g'`;
             do  onappstore diskinfo uuid="$vdisk"|sed "s/^/$vdisk diskinfo /g" &
                 onappstore resynchstatus uuid="$vdisk" |sed "s/^/$vdisk resynchstatus /g" &
          done; wait;
fi;

}

function disks_check_get_info_fun() {
# function is running on HV ; gets info of vdisks(by disk_get_info) and transmit data to disks_check_fun for calculating and printing;
# fun availeble: get_all_vdisks_info_fun; disk_get_info; clean_up; library_ssh_color_funs
# input 1=$VDISKS 2=$ISD 3=$SSH_TEL_FLAG ; 4='list of all hvs'; 5='ssh options'
library_ssh_color_funs;
ssh_opt="$5";

NODES_TABLE="$(echo $(onappstore nodes|grep -v 'Role:')| sed 's/Node:/\n/g; s/\(status:\|IP addr:\)/ /g; s/[ ]\+ / /g;s/^[^0-9]//g')" ;   # example: 2926747366 DELAYED_PING 10.200.7.1 (global var)

all_info_of_vdisks=$(get_all_vdisks_info_fun "$1" 'cached=false') ;                                                              # info of all vdisks (diskinfo;resynchstatus etc) (large value of data)

[ -n "$all_info_of_vdisks" ] && \
  for vdisk in `echo "$all_info_of_vdisks"|grep ' diskinfo '|grep 'utilization\|size_MB'| grep -v 'result=FAILURE' |awk '{print $1}'|sort -u`;
    do vdisk_info=$(echo "$all_info_of_vdisks" |grep ' diskinfo '|grep -- $vdisk| awk '{$1="";$2="";print}') ;
       if [ "$(echo "$vdisk_info"|sed 's/ /\n/g'|grep '^snapshot='|grep -o [1-9]|sed 's/1/snapshot/g')" == 'snapshot' ] ; then echo -n "--snapshot:" ; else echo -n "--vdisk:" ; fi;
       yellow " $vdisk";

       disk_get_info "$vdisk" "$4" "$vdisk_info" "cached=false" ;echo -----------------------------------------------------; echo ' ';
     done;

    list_of_bad_vdisks=$(echo "$all_info_of_vdisks" |grep ' diskinfo '| grep 'result=FAILURE'|awk '{print $1}'|sort -u);                     # get list of bad vdisks
    all_info_of_bad_vdisks=$(get_all_vdisks_info_fun "$list_of_bad_vdisks" 'cached=true');  #  info of all bad vdisks which returned failure of diskinfo task (diskinfo;resynchstatus etc) (large value of data)

     for vdisk in `echo "$list_of_bad_vdisks"|sed 's/ /\n/g' `;
        do vdisk_info=$(echo "$all_info_of_bad_vdisks" |grep ' diskinfo '|grep -- $vdisk| awk '{$1="";$2="";print}' );
        if [ "$(echo "$vdisk_info"|sed 's/ /\n/g'|grep '^snapshot='|grep -o [1-9]|sed 's/1/snapshot/g')" == 'snapshot' ] ; then echo -n "--snapshot:" ; else echo -n "--vdisk:" ; fi;
        yellow " $vdisk";

        disk_get_info "$vdisk" "$4" "$vdisk_info" "cached=true" ;
        yellow "failed diskinfo 'cached=false':" ; echo "$all_info_of_vdisks"|grep 'diskinfo' | grep 'result=FAILURE' |grep -- "$vdisk" | awk '{$1="";$2="";print}' ;
                                                                echo -----------------------------------------------------;echo ' ';
     done;

      unset list_of_bad_vdisks all_info_of_vdisks all_info_of_bad_vdisks vdisk_info
}

function disks_check_main_fun() {
# function prepare list of VDISKS then transmit all output of disks_check_get_info_fun to DISKS_INFO var and print its.
# input 1=$VDISKS ; 2=count_of_vdisks
# output: calculated and readble data
DISKS_INFO=$(ssh $ssh_opt root@$hv "$(typeset -f disks_check_get_info_fun clean_up disk_get_info library_ssh_color_funs get_all_vdisks_info_fun) ;  disks_check_get_info_fun \"$1\" $ISD $SSH_TEL_FLAG \"$dbhv_all\" \"$ssh_opt\"" )
echo;
echo -e "$DISKS_INFO" ;
}

################################    Main function:                 ##################################
function check_is() {

## Network
  [ "$flag" = network -o "$flag" = all ] && \
           network_check_fun;                                                                                                    # run network fun

## IS state
  [ "$flag" = telnet -o "$flag" = all ] && t='1' && status_nodes_hv_fun                                                           # run status_nodes_hv_fun; t=sleep for telnet transactions

unset hv_stats hv_alarm hv_isd_procs ;
 ## vdisks checker
 if [ "$flag" = 'disks' ] ; then \
    if   [ -n "$(echo "$FLAGS"|grep 'all_disks')" ] ; then VDISKS=$(ssh $ssh_opt root@$hv  "onappstore list|grep Node|sed 's/Node \[//g;s/\]//g'");    # prepare vdisks list
         clean_up 'VDISKS' 'empties';
         if [ -z "$VDISKS" ] ; then yellow "ALART!" "there is no any vdisk in onappstore list";
            else echo -n "Will check " ; yellow "$(echo "$VDISKS"|wc -l) vdisk(s): "; echo  $VDISKS; fi;
    elif [ -n "$(echo "$FLAGS"|grep 'degraded_disks')" ] ; then  \
                                                                                                          # echo '-- test --' ;ssh $ssh_opt root@$hv getdegradedvdisks; echo '-- test --';
         VDISKS=$(ssh $ssh_opt root@$hv "getdegradedvdisks"|grep 'degraded_\|missing_'|grep -v 'degraded_snapshots'|sed 's/:/:\n/g'|grep -v ':'|sed 's/,/\n/g;s/ /\n/g'|
                                                                                        tr -d '()'|grep '\w\{8\}'|grep -v '^$'|sort -u);
         clean_up 'VDISKS' 'empties';
         if [ -z "$VDISKS" ] ; then yellow "Looks like all is fine. There is no degraded vdisks" ;
             else  echo -n "Will check " ; yellow "$(echo "$VDISKS"|wc -l) degraded vdisk(s): " ; echo  $VDISKS; fi;
    elif  [ -n "$(echo "$FLAGS"|grep 'vm_mode')" ] ; then VDISKS="$vm_mode_vdisks"; unset vm_mode_vdisks;

    fi;


    [ -n "$VDISKS" ]  && echo && disks_check_main_fun "$VDISKS";                                                                                 # start function which check vdisks list

 fi;

}

########################## BODY

for hv in `echo "$dbhv" | cut  -f 1`;
    do echo -e '\n';((C++));
       DBHV=$(echo "$dbhv" | sed -n {"$C"p});Hid=$(echo "$DBHV" | cut  -f 2);
       hv_backup=$(echo "$DBHV" | cut  -f 6);
       if [ "$hv_backup" == 1 ] ;  then hv_backup_i='BS' ; else hv_backup_i='' ;  fi;
       printf '%-8b\t' $(echo "$DBHV" | cut  -f 5|sed 's/ /_/g') $hv  host_id=$Hid  $(echo hv_zone_id=$(echo "$DBHV" | cut  -f 4) $hv_backup_i|sed 's/hv_zone_id=NULL BS/Backups_server/g'); echo;
       if  ssh $ssh_opt -q root@$hv exit    ;                                                                                                                                         # check ssh
            then tssh=$( { time -p ssh $ssh_opt -q root@$hv exit ; } 2>&1 | grep real| sed 's/\./ /g' | cut -d ' ' -f 2) ;                                                      # get time to log in
                 [ "$tssh" -ge 5 ] && yellow 'Large timeout for log in via ssh. ' "$tssh seconds!" && echo;
                 ssh_check=$(echo $(ssh $ssh_opt root@$hv ps aux|grep 'bash -c'|grep -e take_hv_info_ssh_fun -e calculate_stvm_info -e status_nodes_hv_fun -e take_stvm_info_ssh -e take_info_inside_stvm|awk '{print $2}'|sed 's/^[ ]\+$//g'))
                 [ -n "$ssh_check" ] && echo && red 'WARNING: Has been found  hanged ssh-sessions which the ISchecker left!' && echo "Please check the target server on hanging: NFS-server, 'onappstore nodes' command, 'onappstore nodelocalinfo' command, etc" && \
                 yellow  'NOTE: ISchecker.sh might be hanged!' && echo && echo && echo 'The hanged ssh processes:' && yellow $ssh_check && echo;   # checking  stale ssh sessions wich checker left.
                 check_is ;                                                                                                    ###### --->    RUN MAIN FUNCTION    <---  ####
            else red 'Cant log in via ssh';
                 ssh_report=$(printf '%-8b\t' "$ssh_report""\n"$hv hv_zone=$( echo "$DBHV" | cut  -f 4) host_id=$Hid);
       fi ;
    done ; C='';

[ -n "$dbhvoff" ] && \
    echo && yellow 'List of offline HVs:' && echo && \
    for hv in `echo "$dbhvoff" | cut  -f 1`;
    do ((C++));
    DBHVOFF=$(echo "$dbhvoff" | sed -n {"$C"p});Hid=$(echo "$DBHVOFF" | cut  -f 2);
    hv_backup=$(echo "$DBHVOFF" | cut  -f 6);
    if [ "$hv_backup" == 1 ] ;  then hv_backup_i='BS' ; else hv_backup_i='' ;  fi;
    printf '%b ' $(echo "$DBHVOFF" | cut  -f 5) "\t" ;printf '%-8b\t'  $hv  host_id=$Hid   $(echo hv_zone_id=$(echo "$DBHVOFF" | cut  -f 4) $hv_backup_i|sed 's/hv_zone_id=NULL BS/Backups_server/g'); echo;
    if  ssh $ssh_opt -q root@$hv exit   ;
       then yellow '--Can log in wia ssh to' $hv ; echo;
       else echo -n '--Cant log in via ssh to '$hv' |' ; ping $hv -c 1 -q 1>/dev/null ; if [ "$?" == 0 ] ; then yellow ' Can ping' $hv ; echo ; else echo ' Cant ping' $hv ; fi ;
    fi ;
    done ; C=''

################# check for report:

nodes_table=$(echo "$nodes_table"|sed 's/^[ -]\+//g'|grep -vE '^[ ]{0,}hv_zone=');
clean_up 'nodes_statistic nodes_table hv_hanged_process_report' 'empties';
# echo ----- ;echo "$nodes_table"; echo ----;
[ -n "$nodes_table" ] && nodes_state_report="$nodes_state_report$(echo)$(report_nodes_issues "$nodes_table" '2')" ;
[ -n "$nodes_statistic" ] && \
for node_zone in `echo "$nodes_statistic"|awk '{print $3}'|sort -u` ;
   do if [ "$(echo "$nodes_statistic"|grep -- $node_zone| awk '{print $2}'|sort -u|wc -l)" -gt '1' ] ;  then nodes_state_report="$nodes_state_report
$(report_nodes_issues "$nodes_statistic" '1')" ; break ; fi ; done;                                               # if different amount of active nodes in hv_zone -> report its in nodes_state_report
clean_up 'report_nodes_issues' 'empties';
is_ver_alarm=$(echo "$is_ver"|awk '{print $4}'|uniq|grep -vE "^$"|grep [a-z0-9]|wc -l)                                                                  # alarm =  IS ver mismatch all hvs
is_con_ver_alarm=$(echo "$is_con_ver"|awk '{print $4}'|uniq|grep -vE "^$"|grep [a-z0-9]|wc -l)                                                          # alarm =  IS ver mismatch all hvs

for bzone in `echo "$all_bond"|cut -f 2|sort -u` ;                                                                                                    # cycle for each HV zone - check bond mismatch
     do \
        all_bond_alarm=$(echo "$all_bond"|grep -P "$bzone"|cut -f 3|grep -vE '^$'|sed 's/ //g'|uniq|wc -l);
        [ "$all_bond_alarm" != 1 ] && bond_report_alarm=1 && \
                all_bondz=$(echo "$all_bond"|grep $bzone) && \
                bond_report=$(echo -e "$bond_report""\n"in $bzone"\n""$all_bondz"|grep -v '^$');
     done;

for nzone in `echo "$net_allmtu"|cut -f 2|sort -u` ;                                                                                                   # cycle for per all hvs zone(+BS)
     do net_mtu_alarm=$(echo "$net_allmtu"|grep -P "$nzone\t|=BS\t"|cut -f 4|uniq|wc -l);
        if [ "$net_mtu_alarm" != 1  ] ;                                                                                                                  # alarm of MTU mismatch
             then  mtu_report_alarm=1;
                   net_allmtu_z=$(echo "$net_allmtu"|grep -P "$nzone\t|=BS\t");
                   mtu_report=$(echo -e "$mtu_report""\n"in $nzone"\n""$net_allmtu_z");                                                                  # report list of mtu mismatch for each hvs zone
        fi;
done ;

[ "$ISD" = 0 ] && group_sort_fun "$tel_group_all"; group_sort_fun  "$(echo "$hv_group_all"|tr -d '*')" ;                                                 # alarm for groupmon settings in hv zone
 # echo tel; echo  "$tel_group_all" ; echo hv ; echo  "$(echo "$hv_group_all"|tr -d '*')" ;

################ report
# mtu_report_alarm=1;is_ver_alarm=2;bond_report_alarm=1;   is_con_ver_alarm=2;                                                                           # enabled report manually(test)
  [ -n "$hv_overlay_report" ] && echo && \
yellow "Find out overlays on HV(s):       " '<--' "$(echo "$list_by_George" |grep 'Overlay-feature')" && \
            echo && echo -n 'On HVs: ' && ip_sort_fun "$(echo $hv_overlay_report|sed 's/;/\n/g;s/ //g')" 4 && echo ;                                     # report overlays
clean_up 'nodes_state_report' 'empties';
for report_args in hv_alarm1 multicast_snoop_err ping_report isd_report telinfo_df_report tel_ioerr_report ssh_report api_report group_report free_devs_alart NoConnectStVm_alarm \
                   hv_hanged_process_report locks_file_alarm xfs_alarm  dropbear_alarm hv_cron_report diskhot_errors_report group_all_alarm nodes_state_report;
do [ -n "$(echo "${!report_args}"|grep -v '^$')" ] && report_alarm=1 ; done ;                                                                            # if exist data - report

for report_args in bond_report_alarm mtu_report_alarm onapp_store_ver_report ;
do [ "${!report_args}" = 1 ] && report_alarm=1   ; done ;                                                                                                # if data == 1 - report

  [ "$is_ver_alarm" -gt 1 -o "$is_con_ver_alarm" -gt 1 ]       && report_alarm=1 ;                                                                       # if data gt 1 - report

  if [ -z "$onapp_store_rpm" ] ; then echo ; yellow 'Note:' ; echo " ISchecker doesn't have enough info. No-info: package-version of current IS onapp-version" ; echo ;
   else [ -n "$is_ver" ] && [ "$(echo "$is_ver"|awk '{print $4}'|uniq|grep -vE "^$")" != "$onapp_store_rpm" ] && report_alarm=1 ; fi;                              # mismatch onapp ver bw hv with CP

  [ "$report_alarm" == 1 ] && echo && yellow '### ISchecker - report issues:' && echo && echo ;

  [ "$bond_report_alarm" == 1 ] && echo && red '**Bond mode discrepancy:**'  && echo "$bond_report"|grep -vE "^$" |sort -k 3 ;                             # bond mismatch per hvs zone id report
  [ -n "$ssh_report" ] && red '**Cant log in via ssh:**' && advance_print_fun  "$ssh_report" '2';                                                        # report when no ssh
  [ -n "$hv_hanged_process_report" ] && red '**Hanged telnet transactions(which running more then 100 sec) on HV(s):**'"\t\t"' <-- all hanged processes should be killed!' && \
  advance_print_fun "$(echo "$hv_hanged_process_report"|sort -u)" '2';
  [ "$mtu_report_alarm" == 1 ] && red '**MTU mismatch:**' && advance_print_fun "$(mtu_sort_fun "$mtu_report")" '2';                                       # Mtu mismatch report -- mtu_sort_fun "$mtu_report"

  [ "$onapp_store_ver_report" = 1 ] && red '**Mess in onapp-store packeges on CP**' && advance_print_fun "$onapp_store_ver" '2';

if [ "$is_ver_alarm" -gt 1 -a "$is_con_ver_alarm" -gt 1 ] ; then \
  [ "$is_ver_alarm" == 1 -a "$is_con_ver_alarm" == 1 ] &&   [ "$(echo "$is_ver"|awk '{print $4}'|uniq|grep -vE "^$")" != "$onapp_store_rpm" ] && red '**Mismatch onapp-store version:**' && \
    advance_print_fun "$(rpm_sort_fun "$is_ver" "CP_ALARM"|grep -vE "^$"|sort -k 4 -r)" '2' ;                                                            # between CP and all HVs which checking now.
    red "**found out mismatch IS versions in 'controllerversion|package-version'**";
            advance_print_fun "$(rpm_sort_fun "$is_con_ver"|grep -vE "^$"|sort -k 4 -r)" '2' ;
             else   if [ "$is_ver_alarm" -gt 1 ] ;                                                                                                       # Is ver mismatch all hvs report
       then red "**found out mismatch IS versions in 'cat /onappstore/package-version.txt'**   <-- package-version";
            advance_print_fun "$(rpm_sort_fun "$is_ver"|grep -vE "^$"|sort -k 4 -r)" '2' ;   fi;

  if [ "$is_con_ver_alarm" -gt 1 ] ;                                                                                                                     # Is ver mismatch all hvs report
       then red "**found out mismatch IS versions in 'cat /onappstore/controllerversion.txt'** <-- controllerversion";
            advance_print_fun "$(rpm_sort_fun "$is_con_ver"|grep -vE "^$"|sort -k 4 -r)" '2' ;   fi;
fi;

  [ -n "$(echo "$group_all_alarm"|grep -v '^$')" ] && red '**mismatch groupmon keys:**' && advance_print_fun "$(echo "$group_all_alarm"|sed 1d)" '2' ;
  [ -n "$NoConnectStVm_alarm" ] && red '**Can not connect to storage vm(s):**' && advance_print_fun "$(echo "$NoConnectStVm"|grep -v '^$')" '2';
  [ -n "$ping_report" ] && redn '**Ping Issues:**' && yellow "\t\t""$( if [ "$DEEPLY" = 1 ] ;                                                            # report ping issues
       then echo ' --Deeply mode! [ping by -c 1000 -i 0.001 -w 5]';
       else echo '<-- ping by 1 packet with deadline 1.5 sec. (for check more deeply will Use -D key)'; fi;)" && echo && echo && echo '```' && \
       for ping_i in `echo "$ping_report" |grep -v '^$' |sort|awk '{print $2}'|uniq` ;
         do printf '%-8b\t' $(echo "$ping_report"|grep -v '^$' |sort -u |grep -- ")[[:space:]]$ping_i"|awk '{print $1, $2}'|uniq) 'Cant ping' \
        $(ip_sort_fun "$(echo "$ping_report" |sort -u|grep  ")[[:space:]]$ping_i" | awk '{print $5}')" '3') "$(echo "$ping_report"|sort -u|grep -- ")[[:space:]]$ping_i"|awk '{print $6, $7, $8}'|uniq)" ; echo ;
       done  &&  echo && echo '```' ;                                                                                                                   # report ping issues

  [ -n "$locks_file_alarm" ] && redn '**Found out harmful lock(s) file(s)**' && yellow "\t\t <-- $(echo "$list_by_George" |grep -A 1 'reports locks')" && \
                                echo && advance_print_fun "$(echo "$locks_file_alarm"|grep -v '^$')" '2' ;                                              # locls files
  [ -n "$hv_alarm1" ]   && redb '**'"$(echo "$hv_alarm1"|sed 's/ Large/\nLarge/g'|grep -v '^$')"'**' && echo;                                           # report timeout is on hvs
  [ -n "$xfs_alarm" ] && red '**XFS issues:**' "\t\t" '<--' "${knowdb}42226897-Repair-XFS-filesystem-on-Storage-nodes" && advance_print_fun "$(echo "$xfs_alarm"| sed 's/XFS/\nXFS/g'|grep -v '^$')" '2';
  [ -n "$tel_ioerr_report" ] && red '**I/O errors:**' && advance_print_fun "$(echo "$tel_ioerr_report"|grep -v '^$')" '2' ;                                      # I/O reports
  [ -n "$multicast_snoop_err" ] && red '**Enabled multicast_snooping for SAN bridge**' && advance_print_fun "$(echo "$multicast_snoop_err"|grep -v '^$')" '2' ;  # report mulricast_snoop enable

  if [ -n "$api_report" ]  ; then  yellow '**storage API issues:**' ;  [ -n "$(echo "$api_report"|grep 'API-call')" ] && yellow "\t\t API-call failed means 'onappstore nodelocalinfo uuid=' return failure" ;
                                   echo "  <-- please restart storageAPI inside storage vm via telnet"; advance_print_fun "$api_report" '2';  fi;
  if [ "$ISD" = 0 ] ;
    then [ -n "$group_report" ] &&  yellow
     '**Incorrect amount of groupmon processes:**' "\t\t" '<--' "$(echo "$list_by_George" |grep 'Incorrect-amount')"  && echo && advance_print_fun "$group_report" '2';
    else [ -n "$isd_report" ]  &&  red '**No isd process(es):**'    && advance_print_fun "$isd_report" '2' ;
         [ -n "$hv_cron_report" ] && redn '**Cron issues:**'  && yellow  "$(echo -e "\t\t")"'<-- crond should running with correct values in crontab for IS(isd)' && echo && advance_print_fun "$hv_cron_report" '2';
         [ -n "$dropbear_alarm" ] &&  yellow '**No ssh-server(s):**' && echo && advance_print_fun "$dropbear_alarm" '2' ;
         [ -n "$group_report" ] &&  yellow '**Groupmon|redis processes on isd IS:**'  && echo && advance_print_fun "$group_report" '2' ;
         makespaceNode='"nodemakespace uuid=id" via CLI or';
  fi;
  if [ -n "$diskhot_errors_report" ] ;
    then  yellow '**Found out Diskhotplug issue(s) for HV(s):**'"\t"'<-- try to regenerate MetaData: '"${knowdb}"'87092266-diskhotplug-list-gives-no-output' ; echo; echo; echo '```';
           diskhot_nodata=$(echo "$diskhot_errors_report"|grep nodata|awk '{$1="";print}'|uniq) ;
           [ -n "$diskhot_nodata" ] &&  echo ' ' "$(ip_sort_fun "$(echo "$diskhot_errors_report"|grep nodata|awk 'NF=1'|tr -d 'HV:()' )" '4') $diskhot_nodata";
                      echo "$diskhot_errors_report" |grep -v '^$\|nodata'|sort ; echo; echo '```'; fi;

  [ -n "$telinfo_df_report" ] && yellow '**Found out Overflowed node(s)**:'"\t\t\t"'<-- Try' $makespaceNode 'cleaning up directory /DB/NODE-<ID>/stats/ inside stvm' && echo && \
                  advance_print_fun "$(echo "$telinfo_df_report"|grep -v '^$\|nodata'|sed -e 's|^ +|  |g')" '2' ;

  [ -n "$free_devs_alart" ] && yellow  '**Small amount of free nbd devices:**'       && echo && advance_print_fun "$free_devs_alart" '2';

if [ -n "$nodes_state_report" ] ; then yellow '**Nodes state issues:**' ; [ "$SSH_TEL_FLAG" = 'telnet' ] && yellow "\t"'(Please note:Can be found out wrong issues with no active nodes due telnet method)'
 echo ; advance_print_fun "$(echo "$nodes_state_report"|sed 's/\(\(NO ACTIVE\|Different\|Bad node\)\)/\n\1/g')" '2' ; fi;



######### end
unset bond_report_alarm is_ver_alarm mtu_report_alarm;
fi 2>&1|grep -v 'POSSIBLE BREAK-IN ATTEMPT\|Killed by signal 15.';