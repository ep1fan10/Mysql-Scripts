#!/bin/bash

#1 Parse arguments
args="$@"
if ! invalidArgs=$(ParseArguments "backupPath dbs" "$args")
then
    echo "Invalid arguments:";
    echo " $(echo ${invalidArgs[@]} | sed 's/^/--/g ; s/\ /\ --/g')";
    echo "";
    exit 1;
fi

#2 Define MySQL Variables
user="$1";
password="$2";
mysqlWithPass="mysql -u$user -p$password";

#2 Define File Locations
path="$3"


#3 Function that restores requested database
function restore () {
    #Here I follow the process to restore databases backuped throug$h innobackupex,
    #the process documentation is in here: http://bit.ly/Ud4XAX but it takes extra steps to automate the process 
    $mysqlWithPass -e "CREATE DATABASE $1;"
    $mysqlWithPass $1 < $backupPath/$1/schema.sql
    $mysqlWithPass $1 -e "SHOW TABLES;" -ss > $path/$1
    while read line
    do
        $mysqlWithPass -e "SET foreign_key_checks = 0; ALTER TABLE $1.$line DISCARD TABLESPACE;"
        cp $backupPath/$1/$line.ibd /var/lib/mysql/$1/
        cp $backupPath/$1/$line.exp /var/lib/mysql/$1/
        chown mysql:mysql /var/lib/mysql/$1/$line.*
        chmod 660 /var/lib/mysql/$1/$line.*
        $mysqlWithPass -e "SET foreign_key_checks = 0; ALTER TABLE $1.$line IMPORT TABLESPACE;"
    done < $path/$1
    $mysqlWithPass -e "SET foreign_key_checks = 1;"
    echo "Restore process for DB $1 finished"
}

#2 Function that checks if the required database to be restored it does exists into the
#specifically indicated folder
function check () {
    status=0
    for database in $(ls -lA $backupPath | grep '^d' | awk '{print $NF}')
    do
        if [ "$1" == "$database" ]
        then
            status="OK"
            torestore=$database
        fi
    done
    if [ $status == 0 ]
    then
        status="KO"
    fi
}

IFS=',' read -ra DBS <<< "$dbs"

#1 For each database passed as parameter we start the process
for i in "${DBS[@]}"
do
    #Call check function passing as argument the database
    check $i

    #If status is OK it means the database exists
    #so I call the restore function for that database
    if [ $status == "OK" ]
    then
        echo "Will proceed to restore the database $i"
        restore $torestore
    #If status is KO it means the database does not exists
    #and print out a WARNING for that specific database
    elif [ $status == "KO" ]
    then
        echo "WARNING!: I'm afraid, the database $i you'r asking for restore does not exist into the local backup $backupPath"
    fi
    #remove temporary files
    if [ -f $path/$i ]
    then
        rm $path/$i
    fi
done
