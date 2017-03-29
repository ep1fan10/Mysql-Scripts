#!/bin/bash

#Mysql auth user and pass from parameters, execute script as in: xtradb_backup.sh user password

user="$1"
password="$2"

#1 Define File Locations
lockFile="/var/lock/xtradb_backup";
backupLocation="/usr/src/backup";
timeStamp="$(date +%Y-%m-%d_%H-%M-%S)";
backupFolder="${backupLocation}/${timeStamp}";

#2 Check for a file existance in order to avoid backup running twice simultaneously
if ! lockfile-create --retry 0 ${lockFile}
then
    echoError "xtradb_backup is already running.";
    echoError "If you want to force run please remove ${lockFile}";
    exit 1;
fi

#3 Create backup directory if doesn't exist
mkdir -p $backupLocation;

#4 Create backup
innobackupex --user=$user --password=$password --no-timestamp $backupFolder;

#5 Modify backup config file to enable partial backups
echo "innodb_file_per_table=1" >> $backupFolder/backup-my.cnf;

#6 Prepare backup for immediate restoration
innobackupex --user=$user --password=$password --apply-log --export $backupFolder;

#7 Dump schema for each database
for database in $(ls -lA $backupFolder | grep '^d' | awk '{print $NF}')
do
    mysqldump -u$user -p$password --no-data --lock-tables=false $database > $backupFolder/$database/schema.sql;
done


#8 Clear Lock File
lockfile-remove ${lockFile};
