#include <stdio.h>
#include <unistd.h>
#include <time.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

#define PORT 1
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
		printf( "Lane Up[X1Y%d]: %x\n", resCnt, pcie->userReadWord(8*4) );
		fflush( stdout );
		resCnt ++;
	}
	resCnt = 24;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Lane Up[X1Y%d]: %x\n", resCnt, pcie->userReadWord(8*4) );
		fflush( stdout );
		resCnt ++;
	}
	printf( "\n" );
	fflush( stdout );
	sleep(1);

	pcie->userWriteWord(0, PORT); //designate input port of AuroraExt
	printf( "Designate input port as %d\n\n", PORT );
	fflush( stdout );
	sleep(2);

	pcie->userWriteWord(4, 0xacedc0de);
	pcie->userWriteWord(4, 0xbabeface);
	printf( "Send the first payload done! (acedc0de & babeface)\n\n" );	
	fflush( stdout );
	sleep(1);

	pcie->userWriteWord(4, 0xdeadbeef);
	pcie->userWriteWord(4, 0xcafef00d);
	printf( "Send the second payload done! (deadbeef & cafef00d)\n\n" );
	fflush( stdout );
	sleep(1);

	pcie->userWriteWord(4, 0xfeedc0c0);
	pcie->userWriteWord(4, 0xb00bdace);
	printf( "Send the third payload done! (feedc0c0 & b00bdace)\n\n" );
	fflush( stdout );
	sleep(1);

	resCnt = 16;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Quad 117\n" );
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord(i*4) );
		fflush(stdout);
		resCnt ++;
	}
	resCnt = 24;
	for ( int i = 0; i < 4; i ++ ) {
		printf( "Quad 119\n" );
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord((4+i)*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord((4+i)*4 ));
		fflush(stdout);
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord((4+i)*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord((4+i)*4 ));
		fflush(stdout);
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord((4+i)*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord((4+i)*4 ));
		fflush(stdout);
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord((4+i)*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord((4+i)*4 ));
		fflush(stdout);
		printf( "X1Y%d received(1/2): %x\n", resCnt, pcie->userReadWord((4+i)*4) );
		fflush(stdout);
		printf( "X1Y%d received(2/2): %x\n", resCnt, pcie->userReadWord((4+i)*4 ));
		fflush(stdout);
		resCnt ++;
	}
	printf( "\n");

	return 0;
}
