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

	// send erase command
	uint32_t page = 0;
	uint32_t block = 0;
	uint32_t chip = 0;
	uint32_t bus = 0;
	uint32_t cmd = 2; // erase
	uint32_t tag = 0;

	uint32_t offset = ((1<<16) | cmd | (tag<<8))*4;
	uint32_t data = (block<<8) | (chip<<24) | (bus<<28);

	pcie->userWriteWord(offset, data);
	printf( "Sending erase command\n" );
	
	sleep (1);
	// write data to page buffer
	for ( int i = 0; i < 8192/4; i++ ) {
		if ( i % 8 == 0 ) {
			pcie->userWriteWord(i*4,0xc001d00d);
		} else {
			pcie->userWriteWord(i*4, i);
		}
	}
	// send write command
	offset = ((1<<16) | /*cmd*/1 | (tag<<8))*4;
	data = page | (block<<8) | (chip<<24) | (bus<<28);
	pcie->userWriteWord(offset, data);
	printf( "Sending write command\n" );

	// zero out page buffer
	sleep(1);
	for ( int i = 0; i < 8192/4; i++ ) {
		if ( i % 8 == 0 ) {
			pcie->userWriteWord(i*4,0);
		}
	}
	// send read command
	offset = ((1<<16) | /*cmd*/0 | (tag<<8))*4;
	data = page | (block<<8) | (chip<<24) | (bus<<28);
	pcie->userWriteWord(offset, data);
	printf( "Sending read command\n" );
	// read data from page buffer
	sleep(1);
	for ( int i = 0; i < 8192/4; i++ ) {
		uint32_t d = pcie->userReadWord(i*4);
		if ( i % 8 == 0 ) {
			printf("%x\n", d);
			fflush(stdout);
		} else {
			printf("%x ", d);
			fflush(stdout);
		}
	}




}
