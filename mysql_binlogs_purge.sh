#!/bin/bash
#./mysql_binlogs_purge.sh user password email
#NEEDS:
#1. report-host parameter must be set at the slaves my.cnf in order to pass slave hostname to master
#2. slaves must be accessible from master with same root password as in the master itself
commands="hostname mysql wc sed tail mail"

for i in $commands
do
    tmp=`which $i`
    eval $i="$tmp"
    command=`eval echo \$"${tmp}"`
    if [[ -z "$command" ]]
    then
        echo "command $i not found, existing script..."
        exit 0
    fi
done

#path where to place temporary files
path="/tmp"
EMAIL="$3"
EMAILMESSAGE="$path/purge_report"
hostname=`hostname`
user="$1";
password="$2";
          
#Mysql parts
chain0="mysql -u$user -p$password "
chain1="$chain0 $db -e"
chain2="$chain0 -h$i -bse"

#Check present mysql master bin log
$chain1 "show binary logs;" > $path/binarylog
blines=`wc -l < $path/binarylog`

#That function sets the master's slaves variables based on 
#show slave hosts's hostnames
slaves(){
    $chain1 "show slave hosts" -ss > $path/slave_hosts
    counter=0
    while read line
    do
        let "counter+=1"
	    line=$(echo $line |sed -n 's/^[0-9]* \(.*\) 3306.*/\1/p')
	    slaves=("${slaves[@]}" "$line")
    done <$path/slave_hosts 
    if [[ "$counter" < "1" ]]
    then
    	echo "It seems there's not any slave for that master. Nothing to rule. Exiting now..."
    	exit 0
    fi
}

#execute slaves function
slaves

counter=0
base0="Master_Log_File"
base1="mlf"
#per slave generate a file with its status
for i in "${slaves[@]}" 
do
    chain2="$chain0 -h$i -bse"
    $chain2 "show slave status\G" -ss > $path/reference$counter
    tmp0=`/bin/sed -n '7p' $path/reference$counter`
    tmp0="$tmp0"
    now0="$base0$counter"
    eval ${now0}=\$tmp0
    now1="$base1$counter"
    tmp1=${!now0:31}
    eval ${now1}=\$tmp1
    let counter+=1
done

#If the master binary log has more than one line, lets see if can be purged 
if [ $blines -gt 1 ]; then
    #Catch lastt Master Binary Log which is the present one
    LastLine=`tail -n1 $path/binarylog|awk '{print $1}'`
    #Count the number of present slaves
    slavesquant=${#slaves[@]}
    #Compose the condition that will be used for comparing the Binary Log
    #with the one is following each slave, depending if there's one or more 
    #slaves
    if [[ $slavesquant > 1 ]]
    then
        let slavesquant-=1
        for (( c=0; c<=$slavesquant; c++ ))
        do
            eval vname="mlf$c"
            if [[ $c == 0 ]]
            then
                eval vname="mlf$c"
                ifbase="( \"$LastLine\" == \"\$$vname\" )"
            else
                ifbase="$ifbase && ( \"$LastLine\" == \"\$$vname\" )"
            fi
        done
    elif [[ $slavesquant == 1 ]]
    then
        eval vname="mlf$slavesquant"
        ifbase="$ifbase \"\$$vname\" "
    fi

    #If the present master's Binary Log is equal to all the slaves purge the Binary Log
    #and send an email
    if [[ $ifbase ]]
    then
        SUBJECT="$hostname: Binary logs purge report"
        $mysql -u$user -p$password -hlocalhost -bse "purge binary logs to '$LastLine';"
        pslavesquant=${#slaves[@]}
        let pslavesquant-=1
        counter=0
        for i in "${slaves[@]}" 
        do
            eval vname="mlf$counter"
            vname=$(eval "echo \$${vname}")	
            echo "Master_Log_File on $i was $vname when purged logs" >> $EMAILMESSAGE
            let counter+=1
        done	
    else
        #If not is not possible to purge Binary Logs since replica could be
        #broken, so do not do anything and sent a report about it
	    SUBJECT="$hostname: binary logs are not up to date"
        echo "found binary logs differences before the purged so didn't proceed in order to not breack the replica" > $EMAILMESSAGE
        echo "Last binary log on $hostname is: $LastLine" >> $EMAILMESSAGE
        pslavesquant=${#slaves[@]}
        for i in "${slaves[@]}"
        do
            eval vname="mlf$counter"
            vname=$(eval "echo \$${vname}")
            echo "Master_Log_File on $i was $vname when purged logs" >> $EMAILMESSAGE
            let counter+=1
        done	
    fi
fi
mail -s "$SUBJECT" "$EMAIL" < $EMAILMESSAGE
rm $path/binarylog
rm $path/slave_hosts
rm $path/reference*
