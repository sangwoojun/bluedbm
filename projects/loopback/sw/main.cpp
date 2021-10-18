#include <stdio.h>
#include <unistd.h>
#include <time.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

static const uint32_t port = 0;

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}


int main(int argc, char** argv) {

	printf( "Software startec\n" ); fflush(stdout);
	BdbmPcie* pcie = BdbmPcie::getInstance();

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);
	if ( d != 0xc001d00d ) {
		printf( "Magic number is incorrect (0xc001d00d)\n" );
		return -1;
	}

	pcie->userWriteWord(0, port); //designate input port of AuroraExt

	int readCount = 0;
	for ( int i = 0; i < 1024; i ++ ) {
		int d_1 = pcie->userWriteWord(0, 0xdeadbeef);
		if ( d_1 == 0 ) {
			printf( "Read: %x\n", pcie->userReadWord(0) );
			readCount ++;
			pcie->userWriteWord(0, 0xdeadbeef);
		}
		int d_2 = pcie->userWriteWord(0, 0xcafef00d);
		if ( d_2 == 0 ) {
			printf( "Read: %x\n", pcie->userReadWord(0) );
			readCount ++;
			pcie->userWriteWord(0, 0xcafef00d);
		}
	}

	for ( int i = 0; i < 1024-readCount; i ++ ) {
		printf( "Read: %x\n", pcie->userReadWord(0) );
	}

	return 0;
}
