#!/bin/bash

#Settings
pass="$1"

#8. Function reset
reset () {
    #9. wait 5 seconds until re-try
    sleep 5

    #10. Reset the password through the new mysql_safe instance, password not needed but written "a" to connect directly
    /usr/bin/mysql -uroot -pa mysql --socket=/var/run/mysqld/mysqlr.sock -e "update user set Password=PASSWORD('$pass') where user='root';"
}

#5. Function check
check () {
    #6. check if the new mysql instance is already running just in case it takes some time/delay
    if /bin/ps aux | grep -v grep |grep "reset_root_password.cnf" > /dev/null
    then
        status="OK"
        #7. white until is possible connect (could take some time after the instance start to connect)
        while ! /usr/bin/mysql -uroot -pa  --socket=/var/run/mysqld/mysqlr.sock -e";"
        do
            #8. wait 5 seconds until re-try
            #sleep 5
            reset
            #9. Reset the password through the new mysql_safe instance, password not needed but written "a" to connect directly
            #/usr/bin/mysql -uroot -pa mysql --socket=/var/run/mysqld/mysqlr.sock -e "update user set Password=PASSWORD('$pass') where user='root';"
        done

        #11. Once reset the password, send a SIGHUP to the main mysql instance in order to fush privileges
        /bin/kill -HUP $perconapid

        #12. Kill the auxiliar mysql instance and its child process
        for i in `ps -ef| awk '$3 == '$auxpid' { print $2 }'`
        do
            /bin/kill -9 $i
        done
        /bin/kill -9 $auxpid
    fi
    #I do a fina check with the pass its been just setup
    #If connects it shows an OK
    #If does not connect it shows a KO message 
    if ! $mysql -uroot -p$pass -e 'use mysql'; then
        echo "KO: For some reason couldn't be possible to connect with the new password set"
    else
        echo "OK: Password succesfully changed"
    fi
}

#0. check if parameter $1 is set
if [ -z "$1" ]
then
    echo "mysql server password has been not passed as parameter, please when executing the script make sure you pass the password as in: /usr/sbin/mysql_reset_root_password.sh.sh password."
    exit
fi


start () {
    #1. Catch the present mysql running instance PID
    perconapid=`/usr/bin/pgrep -u mysql`

    #2. Start a new mysql instance skipping innodb and using a different socket, port, and pidfile refered at mycnf_reset_root_password.cnf
    /usr/bin/mysqld_safe --defaults-file=/etc/mysql/reset_root_password.cnf --skip-grant-tables --default-storage-engine=myisam &

    #3. Catch the new mysqld_safe instance PID
    auxpid=$!

    #4. Run the function check until status is OK
    while [[ $status != "OK" ]]
    do
        check
    done
}

#I the second parameter is not set, set as SKIP_PASSWORD_CONFIRMATION
if [[ -z "$2" && "$2" != "SKIP_PASSWORD_CONFIRMATION" ]]
then
    read -p "Are you sure that new password to be set is $1?  <y/N> " prompt
    if [[ $prompt == "y" || $prompt == "Y" || $prompt == "yes" || $prompt == "Yes" ]]
    then
        start   
    else
        echo "Exiting program because bad password to be set"
        exit 0
    fi
#If second parameter is set and set as SKIP_PASSWORD_CONFIRMATION, go ahead and reset
elif [ "$2" == "SKIP_PASSWORD_CONFIRMATION" ]
then
    start
fi
