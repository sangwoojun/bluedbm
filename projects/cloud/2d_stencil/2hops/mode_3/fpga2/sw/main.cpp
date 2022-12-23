#include <stdio.h>
#include <unistd.h>
#include <time.h>
#include <math.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

// AuroraExt117
// 0 means X1Y16, 1 means X1Y17
// 2 means X1Y18, 3 means X1Y19
// AuroraExt119
// 4 means X1Y24, 5 means X1Y25
// 6 means X1Y26, 7 means X1Y27

#define FPGA1_1 1
#define FPGA2_1 2
#define FPGA1_2 3
#define FPGA2_2 4

#define SourceRouting 0
#define DataSending 1

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

// Main
int main(int argc, char** argv) {
	printf( "Software startec\n" ); fflush(stdout);
	BdbmPcie* pcie = BdbmPcie::getInstance();

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush( stdout );
	if ( d != 0xc001d00d ) {
		printf( "Magic number is incorrect (0xc001d00d)\n" );
		return -1;
	}
	printf( "\n" );
	fflush( stdout );

	printf( "Sending source routing packet from FPGA1_1 to FPGA1_3\n" );
	fflush( stdout );	

	pcie->userWriteWord(0, SourceRouting);
	
	unsigned int d_0 = 0;
	while ( 1 ) {
		d_0 = pcie->userReadWord(0);
		if ( d_0 == 1 ) {
			printf( "Sending source routing packet succedded!\n" );
			fflush( stdout );
			break;
		} else if ( d_0 == 0 ) {
			printf( "Sending source routing packet is in failure...\n" );
			fflush( stdout );
			break;
		}
	}

	printf( "Sending data sending packet from FPGA1_1 to FPGA1_3\n" );
	fflush( stdout );	

	pcie->userWriteWord(0, DataSending);
	
	d_0 = 0;
	while ( 1 ) {
		d_0 = pcie->userReadWord(0);
		if ( d_0 == 1 ) {
			printf( "Sending source routing packet succedded!\n" );
			fflush( stdout );
			break;
		} else if ( d_0 == 0 ) {
			printf( "Sending source routing packet is in failure...\n" );
			fflush( stdout );
			break;
		}
	}

	return 0;
}
