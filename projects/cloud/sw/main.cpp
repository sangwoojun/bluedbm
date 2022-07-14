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
// Public Key of FPGA1
uint32_t publicKeyFPGA1_32b(uint32_t routingPacket) {
	uint32_t encPacket = routingPacket ^ 1;
	return encPacket;
}
uint8_t publicKeyFPGA1_8b(uint8_t routingPacket) {
	uint8_t encPacket = routingPacket ^ 1;
	return encPacket;
}
// Public Key of FPGA2
uint32_t publicKeyFPGA2_32b(uint32_t routingPacket) {
	uint32_t encPacket = routingPacket ^ 2;
	return encPacket;
}
uint8_t publicKeyFPGA2_8b(uint8_t routingPacket) {
	uint8_t encPacket = routingPacket ^ 2;
	return encPacket;
}
// Public & Private Key of Host
uint32_t publicKeyHost_32b(uint32_t routingPacket) {
	uint32_t encPacket = routingPacket ^ 3;
	return encPacket;
}
uint32_t privateKeyHost_32b(uint32_t encRoutingPacket) {
	uint32_t decPacket = encRoutingPacket ^ 3;
	return decPacket;
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
		
		uint32_t address = 0; // 32-bit Start Point of The Address
		uint32_t amountofmemory = 4*1024;
		uint32_t header = 0; // 0:Write, 1:Read
		uint32_t aomNheader = (amountofmemory << 1) | header; // 32-bit R/W + Amount of Memory
		uint32_t packetHeader = 0; // 16-bit Packet Header

		uint8_t outportFPGA2 = 6; // 8-bit Output Port of FPGA2
		uint8_t outportFPGA1_1 = 4; // 8-bit Output Port of FPGA1_1
		uint8_t numHops = 2; // 8-bit The number of Hops
		
		uint32_t encaddress = publicKeyFPGA1_32b(address);
		uint32_t encaomNheader = publicKeyFPGA1_32b(aomNheader);
		uint32_t encpacketHeader = publicKeyFPGA1_32b(packetHeader);

		uint8_t encoutportFPGA2 = publicKeyFPGA2_8b(outportFPGA2);
		uint8_t encoutportFPGA1_1 = publicKeyFPGA1_8b(outportFPGA1_1);
		uint8_t encnumHops = publicKeyFPGA1_8b(numHops);

		uint32_t encHeaderPart = ((uint32_t)encoutportFPGA2 << 16) | ((uint32_t)encoutportFPGA1_1 << 8) | (uint32_t)encnumHops ;

		pcie->userWriteWord(direction, encHeaderPart);
		pcie->userWriteWord(direction, encpacketHeader);
		pcie->userWriteWord(direction, encaomNheader);
		pcie->userWriteWord(direction, encaddress);
	} else {
		printf( "Sending source routing packet from FPGA2 to FPGA1\n" );
		pcie->userWriteWord(direction, 0);
	}
	fflush( stdout );
	
	int cnt = 0;
	int* aom;	
	unsigned int d_0 = 0;
	unsigned int d_1[3] = { 0, };
	
	if ( direction == 0 ) {
		while ( 1 ) {
			d_0 = pcie->userReadWord(direction*4);
			if ( d_0 == 1 ) {
				break;
			} else if ( d_0 == 0 ) {
				break;
			}
		}
		printf( "Sending source routing packet succeeded!\n" );
		fflush( stdout );
	} else {
		while ( 1 ) {
			if ( cnt > 2 ) {
				break;
			}
			d_0 = pcie->userReadWord(direction*4);
			if ( d_0 != 305419896 ) {
				d_1[cnt] = d_0;
				cnt ++;
			}
	 	}
		printf( "\n" );
		fflush(stdout);

		uint32_t address = privateKeyHost_32b(d_1[0]);
		uint32_t aomNHeader = privateKeyHost_32b(d_1[1]);
		uint32_t rwHeader = (aomNHeader >> 31);
		uint32_t aomTmp = (aomNHeader << 1);
		uint32_t aomFinal = (aomTmp >> 1);
		uint32_t packetHeader = privateKeyHost_32b(d_1[2]);	

		if ( rwHeader == 1 ) {
			aom = (int*)malloc(aomFinal);
		}

		printf( "Packet Header: %u\n", packetHeader );
		printf( "Amount of Memory: %llu Bytes\n", aomFinal );
		printf( "Start Point of Address: %p\n", address );
		
		if ( rwHeader == 1 ) {
			free(aom);
		}
	}
	printf("\n");
	fflush(stdout);
	return 0;
}