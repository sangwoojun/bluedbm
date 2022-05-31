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
// Current Connections
// FPGA1 X1Y16 <=> FPGA1 X1Y17
// FPGA1 X1Y19 <=> FPGA2 X1Y26 FPGA2 to FPGA1
// FPGA1 X1Y24 <=> FPGA2 X1Y27 FPGA1 to FPGA2

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
	
	int direction = 0;
	printf( "Please input the direction (0: FPGA1 to FPGA2, 1: FPGA2 to FPGA1): " );
	scanf( "%d", &direction );
	if ( direction == 0 ) {
		printf( "Sending source routing packet from FPGA1 to FPGA2\n" );
		
		uint64_t address = 0;
		uint32_t addressFirst = (uint32_t) address;
		uint64_t addressSecondTmp = address >> 32;
		uint32_t addressSecond = (uint32_t) addressSecondTmp;
	
		uint64_t amountofmemory = 4*1024;
		uint64_t header = 0;
		uint64_t aomNheader = (header << 47) | amountofmemory;
		uint32_t aomNheaderFirst = (uint32_t) aomNheader;
		uint64_t aomNheaderSecondTmp = aomNheader >> 32;
		uint32_t aomNheaderSecond = (uint32_t) aomNheaderSecondTmp;

		uint32_t outportHost = 0;
		uint32_t outportFPGA1 = 4;
		uint32_t outport = (outportHost << 8) | outportFPGA1;

		pcie->userWriteWord(direction, addressFirst);
		pcie->userWriteWord(direction, addressSecond);
		pcie->userWriteWord(direction, aomNheaderFirst);
		pcie->userWriteWord(direction, aomNheaderSecond);
		pcie->userWriteWord(direction, outport);
	} else {
		printf( "Sending source routing packet from FPGA2 to FPGA1\n" );
		pcie->userWriteWord(direction, 0);
	}
	fflush( stdout );
	
	int* aom;	
	unsigned int d_0 = 0;
	unsigned int d_1[4] = { 0, };
	
	if ( direction == 0 ) {
		while ( 1 ) {
			d_0 = pcie->userReadWord(direction*4);
			if ( d_0 == 1 ) {
				break;
			}
		}
		printf( "Sending source routing packet from FPGA1 to FPGA2 succeeded!\n" );
	} else {
		for ( int i = 0; i < 5; i ++ ) {
			d_1[i] = pcie->userReadWord(direction*4);
			printf( "%d ", d_1[i] );
		}
		printf( "\n" );
		fflush(stdout);
	
		uint64_t add_1 = d_1[0];
		uint64_t add_2_Tmp = d_1[1];
		uint64_t add_2 = add_2_Tmp << 32;
		uint64_t addFinal = add_1 | add_2;
		uint64_t aom_1 = d_1[2];
		uint64_t aom_2_Tmp = d_1[3];
		uint64_t aom_2 = aom_2_Tmp << 16;
		uint64_t aom_3 = aom_1 | aom_2;
		uint64_t aom_4 = aom_3 << 17;
		uint64_t aomFinal = aom_4 >> 17;
		uint64_t rw = aom_3 >> 47;
		uint32_t outPortFPGA1Tmp = d_1[4] << 24;
		uint32_t outPortFPGA1 = outPortFPGA1Tmp >> 24;
		uint32_t outPortFPGA2 = d_1[4] >> 8;

		if ( rw == 1 ) {
			aom = (int*)malloc(aomFinal);
		}

		printf( "OutPort of FPGA2: %u\n", outPortFPGA2 );
		printf( "OutPort of FPGA1: %u\n", outPortFPGA1 );
		printf( "Amount of Memory: %llu Bytes\n", aomFinal );
		
		if ( rw == 1 ) {
			printf( "Start Point of Address: %p\n", aom );
			free(aom);
		}
	}
	printf("\n");
	fflush(stdout);
	return 0;
}
