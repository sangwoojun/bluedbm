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
	
	uint32_t page = 4;
	uint32_t block = 1;
	uint32_t chip = 0;
	uint32_t bus = 0;
	uint32_t tag = 0;
	
	// send erase command
	offset = ((1<<16) | 2 | (tag<<8))*4;
	data = (block<<8) | (chip<<24) | (bus<<28);
	pcie->userWriteWord(offset, data);
	printf( "Sending erase command\n" );
	sleep (1);

	
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
	offset = ((1<<16) | /*cmd*/1 | (tag<<8))*4;
	data = page | (block<<8) | (chip<<24) | (bus<<28);
	pcie->userWriteWord(offset, data);
	printf( "Sending write command\n" );
	sleep(1);
	
	// zero out page buffer
	for ( int i = 0; i < 8192/4; i++ ) {
		pcie->userWriteWord(i*4,0);
	}

	sleep(1);
	
	
	for ( int p = 0; p < 8; p++ ) {
		tag = p;
		offset = ((1<<16) | /*cmd*/0 | (tag<<8))*4; //read
		data = page | (block<<8) | (chip<<24) | (bus<<28);
		pcie->userWriteWord(offset, data);
		printf( "Sending read command\n" );
	}
	// read data from page buffer
	sleep(1);

	for ( int i = 0; i < 8192/4 * 8; i++ ) {
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
