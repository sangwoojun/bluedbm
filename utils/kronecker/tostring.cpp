#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

int
main(int argc, char** argv) {
	if ( argc < 3 ) {
		printf( "usage: %s in_filename out_filename [dedup]\n", argv[0] );
		exit(1);
	}
	char* infilename = argv[1];
	char* outfilename = argv[2];
	bool dedup = false;
	if ( argc >= 4  ) {
		dedup = true;
	}

	FILE* fin = fopen(infilename, "rb");
	FILE* fout = fopen(outfilename, "w");
	if ( !fin ) {
		printf( "Failed to open %s\n", infilename );
		exit(1);
	}

	printf( "%s > %s dedup: %s\n", infilename, outfilename, dedup?"True":"False" );

	uint64_t rbuf[2];
	uint64_t last_rbuf[2] = {0,0};
	while ( !feof(fin) ) {
		int r = fread(&rbuf, sizeof(uint64_t), 2, fin);
		if ( r != 2 ) continue;

		if ( rbuf[0] == last_rbuf[0] && rbuf[1] == last_rbuf[1] ) continue;
		if ( last_rbuf[0] > rbuf[0] ) continue;

		last_rbuf[0] = rbuf[0];
		last_rbuf[1] = rbuf[1];


		fprintf(fout, "%10ld\t%10ld\n", rbuf[0], rbuf[1] );
	}

	fclose(fin);
	fclose(fout);
}
