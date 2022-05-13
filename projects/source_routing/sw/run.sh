#!/bin/bash

../hw/bsim/obj/bsim &
export BDBM_BSIM_PID=$!
echo "running sw"
echo $BDBM_BSIM_PID
sleep 1
if [ "$1" == "gdb" ]
then
	gdb ./obj/bsim 
else
	./obj/bsim | tee res.txt
fi
kill -9 $BDBM_BSIM_PID
rm /dev/shm/bdbm$BDBM_BSIM_PID
