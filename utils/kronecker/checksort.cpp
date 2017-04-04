#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#include <cstdio>


int
main(int argc, char** argv) {
	if ( argc < 2 ) {
		printf( "Usage: %s filename\n", argv[0] );
		exit(1);
	}

	FILE* fin = fopen(argv[1], "rb");

	uint32_t last = 0;
	uint64_t offset = 0;
	while(!feof(fin)) {
		uint32_t din[2];// = 0;
		if ( 0 == fread(din, sizeof(uint32_t),2,fin) ) break;

		if ( din[0] <= last ) {
			printf( "Unsorted 64bit value! %x < %x @ %lx\n", din[0], last, offset );
		} else {
		}
		last = din[0];
		offset+= sizeof(uint64_t);
	}
}
