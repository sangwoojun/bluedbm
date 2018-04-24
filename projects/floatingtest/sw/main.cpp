#include <stdio.h>
#include <unistd.h>

#include <string>

#include "bdbmpcie.h"



/*
PRNG
(cmd: generate(count))
Distributed DRAM accumulator
(cmd: range, init) (stat: bytes)
DRAM-DRAM Sorter(cmd: write range)
Flash-Flash Sorter(cmd: write page)
Flash reader (cmd:page('new/future reuse count', or 'reuse', range)
DRAM->Flash writer(cmd: 8K page in DRAM, page address)

*/

extern double timespec_diff_sec( timespec start, timespec end );

int main(int argc, char** argv) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	//DMASplitter* dma = DMASplitter::getInstance();

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	printf( "All Init Done\n" );
	fflush(stdout);
	
	//pcie->userWriteWord(16*4,0xc001d00d);
	while (1) {
		for ( int i = 0; i < 32; i++ ) {
			printf( "++%2d %x\n", i, pcie->userReadWord(i*4) );
		}
		printf( "\n" );
		fflush(stdout);
		
		sleep(1);
	}


	// src, dst {DRAM/addr, Flash/addr, accel, SW}

	// for len
	// create 8KB -> DRAM

	// feed 8KB 8KB to sorter 

	//BSBFS* fs = BSBFS::getInstance();
	
}
