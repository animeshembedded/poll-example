#!/bin/sh
instance=$1
myport=$2
count=1;
while [ $count -le $instance ]
do
	/usr/bin/x-terminal-emulator  -e nc localhost $2 
	count=`expr $count + 1`
done
