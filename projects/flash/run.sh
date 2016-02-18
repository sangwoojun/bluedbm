#!/bin/bash

./bsim/obj/bsim &
export BDBM_BSIM_PID=$!
echo "running sw"
echo $BDBM_BSIM_PID
sleep 1
#gdb ./sw 
./sw | tee res.txt
kill -9 $BDBM_BSIM_PID
rm /dev/shm/bdbm$BDBM_BSIM_PID
