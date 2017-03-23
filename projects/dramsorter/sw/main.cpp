#include <stdio.h>
#include <unistd.h>

#include <string>
#include <time.h>

#include "bdbmpcie.h"
//#include "flashmanager.h"
//#include "bsbfs.h"



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
	//FlashManager* flash = FlashManager::getInstance();

	srand(time(NULL));

	//void* dmabuffer = pcie->dmaBuffer();
	//unsigned int* ubuf = (unsigned int*)dmabuffer;

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	printf( "All Init Done\n" );
	fflush(stdout);
	

/*
	pcie->userWriteWord(12,4); // merger test cmd
	pcie->userWriteWord(8,rand());
	pcie->userWriteWord(4,rand());
	pcie->userWriteWord(0,256*1024*1024);;
	for ( int i = 0; i < 16; i++ ) {
		sleep(1);
		uint32_t tot = pcie->userReadWord(9*4);
		uint32_t test = pcie->userReadWord(64);
		printf( "Total: %d  %x\n", tot, test );
		fflush(stdout);
		pcie->userWriteWord(12,4); // merger test cmd
		pcie->userWriteWord(8,rand());
		pcie->userWriteWord(4,rand());
		pcie->userWriteWord(0,256*1024*1024);;
	}

	exit(0);
*/


		
	uint32_t tot = pcie->userReadWord(8*4);
	printf( "Total: %d\n", tot );


	pcie->userWriteWord(12,rand());
	pcie->userWriteWord(8,rand());
	pcie->userWriteWord(4,rand());
	pcie->userWriteWord(0,rand());
	
	pcie->userWriteWord(12,8);
	pcie->userWriteWord(0,256*1024*1024);
	
	pcie->userWriteWord(64, 0xdeadbeef);

	// src, dst {DRAM/addr, Flash/addr, accel, SW}

	// for len
	// create 8KB -> DRAM

	// feed 8KB 8KB to sorter 

	//BSBFS* fs = BSBFS::getInstance();
	while (1) {
		sleep(1);
		uint32_t tot = pcie->userReadWord(8*4);
		uint32_t test = pcie->userReadWord(64);
		printf( "Total: %d  %x\n", tot, test );
		fflush(stdout);
		pcie->userWriteWord(12,8);
		pcie->userWriteWord(0,256*1024*1024);
	}
	
}
