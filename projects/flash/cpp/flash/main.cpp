#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"
#include "flashmanager.h"
#include "dmasplitter.h"

extern double timespec_diff_sec( timespec start, timespec end );

main() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();

	void* dmabuffer = pcie->dmaBuffer();
	unsigned int* ubuf = (unsigned int*)dmabuffer;

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	printf( "All Init Done\n" );
	fflush(stdout);

	//dma->sendWord(0,0,0,2); // Test DMA // Test Flash Connectivity 


	uint32_t* pageBufferW = (uint32_t*)malloc(8192+32);
	uint32_t* pageBufferR = (uint32_t*)malloc(8192+32);
	uint32_t* pageBufferR0 = (uint32_t*)malloc(8192+32);
	for ( int i = 0; i < 8192/4; i++ ) {
		pageBufferW[i] = i;
	}
	/*
	printf( "Sending erase message:\n" );
	flash->eraseBlock(1,1,1);
	sleep(1);
	printf( "Sending write message:\n" );
	flash->writePage(1,1,1,0, pageBufferW);

*/
	printf( "\t\tSending read cmd\n" ); fflush(stdout);
	sleep (2);
	
	flash->readPage(1,1,1,0, pageBufferR0);

	timespec start, now;
	clock_gettime(CLOCK_REALTIME, & start);
	//int rcount = 10;
	int rcount = (1024*1024)/8;
	for ( int i = 0; i < rcount; i++ ) {
		int bus = i & 0x7;
		int chip = (i>>3) &0x7;
		int block = (i>>6) & 0xfff;
		int page = (i>>18);
#ifdef BSIM	
		block = (block % 128);
		page = page % 16;
#endif
		flash->readPage(bus,chip,block,page, pageBufferR);
	}
	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %f\n", timespec_diff_sec(start, now) );
	/*
	for ( int i = 0; i < 16; i++ ) {
		flash->readPage(1,1,1,i, pageBufferR);
	}
	*/

	sleep (2);

	for ( int i = 0; i < 32; i++ ) {
		printf( "%x ", pageBufferR0[i] );
	}

}
