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

int main(int argc, char** argv) {
	//srand(time(NULL)); // Do not need to refresh
	//-------------------------------------------------------------------------------
	// Initial
	//-------------------------------------------------------------------------------
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
	//-------------------------------------------------------------------------------
	// Generate the values of the particles
	//-------------------------------------------------------------------------------
	float* particleLocX = (float*)malloc(sizeof(float)*NumParticles);
	uint32_t* particleLocXv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocX[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleLocX[i] == particleLocX[j] ) {
				i--;
				break;
			}
		}
	}
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleLocXv[k] = *(uint32_t*)&particleLocX[k];
	}
	float* particleLocY = (float*)malloc(sizeof(float)*NumParticles);
	uint32_t* particleLocYv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocY[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleLocY[i] == particleLocY[j] ) {
				i--;
				break;
			}
		}
	}
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleLocYv[k] = *(uint32_t*)&particleLocY[k];
	}
	float* particleLocZ = (float*)malloc(sizeof(float)*NumParticles);
	uint32_t* particleLocZv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocZ[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleLocZ[i] == particleLocZ[j] ) {
				i--;
				break;
			}
		}
	}
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleLocZv[k] = *(uint32_t*)&particleLocZ[k];
	}
	float* particleMass = (float*)malloc(sizeof(float)*NumParticles);
	uint32_t* particleMassv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);	
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleMass[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleMass[i] == particleMass[j] ) {
				i--;
				break;
			}
		}
	}
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleMassv[k] = *(uint32_t*)&particleMass[k];
	}
	float* particleVelX = (float*)malloc(sizeof(float)*NumParticles);
	uint32_t* particleVelXv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);	
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelX[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleVelX[i] == particleVelX[j] ) {
				i--;
				break;
			}
		}
	}
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleVelXv[k] = *(uint32_t*)&particleVelX[k];
	}
	float* particleVelY = (float*)malloc(sizeof(float)*NumParticles);
	uint32_t* particleVelYv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);	
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelY[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleVelY[i] == particleVelY[j] ) {
				i--;
				break;
			}
		}
	}
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleVelYv[k] = *(uint32_t*)&particleVelY[k];
	}
	float* particleVelZ = (float*)malloc(sizeof(float)*NumParticles);
	uint32_t* particleVelZv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);	
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelZ[i] = (float)(rand()%10000)/10000.f;
		for ( int j = 0; j < i; j ++ ) {
			if ( particleVelZ[i] == particleVelZ[j] ) {
				i--;
				break;
			}
		}
	}
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleVelZv[k] = *(uint32_t*)&particleVelZ[k];
	}
	//-------------------------------------------------------------------------------
	// Send the values of the particles through PCIe first
	//-------------------------------------------------------------------------------
	int statCheckInit = 0;
	int dataSendMode = 0;
	unsigned int status = 0;
	printf( "Started to send the values of the particles\n" );
	fflush( stdout );
	for ( int k = 0; k < NumParticles; k ++ ) {
		pcie->userWriteWord(dataSendMode*4, particleLocXv[k]);
		pcie->userWriteWord(dataSendMode*4, particleLocYv[k]);
		pcie->userWriteWord(dataSendMode*4, particleLocZv[k]);
		pcie->userWriteWord(dataSendMode*4, particleMassv[k]);
	}
	for ( int l = 0; l < NumParticles; l ++ ) {
		pcie->userWriteWord(dataSendMode*4, particleVelXv[l]);
		pcie->userWriteWord(dataSendMode*4, particleVelYv[l]);
		pcie->userWriteWord(dataSendMode*4, particleVelZv[l]);
	}
	while ( 1 ) {
		status = pcie->userReadWord(statCheckInit*4);
		if ( status == 1 ) {
			printf( "Sending the values of the particels done!\n\n" );
			fflush( stdout );
			break;
		}
	}
	//------------------------------------------------------------------------------	
	// Take the value of system mode & Send a command to HW & Start running N-body
	//------------------------------------------------------------------------------
	timespec start;
	timespec now;
	int statCheckMemMng = 1;
	int mode = 0;
	status = 0;
	printf( "The system mode\n" );
	printf( "1: Use only FPGA1\n" );
	printf( "2: Use both FPGA1 and FPGA2 with 1 Aurora lane\n" );
	printf( "3: Use both FPGA1 and FPGA2 with 2 Aurora lanes\n" );
	printf( "4: Use both FPGA1 and FPGA2 with 3 Aurora lanes\n" );
	printf( "5: Use both FPGA1 and FPGA2 with 4 Aurora lanes\n" );
	scanf( "Mode: %d", &mode );
	fflush( stdout );
	pcie->userWriteWord(mode*4, 0);
	if ( mode == 1 ) {
		printf( "No need to send the data from FPGA1 to FPGA2\n" );
		printf( "Started to compute N-body App\n\n" );
		fflush( stdout );	
	} else {
		printf( "Started to send the data from FPGA1 to FPGA2\n" );
		fflush( stdout );
		while ( 1 ) {
			status = pcie->userReadWord(statCheckMemMng*4);
			if ( status == 1 )  {
				printf( "Sending some of the values of the particles to FPGA2 done!\n" );
				printf( "Started to compute N-body App\n\n" );
				fflush( stdout );
				pcie->userWriteWord(mode*4, 0);
				break;
			}
		}
	}
	clock_gettime(CLOCK_REALTIME, & start);
	//-------------------------------------------------------------------------------	
	// Status check for finishing N-body App
	//-------------------------------------------------------------------------------
	int statCheckNbody = 2;
	status = 0;
	while ( 1 ) {
		status = pcie->userReadWord(statCheckNbody*4);
		if ( status == 1 ) {
			clock_gettime(CLOCK_REALTIME, & now);
			printf( "Computing N-body app & writing the updated data to memory done!\n" );
			fflush( stdout );
			break;
		}
	}
	double diff = timespec_diff_sec(start, now);

	int getNumOfCycles = 3;
	status = 0;
	status = pcie->userReadWord(getNumOfCycles*4);
	double ff = (double)status/diff;
	printf( "FF: %f\n", ff );
	fflush( stdout );

	return 0;
}
