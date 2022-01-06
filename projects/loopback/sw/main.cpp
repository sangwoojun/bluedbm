#include <stdio.h>
#include <unistd.h>
#include <time.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

#define PORT 0
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

	int cnt = 16;
	printf( "Quad 117\n" );
	fflush( stdout );
	for ( int i = 0; i < 4; i ++ ) {
		printf( "X1Y%d Channel Up: %x\n", cnt, pcie->userReadWord(0) );
		fflush( stdout );
		cnt ++;
	}
	cnt = 24;
	printf( "Quad 119\n" );
	fflush( stdout );
	for ( int i = 0; i < 4; i ++ ) {
		printf( "X1Y%d Channel Up: %x\n", cnt, pcie->userReadWord(0) );
		fflush( stdout );
		cnt ++;
	}
	cnt = 16;
	printf( "Quad 117\n" );
	fflush( stdout );
	for ( int i = 0; i < 4; i ++ ) {
		printf( "X1Y%d Lane Up: %x\n", cnt, pcie->userReadWord(0) );
		fflush( stdout );
		cnt ++;
	}
	cnt = 24;
	printf( "Quad 119\n" );
	fflush( stdout );
	for ( int i = 0; i < 4; i ++ ) {
		printf( "X1Y%d Lane Up: %x\n", cnt, pcie->userReadWord(0) );
		fflush( stdout );
		cnt ++;
	}
	printf( "\n" );
	fflush( stdout );
	pcie->Ioctl(1, 0);
	sleep(1);

	pcie->userWriteWord(0, PORT); //designate input port of AuroraExt
	printf( "Designate input port as %d\n", PORT );
	fflush( stdout );
	
	for ( int i = 0; i < 32; i ++ ) {
		pcie->userWriteWord(1, 0xdeadbeef);
		pcie->userWriteWord(1, 0xcafef00d);
	}
	printf( "Send Done! (deadbeef & cafef00d)\n\n" );
	fflush( stdout );
	sleep(10);
	
	int resCnt = 16;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Quad 117\n" );
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord(0) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord(0) );
		fflush(stdout);
		resCnt ++;
	}
	resCnt = 24;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Quad 119\n" );
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord(0) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord(0) );
		fflush(stdout);
		resCnt ++;
	}

	return 0;
}
