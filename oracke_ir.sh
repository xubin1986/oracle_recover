#!/bin/bash
#developed by palmer
#target to recover oracle database.it is executed on oracle resotre host.will remote execute nba cmd via ssh channel.

usage(){
local script
script=`basename $0`
cat << EOF

ERROR! Usage:

    $script -reset
        reset nba password

    $script -list image -client <backup_client> -nba <IP>
        List the avaiable images.

    $script -create -id <ID> -nba <IP>
        create recover point for client
        
    $script -destroy -id <ID> -nba <IP>
        destroy recover point for client
        
    $script -restore -id <ID> -nba <IP>
        restore oracle database from the image you specified.
              
EOF

}  

getArg(){
#example: getArg "$args" add,delete [1,1],1 means the value could be empty
local j opt opts args opts_exp opts_data args_data isempty
unset ARGVS
args=$1
opts=$2
isempty=$3
isempty=(${isempty//,/ })
opts_exp="-`echo "$opts"|sed -r "s/,/ |-/g"` "
args_data=`echo "$args "|sed -r "s/$opts_exp/\n&/g"|grep -vP "^$"`
opts_data=`echo $opts|sed "s/,/ /g"`
j=0
for opt in $opts_data
do
    ! echo "$args_data"|grep -P "\-$opt$|\-$opt " > /dev/null 2>&1 && usage && exit 1
    ARGVS[$j]=`echo "$args_data"|grep -oP "(?<=-$opt$|-$opt ).*"|sed -r "s/\s+/ /g;s/^\s|\s$//g"`   
    [ -z "${ARGVS[$j]}" -a "${isempty[$j]}" != 1 ] && echo -e "\nValue of Option -$opt could not be empty!\n" && usage && exit 1
    j=$[$j+1] 
done
}

checkAuth(){
local host user
host=$1
user=$2
passwd=$3

expect << EOF > /dev/null 2>&1  
set timeout $TIMEOUT
spawn ssh $user@$host "hostname"
expect {
    "connect to host" {exit 2}
    "word" {exit 1}
    eof {exit 0}
    timeout {exit 2}
}
expect eof
EOF
return $?
}


rexec(){
local cmd file
cmd=$1
if [ -z "$nba_password" ]
then
    for i in {1..3}
    do
        read -p "please input password of NBA server: " -t $TIMEOUT -s tmp_pw
        [ $? -ne 0 ] && exit 1
        checkAuth $nba_server $nba_user $tmp_pw
        [ $? -eq 0 ] && nba_password="$tmp_pw" && echo "$tmp_pw" > ~/.nbapass  && break
    done
fi        

file=/tmp/rexec.tmp

expect << EOF > $file 2>&1
set timeout $TIMEOUT
spawn ssh $nba_user@$nba_server
expect {
    "(yes/no)?" { send "yes\r";exp_continue}
    "word" {send "$nba_password\r"}
    }
expect {
    -re "#|~" {send "echo \"$cmd\" > /tmp/cmd.$host \&\& bash /tmp/cmd.$host;echo rc=\$? \&\& rm -f /tmp/cmd.$host;\r"}
    "word" {puts "\nrc=1002";exit 1}
    timeout {puts "\nrc=1003";exit 1}
    }
expect -re "#|~"
send "exit\r"
expect eof
EOF

content=`cat $file`
rm -f $file
ret=`echo "$content"|grep -oP "(?<=rc=)[0-9]+"|tail -1`
content=`echo "$content"|grep -A 1000000 "/tmp/cmd.$host"|grep -B 1000000 -P "^rc=[0-9]+"|sed '1d;$d'`
if [ "$ret" = 0 ]
then
    echo "$content" > $tmplog
    disPlayLog 
elif [ "$ret" = 1002 ]
then
    log 1 "The password is wrong!" 
elif [ "$ret" = 1003 ]
then
    log 1 "The prompt shell is not supported!"
else
    :
fi
[ $ret -ne 0 ] && exit 1
}

log(){
local lv msg date
lv=$1
msg=$2
date=`date "+%Y-%m-%d %H:%M:%S"`
echo "$msg"|while read line
do
    [ $lv = 0 ] && echo -e "\n$date  $line" || echo "        $line"
done
}

disPlayLog(){
cat $tmplog|while read line
do
    log 1 "$line"
done
}


createPfile(){
log 0 "Create database pfile"
rm -f $NEWPFILE
SPFILETMP=$LOGDIR/spfile.tmp
strings $COPILOT_LOCATION/spfile* > $SPFILETMP

echo "*.pga_aggregate_target=$PGAMEMORY" >> $NEWPFILE
echo "*.sga_target=$SGAMEMORY" >> $NEWPFILE
echo "*.audit_file_dest='$DBFILES_LOCATION/adump'" >> $NEWPFILE
echo "*.control_files='${DBFILES_LOCATION}/control01.ctl','${DBFILES_LOCATION}/flash_recovery_area/control02.ctl'" >> $NEWPFILE
echo "*.log_archive_dest='$DBFILES_LOCATION/arch'" >> $NEWPFILE
echo "*.dispatchers='(PROTOCOL=TCP) (SERVICE=${ORACLESID}XDB)'" >> $NEWPFILE
echo "*.diagnostic_dest='$DBFILES_LOCATION/diag'" >> $NEWPFILE
echo "_disk_sector_size_override=TRUE" >> $NEWPFILE

grep "*.db_name" $SPFILETMP >> $NEWPFILE
grep "*.processes" $SPFILETMP >> $NEWPFILE
grep "*.sessions" $SPFILETMP >> $NEWPFILE
grep "*.db_files" $SPFILETMP >> $NEWPFILE
grep "*.max_string_size" $SPFILETMP >> $NEWPFILE
grep "*.audit_trail" $SPFILETMP >> $NEWPFILE
grep "*.compatible" $SPFILETMP >> $NEWPFILE
grep "*.db_block_size" $SPFILETMP >> $NEWPFILE
grep "*.nls_language" $SPFILETMP >> $NEWPFILE
grep "*.nls_territory" $SPFILETMP >> $NEWPFILE
grep "*.open_cursors" $SPFILETMP >> $NEWPFILE
grep "*.remote_login_passwordfile" $SPFILETMP >> $NEWPFILE
grep "$ORACLESID.undo_tablespace" $SPFILETMP >> $NEWPFILE
echo "db_unique_name=$ORACLESID" >> $NEWPFILE
log 0 "Create database pfile...Finished"
}

startNomount(){
log 0 "STEP1: Try to start oracle with nomount mode."
export ORACLE_SID=$ORACLESID
rman target / nocatalog << EOF > $tmplog
startup nomount pfile='$NEWPFILE';
exit;
EOF
disPlayLog
if cat $tmplog|grep -i error > /dev/null 2>&1
then
    log 0 "Staring oracle with nomount mode...Failed!"
    exit 1
else
    log 0 "Staring oracle with nomount mode...Finished!"
fi
}

recoverControlFile(){
log 0 "STEP2: Try to recover control file."
export ORACLE_SID=$ORACLESID
rman target / nocatalog << EOF > $tmplog
restore controlfile to '/recovery/control01.ctl' from '/recovery/cf_D-ORCL_I-1511384122_T-20180810_4sta5mlu_rhel-guest_copilot';
exit;
EOF
disPlayLog
if cat $tmplog|grep -i error > /dev/null 2>&1
then
    log 0 "Recover control file...Failed!"
    exit 1
else
    log 0 "Recover control file...Finished!"
fi
}

modifyRedoAndDataFile(){
local sqlfile
sqlfile=/tmp/sqlfile
#gen sql file
cat << EOF > $sqlfile
alter database mount;
set heading off feedback off pagesize 0 verify off echo off;
select member from v\$logfile;
EOF
sqlplus / as sysdba @$sqlfile > $tmplog
disPlayLog
if cat $tmplog | grep -i error > /dev/null
then
    log 0 "Failed to get original redolog"
    exit 1
fi

}




#main code
#parameter seetings 

[ -f ~/.nbapass  ] && nba_password=`cat ~/.nbapass`
nba_server=
nba_user=root
TIMEOUT=10
ORACLESID=nsid
CLIENTNAME=lxmstgrac1
SGAMEMORY=4g
PGAMEMORY=2g
ORACLEHOME=/u01/app/oracle/product/12.2.0.1/dbhome_1
ORAPASSWD=P@ssw0rd
COPILOT_LOCATION=/recovery
tmplog=/tmp/oracle_ir_log



args="$*"
[ -z "$1" ] && usage && exit 1
args=`echo "$args"|sed -r "s/$1\s+//"`
case $1 in
    -reset)
        rm -f ~/.nbapass
        ;;
    -list)
        getArg "$args" client,nba
        nba_server=${ARGVS[0]}
        client=${ARGVS[1]}
        rexec "nborair -list_images -client $client" 
        ;;
    -create)
        addTarget "$args"
        ;;
    -destroy)
        chgTarget "$args"
        ;;
    -resotre)
        delTarget "$args"
        ;;
    *)
        usage
        exit 1
esac




