#include <stdio.h>
#include <unistd.h>
#include <time.h>
#include <math.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

#define INPORT 3
// AuroraExt117
// 0 means X1Y16, 1 means X1Y17
// 2 means X1Y18, 3 means X1Y19
// AuroraExt119
// 4 means X1Y24, 5 means X1Y25
// 6 means X1Y26, 7 means X1Y27
// Current Connections
// X1Y16 <=> X1Y17
// X1Y18 <=> X1Y24
// X1Y19 <=> X1Y25

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
	fflush( stdout );
	if ( d != 0xc001d00d ) {
		printf( "Magic number is incorrect (0xc001d00d)\n" );
		return -1;
	}
	printf( "\n" );
	fflush( stdout );
	
	int resCnt = 16;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Channel Up[X1Y%d]: %x\n", resCnt, pcie->userReadWord(8*4) );
		fflush( stdout );
		resCnt ++;
	}
	resCnt = 24;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Channel Up[X1Y%d]: %x\n", resCnt, pcie->userReadWord(8*4) );
		fflush( stdout );
		resCnt ++;
	}
	resCnt = 16;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Lane Up[X1Y%d]: %x\n", resCnt, pcie->userReadWord(9*4) );
		fflush( stdout );
		resCnt ++;
	}
	resCnt = 24;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Lane Up[X1Y%d]: %x\n", resCnt, pcie->userReadWord(9*4) );
		fflush( stdout );
		resCnt ++;
	}
	printf( "\n" );
	fflush( stdout );
	sleep(1);

	printf( "Network test between two FPGAs" );
	printf( "Starting performance testing and validation check\n" );
	fflush( stdout );
	
	timespec start;
	timespec now;
	unsigned int v = 0;
	pcie->userWriteWord(0, INPORT); //designate input port of AuroraExt
	
	clock_gettime(CLOCK_REALTIME, & start);
	while ( 1 ) {
		v = pcie->userReadWord(INPORT*4);
		if ( v == 1 ) { 
			break;
		}else if ( v == 0 ) {
			break;
		}
	}
	/*for ( int i = 0; i < 4; i ++ ) {
		printf("%d\n", pcie->userReadWord(OUTPORT*4));
	}*/
	fflush(stdout);
	clock_gettime(CLOCK_REALTIME, & now);
	double diff = timespec_diff_sec(start, now);
	
	if ( v == 1 ) { 
		printf( "Elapsed: %f\n", diff );
		printf( "Bandwith: %f\n", (((double) 16 * 128) / diff) / pow(10.0, 9.0) );
		printf( "Result: %f\n\n", ((double) 16 / (double) 16)*100 );
		fflush( stdout );
		sleep(1);
	} else {
		printf( "Result is not 100%%. Please check the system\n" );
		exit(1);
	}
	return 0;
}
