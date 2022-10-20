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
	uint32_t pubKey = 1;
	uint32_t encPacket = routingPacket ^ pubKey;
	return encPacket;
}
uint16_t publicKeyFPGA1_16b(uint16_t routingPacket) {
	uint16_t pubKey = 1;
	uint16_t encPacket = routingPacket ^ pubKey;
	return encPacket;
}
uint8_t publicKeyFPGA1_8b(uint8_t routingPacket) {
	uint8_t pubKey = 1;
	uint8_t encPacket = routingPacket ^ pubKey;
	return encPacket;
}
// Public Key of FPGA2
uint32_t publicKeyFPGA2_32b(uint32_t routingPacket) {
	uint32_t pubKey = 2;
	uint32_t encPacket = routingPacket ^ pubKey;
	return encPacket;
}
uint16_t publicKeyFPGA2_16b(uint16_t routingPacket) {
	uint16_t pubKey = 2;
	uint16_t encPacket = routingPacket ^ pubKey;
	return encPacket;
}
uint8_t publicKeyFPGA2_8b(uint8_t routingPacket) {
	uint8_t pubKey = 2;
	uint8_t encPacket = routingPacket ^ pubKey;
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
	
	printf( "Sending source routing packet from FPGA1 to FPGA2\n" );
	fflush( stdout );	
	uint32_t address = 0; // 32-bit Start Point of The Address
	uint32_t amountofmemory = 4*1024;
	uint32_t header = 0; // 0:Write, 1:Read
	uint32_t aomNheader = (amountofmemory << 1) | header; // 32-bit R/W + Amount of Memory
	uint16_t packetHeader = 0; // 16-bit Packet Header

	uint8_t outportFPGA1_2 = 3; // 8-bit Output Port of FPGA1_2
	uint8_t outportFPGA2_1 = 7; // 8-bit Output Port of FPGA2
	uint8_t outportFPGA1_1 = 4; // 8-bit Output Port of FPGA1_1
	uint8_t numHops = 3; // 8-bit The number of Hops
		
	uint32_t encAddress = publicKeyFPGA2_32b(address);
	uint32_t encAomNheader = publicKeyFPGA2_32b(aomNheader);
	uint16_t encPacketHeader = publicKeyFPGA2_16b(packetHeader);

	uint8_t encOutportFPGA1_2 = publicKeyFPGA1_8b(outportFPGA1_2);
	uint8_t encOutportFPGA2_1 = publicKeyFPGA2_8b(outportFPGA2_1);
	uint8_t encOutportFPGA1_1 = publicKeyFPGA1_8b(outportFPGA1_1);
	uint8_t encNumHops = publicKeyFPGA1_8b(numHops);

	uint32_t encHeaderPart = ((uint32_t)encOutportFPGA1_2 << 24) | ((uint32_t)encOutportFPGA2_1 << 16) | 
				 ((uint32_t)encOutportFPGA1_1 << 8) | (uint32_t)encNumHops;

	pcie->userWriteWord(0, encHeaderPart);
	pcie->userWriteWord(0, (uint32_t)encPacketHeader);
	pcie->userWriteWord(0, encAomNheader);
	pcie->userWriteWord(0, encAddress);

	unsigned int d_0 = 0;

	while ( 1 ) {
		d_0 = pcie->userReadWord(0);
		if ( d_0 == 1 ) {
			printf( "Sending source routing packet from Host to FPGA2_2 succeeded!\n" );
			fflush( stdout );
			break;
		} else if ( d_0 == 0 ) {
			printf( "Sending source routing packet from Host to FPGA2_2 is in failure...\n" );
			fflush( stdout );
			break;
		}
	}
	
	return 0;
}