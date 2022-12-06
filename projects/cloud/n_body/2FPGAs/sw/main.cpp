#include <stdio.h>
#include <unistd.h>
#include <time.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

#include <ctime>
#include <chrono>

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

#define NumParticles 16777216

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

// Main
int main(int argc, char** argv) {
	//srand(time(NULL)); // Do not need to refresh
	//------------------------------------------------------------------------
	// Initial
	//------------------------------------------------------------------------
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
	//------------------------------------------------------------------------
	// Test
	//------------------------------------------------------------------------
	float* a = (float*)malloc(sizeof(float)*2);
	a[0] = 9.00f;
	a[1] = 3.00f;
	uint32_t* av = (uint32_t*)malloc(sizeof(uint32_t)*2);
	av[0] = *(uint32_t*)&a[0];
	av[1] = *(uint32_t*)&a[1];
	pcie->userWriteWord(0, av[0]);
	pcie->userWriteWord(0, av[1]);
	pcie->userWriteWord(0, 0);
	pcie->userWriteWord(0, 0);
	//------------------------------------------------------------------------
	// Generate the values of the particles
	//------------------------------------------------------------------------
	/*float* particleLocX = (float*)malloc(sizeof(float)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocX[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleLocX[i] == particleLocX[j] ) {
				i--;
				break;
			}
		}
	}
	float* particleLocY = (float*)malloc(sizeof(float)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocY[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleLocY[i] == particleLocY[j] ) {
				i--;
				break;
			}
		}
	}
	float* particleLocZ = (float*)malloc(sizeof(float)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocZ[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleLocZ[i] == particleLocZ[j] ) {
				i--;
				break;
			}
		}
	}
	float* particleVelX = (float*)malloc(sizeof(float)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelX[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleVelX[i] == particleVelX[j] ) {
				i--;
				break;
			}
		}
	}
	float* particleVelY = (float*)malloc(sizeof(float)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelY[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleVelY[i] == particleVelY[j] ) {
				i--;
				break;
			}
		}
	}
	float* particleVelZ = (float*)malloc(sizeof(float)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelZ[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleVelZ[i] == particleVelZ[j] ) {
				i--;
				break;
			}
		}
	}
	float* particleMass = (float*)malloc(sizeof(float)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleMass[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleMass[i] == particleMass[j] ) {
				i--;
				break;
			}
		}
	}*/
	//------------------------------------------------------------------------	
	// Take the value of system mode & Send the source routing packets
	//------------------------------------------------------------------------
	/*int mode = 0;
	int srPacketMode = 5;
	printf( "The system mode\n" );
	printf( "0: Use only FPGA1\n" );
	printf( "1: Use both FPGA1 and FPGA2 with 1 Aurora lane\n" );
	printf( "2: Use both FPGA1 and FPGA2 with 2 Aurora lanes\n" );
	printf( "3: Use both FPGA1 and FPGA2 with 3 Aurora lanes\n" );
	printf( "4: Use both FPGA1 and FPGA2 with 4 Aurora lanes\n" );
	scanf( "%d", &mode );
	fflush( stdout );

	if ( mode == 0 ) {
		printf( "No need to send source routing packets from FPGA1 to FPGA2\n" );
		printf( "Starting to store the data directly to DRAM of FPGA1\n" );
		fflush( stdout );	
	} else {
		printf( "Sending source routing packets from FPGA1 to FPGA2\n" );
		fflush( stdout );
		pcie->userWriteWord(srPacketMode*4, 0);
	}*/
	//------------------------------------------------------------------------	
	// Send the values of the particles through PCIe
	//------------------------------------------------------------------------
	/*for ( int k = 0; k < NumParticles; k ++ ) {
		pcie->userwriteword(mode*4, particleLocX[k]);
		pcie->userwriteword(mode*4, particleLocY[k]);
		pcie->userwriteword(mode*4, particleLocZ[k]);
		pcie->userwriteword(mode*4, particleVelX[k]);
		pcie->userwriteword(mode*4, particleVelY[k]);
		pcie->userwriteword(mode*4, particleVelZ[k]);
		pcie->userwriteword(mode*4, particleMass[k]);
	}
	*/
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

	return 0;
}
