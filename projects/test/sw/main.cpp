#include <stdio.h>
#include <unistd.h>
#include <time.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}


int main(int argc, char** argv) {
	//printf( "Software startec\n" ); fflush(stdout);
	BdbmPcie* pcie = BdbmPcie::getInstance();

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);
	if ( d != 0xc001d00d ) {
		printf( "Magic number is incorrect (0xc001d00d)\n" );
		return -1;
	}

	uint32_t offset = 0;
	uint32_t data = 0;
	uint32_t tag = 0;
	uint32_t pageoffset = 892;
	
	/*
	// send erase command
	offset = ((1<<16) | 2 | (tag<<8))*4;
	data = pageoffset;
	pcie->userWriteWord(offset, data);
	printf( "Sending erase command. Waiting for ack\n" ); fflush(stdout);
	while (true) {
		uint32_t event = pcie->userReadWord(8192*8);
		if ( event >= 0xffffffff ) continue;


		printf( "Event: %x\n", event );
		break;
	}

	
	for ( int i = 0; i < 8192/4; i++ ) {
		if ( i % 8 == 0 ) {
			pcie->userWriteWord(i*4,0xc001d00d);
		} else {
			pcie->userWriteWord(i*4, i);
		}
	}
	printf( "Finished writing to page buffer\n" );
	fflush(stdout);
	
	// send write command
	offset = ((1<<16) | 1 | (tag<<8))*4;
	data = pageoffset;
	pcie->userWriteWord(offset, data);
	printf( "Sending write command. Waiting for ack...\n" );
	while (true) {
		uint32_t event = pcie->userReadWord(8192*8);
		if ( event >= 0xffffffff ) continue;


		printf( "Event: %x\n", event );
		break;
	}
	
	// zero out page buffer
	for ( int i = 0; i < 8192/4; i++ ) {
		pcie->userWriteWord(i*4,0);
	}
	*/

	timespec start;
	timespec now;
	clock_gettime(CLOCK_REALTIME, & start);
	printf( "Sending read commands\n" );
	//uint32_t pagecount = (1024*1024*(32/8)); //32 GB
	uint32_t pagecount = 4096; //32 GB
	for ( uint32_t p = 0; p < pagecount; p++ ) { // 32 GB
	//for ( int p = 0; p < 32; p++ ) {
		tag = p%256;
		offset = ((1<<16) | /*cmd*/0 | (tag<<8))*4; //read
		data = p;
		pcie->userWriteWord(offset, data);
		//printf( "Sending read command %d\n", p ); fflush(stdout);
	}

	clock_gettime(CLOCK_REALTIME, & now);
	double diff = timespec_diff_sec(start, now);
	printf( "Elapsed: %f, words read %d\n", diff, pcie->userReadWord(16*8192));
	fflush(stdout);

	// read data from page buffer
	sleep(1);

	for ( int i = 0; i < 8192/4 * 4; i++ ) {
		uint32_t d = pcie->userReadWord(i*4);
		if ( i % 8 == 7 ) {
			printf("%x\n", d);
			fflush(stdout);
		} else {
			printf("%x, ", d);
			fflush(stdout);
		}
	}
	exit(0);
}
