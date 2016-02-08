#!/bin/bash

VFILES="
	RegFile.v
	SyncHandshake.v
	SyncRegister.v
	SyncResetA.v
	MakeResetA.v
	SizedFIFO.v
	Counter.v
	TriState.v
	FIFO2.v
	ResetInverter.v
	SyncFIFO.v
	ClockDiv.v
	ResetEither.v
	MakeReset.v
	SyncReset0.v
	BRAM2.v
	"

CURDIR=`pwd`
cd $BLUESPECDIR/Verilog;
for VFILE in $VFILES ;
do
	echo $VFILE
	cp $VFILE $CURDIR/
done
