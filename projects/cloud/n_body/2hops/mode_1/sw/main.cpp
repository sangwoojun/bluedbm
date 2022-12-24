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

#define NumParticles 16777216

#define MAX_MIXING_COUNT 1000

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

int main(int argc, char** argv) {
	//srand(time(NULL)); // Do not need to refresh
	//------------------------------------------------------------------------------------
	// Initial
	//------------------------------------------------------------------------------------
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
	//------------------------------------------------------------------------------------
	// Generate the values of the particles
	//------------------------------------------------------------------------------------
	printf( "Started generating the values of the particles\n" );
	fflush( stdout );
	// Location X
	int x = 0, y = 0;
	float tmp = 0;
	float* particleLocX = (float*)malloc(sizeof(float)*NumParticles);
	float locX = -83.88607;
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocX[i] = locX;
		locX = locX + 0.00001;
	}
	for ( int j = 0; j < MAX_MIXING_COUNT; j ++ ) {
		x = random() % NumParticles;
		y = random() % NumParticles;
		if ( x != y ) {
			tmp = particleLocX[x];
			particleLocX[x] = particleLocX[y];
			particleLocX[y] = tmp;
		}
	}
	uint32_t* particleLocXv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleLocXv[k] = *(uint32_t*)&particleLocX[k];
	}
	// Location Y
	x = 0, y = 0;
	tmp = 0;
	float* particleLocY = (float*)malloc(sizeof(float)*NumParticles);
	float locY = -83.88607;
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocY[i] = locY;
		locY = locY + 0.00001;
	}
	for ( int j = 0; j < MAX_MIXING_COUNT; j ++ ) {
		x = random() % NumParticles;
		y = random() % NumParticles;
		if ( x != y ) {
			tmp = particleLocY[x];
			particleLocY[x] = particleLocY[y];
			particleLocY[y] = tmp;
		}
	}
	uint32_t* particleLocYv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleLocYv[k] = *(uint32_t*)&particleLocY[k];
	}
	// Location Z
	x = 0, y = 0;
	tmp = 0;
	float* particleLocZ = (float*)malloc(sizeof(float)*NumParticles);
	float locZ = -83.88607;
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleLocZ[i] = locZ;
		locY = locY + 0.00001;
	}
	for ( int j = 0; j < MAX_MIXING_COUNT; j ++ ) {
		x = random() % NumParticles;
		y = random() % NumParticles;
		if ( x != y ) {
			tmp = particleLocZ[x];
			particleLocZ[x] = particleLocZ[y];
			particleLocZ[y] = tmp;
		}
	}
	uint32_t* particleLocZv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleLocZv[k] = *(uint32_t*)&particleLocZ[k];
	}
	// Mass
	x = 0, y = 0;
	tmp = 0;
	float* particleMass = (float*)malloc(sizeof(float)*NumParticles);
	float mass = 0.0000000;
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleMass[i] = mass;
		mass = mass + 0.0000001;
	}
	for ( int j = 0; j < MAX_MIXING_COUNT; j ++ ) {
		x = random() % NumParticles;
		y = random() % NumParticles;
		if ( x != y ) {
			tmp = particleMass[x];
			particleMass[x] = particleMass[y];
			particleMass[y] = tmp;
		}
	}
	uint32_t* particleMassv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleMassv[k] = *(uint32_t*)&particleMass[k];
	}
	// Velocity X
	x = 0, y = 0;
	tmp = 0;
	float* particleVelX = (float*)malloc(sizeof(float)*NumParticles);
	float velX = 0.8388607;
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelX[i] = velX;
		velX = velX + 0.0000001;
	}
	for ( int j = 0; j < MAX_MIXING_COUNT; j ++ ) {
		x = random() % NumParticles;
		y = random() % NumParticles;
		if ( x != y ) {
			tmp = particleVelX[x];
			particleVelX[x] = particleVelX[y];
			particleVelX[y] = tmp;
		}
	}
	uint32_t* particleVelXv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleVelXv[k] = *(uint32_t*)&particleVelX[k];
	}
	// Velocity Y
	x = 0, y = 0;
	tmp = 0;
	float* particleVelY = (float*)malloc(sizeof(float)*NumParticles);
	float velY = 0.8388607;
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelY[i] = velY;
		velY = velY + 0.0000001;
	}
	for ( int j = 0; j < MAX_MIXING_COUNT; j ++ ) {
		x = random() % NumParticles;
		y = random() % NumParticles;
		if ( x != y ) {
			tmp = particleVelY[x];
			particleVelY[x] = particleVelY[y];
			particleVelY[y] = tmp;
		}
	}
	uint32_t* particleVelYv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleVelYv[k] = *(uint32_t*)&particleVelY[k];
	}
	// Velocity Z
	x = 0, y = 0;
	tmp = 0;
	float* particleVelZ = (float*)malloc(sizeof(float)*NumParticles);
	float velZ = 0.8388607;
	for ( int i = 0; i < NumParticles; i ++ ) {
		particleVelZ[i] = velZ;
		velZ = velZ + 0.0000001;
	}
	for ( int j = 0; j < MAX_MIXING_COUNT; j ++ ) {
		x = random() % NumParticles;
		y = random() % NumParticles;
		if ( x != y ) {
			tmp = particleVelZ[x];
			particleVelZ[x] = particleVelZ[y];
			particleVelZ[y] = tmp;
		}
	}
	uint32_t* particleVelZv = (uint32_t*)malloc(sizeof(uint32_t)*NumParticles);
	for ( int k = 0; k < NumParticles; k ++ ) {
		particleVelZv[k] = *(uint32_t*)&particleVelZ[k];
	}
	printf( "Generating the values of the particles done!\n\n" );
	fflush( stdout );
	//------------------------------------------------------------------------------------
	// Send the values of the particles through PCIe first & Check all data are stored well
	//------------------------------------------------------------------------------------
	int statCheckInit = 0;
	int dataSendMode = 0;
	unsigned int status = 0;
	printf( "Started to send the values of the particles\n" );
	fflush( stdout );
	for ( int i = 0; i < NumParticles/2048; i ++ ) {
		for ( int j = 0; j < 2048; j ++ ) {
			pcie->userWriteWord(dataSendMode*4, particleLocXv[(i*2048)+j]);
			pcie->userWriteWord(dataSendMode*4, particleLocYv[(i*2048)+j]);
			pcie->userWriteWord(dataSendMode*4, particleLocZv[(i*2048)+j]);
			pcie->userWriteWord(dataSendMode*4, particleMassv[(i*2048)+j]);
		}
		printf( "Sent %dth position and mass values\n", ((i*2048) + 2048) );
		fflush( stdout );
		sleep(1);
	}

	for ( int i = 0; i < NumParticles/2048; i ++ ) {
		for ( int j = 0; j < 2048; j ++ ) {
			pcie->userWriteWord(dataSendMode*4, particleVelXv[(i*2048)+j]);
			pcie->userWriteWord(dataSendMode*4, particleVelYv[(i*2048)+j]);
			pcie->userWriteWord(dataSendMode*4, particleVelZv[(i*2048)+j]);
		}
		printf( "Sent %dth velocity values\n", ((i*2048) + 2048) );
		fflush( stdout );
		sleep(1);
	}
	printf( "Sending the values of the particles done!\n" );
	fflush( stdout );

	while ( 1 ) {
		status = pcie->userReadWord(statCheckInit*4);
		if ( status == 1 ) {
			printf( "Storing the values of the particles to DRAM done!\n\n" );
			fflush( stdout );
			break;
		}
	}
	//------------------------------------------------------------------------------	
	// Send a command to HW to start running N-body
	//------------------------------------------------------------------------------
	timespec start;
	timespec now;
	int mode = 1;
	status = 0;
	printf( "The system mode\n" );
	printf( "1: Use only FPGA1\n" );
	printf( "2: Use both FPGA1 and FPGA2 with 1 Aurora lane (2hops)\n" );
	printf( "3: Use both FPGA1 and FPGA2 with 2 Aurora lanes (2hops)\n" );
	printf( "4: Use both FPGA1 and FPGA2 with 3 Aurora lanes (2hops)\n" );
	printf( "5: Use both FPGA1 and FPGA2 with 4 Aurora lanes (2hops)\n" );
	printf( "6: Use both FPGA1 and FPGA2 with 1 Aurora lane (4hops)\n" );
	printf( "Mode: %d\n\n", mode);
	fflush( stdout );
	pcie->userWriteWord(mode*4, 0);

	printf( "No need to send the data from FPGA1 to FPGA2\n" );
	printf( "Started to compute N-body App\n\n" );
	fflush( stdout );	

	clock_gettime(CLOCK_REALTIME, & start);
	//-------------------------------------------------------------------------------	
	// Status check over running N-body
	//-------------------------------------------------------------------------------
	int statCheckNbody = 1;
	status = 0;
	for ( int k = 0; k < NumParticles/256; k ++ ) {
		while ( 1 ) {
			status = pcie->userReadWord(statCheckNbody*4);
			if ( status == 1 ) {
				printf( "Computing N-body app & writing the 256 updated data to memory done!\n" );
				fflush( stdout );
				break;
			}
		}
	}
	clock_gettime(CLOCK_REALTIME, & now);
	printf( "\n" );
	fflush( stdout );
	//-------------------------------------------------------------------------------	
	// Status check for finishing N-body App
	//-------------------------------------------------------------------------------
	double diff = timespec_diff_sec(start, now);

	int getNumOfCycles = 2;
	status = 0;
	status = pcie->userReadWord(getNumOfCycles*4);
	double ff = (double)status/diff;
	printf( "FLOPs: %f\n", ff );
	fflush( stdout );

	return 0;
}
