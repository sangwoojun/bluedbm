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

#define PUBKEY_FPGA1 1
#define PUBKEY_FPGA2 2
#define PUBKEY_HOST 3
#define PRIVKEY_HOST 3

#define HOST 0
#define FPGA1_1 1
#define FPGA2_1 2
#define FPGA1_2 3
#define FPGA2_2 4

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

// Public Key of FPGA1
uint32_t publicKeyFPGA1_32b(uint32_t routingPacket) {
	uint32_t encPacket = routingPacket ^ PUBKEY_FPGA1;
	return encPacket;
}
uint16_t publicKeyFPGA1_16b(uint16_t routingPacket) {
	uint16_t encPacket = routingPacket ^ PUBKEY_FPGA1;
	return encPacket;
}
uint8_t publicKeyFPGA1_8b(uint8_t routingPacket) {
	uint8_t encPacket = routingPacket ^ PUBKEY_FPGA1;
	return encPacket;
}
// Public Key of FPGA2
uint32_t publicKeyFPGA2_32b(uint32_t routingPacket) {
	uint32_t encPacket = routingPacket ^ PUBKEY_FPGA2;
	return encPacket;
}
uint16_t publicKeyFPGA2_16b(uint16_t routingPacket) {
	uint16_t encPacket = routingPacket ^ PUBKEY_FPGA2;
	return encPacket;
}
uint8_t publicKeyFPGA2_8b(uint8_t routingPacket) {
	uint8_t encPacket = routingPacket ^ PUBKEY_FPGA2;
	return encPacket;
}
// Public & Private Key of Host
uint32_t publicKeyHost_32b(uint32_t routingPacket) {
	uint32_t encPacket = routingPacket ^ PUBKEY_HOST;
	return encPacket;
}
uint32_t privateKeyHost_32b(uint32_t encRoutingPacket) {
	uint32_t decPacket = encRoutingPacket ^ PRIVKEY_HOST;
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

	// Check Aurora Channel and Lane	
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

	// Payload	
	uint32_t address = 0; // 32-bit Start Point of The Address
	uint32_t amountofmemory = 4*1024;
	uint32_t header = 0; // 0:Write, 1:Read
	uint32_t aomNheader = (amountofmemory << 1) | header; // 32-bit R/W + Amount of Memory
	// Actual Route
	uint8_t outportFPGA2_2 = 7;
	uint8_t outportFPGA1_2 = 2;
	uint8_t outportFPGA2_1 = 5;
	uint8_t outportFPGA1_1 = 0;
	// Header Part
	uint8_t packetHeader1stSR = 0; // 1-bit S/D Flag
	uint8_t packetHeader2ndSR = 4; // 7-bit Route Cnt ***
	uint8_t packetHeader3rdSR = HOST; // 8-bit Starting Point
	uint8_t packetHeader4thSR = 8; // 8-bit Payload Bytes
	uint32_t packetHeaderSR = ((uint32_t)packetHeader4thSR << 16) | ((uint32_t)packetHeader3rdSR << 8) | 
				  ((uint32_t)packetHeader2ndSR << 1) | (uint32_t)packetHeader1stSR; // 24-bit Packet Header
	uint8_t numHops = 4; // 8-bit The number of Hops ***
	uint32_t headerPartSR = (packetHeaderSR << 8) | numHops; // 32-bit Header Part

	// Encryption
	// Payload
	uint32_t encAddress = publicKeyFPGA1_32b(address);
	uint32_t encAomNheader = publicKeyFPGA1_32b(aomNheader);
	// Actual Route
	uint8_t encOutportFPGA2_2 = publicKeyFPGA2_8b(outportFPGA2_2);
	uint8_t encOutportFPGA1_2 = publicKeyFPGA1_8b(outportFPGA1_2);
	uint8_t encOutportFPGA2_1 = publicKeyFPGA2_8b(outportFPGA2_1);
	uint8_t encOutportFPGA1_1 = publicKeyFPGA1_8b(outportFPGA1_1);
	uint32_t encActualRoute = ((uint32_t)encOutportFPGA2_2 << 24) | ((uint32_t)encOutportFPGA1_2 << 16) |
				  ((uint32_t)encOutportFPGA2_1 << 8) | (uint32_t)encOutportFPGA1_1; // 32-bit Encrypted Each Actual Route
	// Header Part
	uint32_t encHeaderPartSR = publicKeyFPGA1_32b(headerPartSR); // 32-bit Encrypted Header Part

	pcie->userWriteWord(0, encHeaderPartSR);
	pcie->userWriteWord(0, encActualRoute);
	pcie->userWriteWord(0, encAomNheader);
	pcie->userWriteWord(0, encAddress);
	
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

	pcie->userWriteWord(0, encHeaderPartSR);
	pcie->userWriteWord(0, encActualRoute);
	pcie->userWriteWord(0, encAomNheader);
	pcie->userWriteWord(0, encAddress);
	
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
