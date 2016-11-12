#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#include <cstdlib>

#include <string>

int main( int argc, char** argv ) {
	if ( argc < 2 ) {
		printf( "usage: ./%s [file]\n", argv[0] );
		exit(1);
	}

	char oname[128] = "parsed.dat";
	if ( argc >= 3 ) {
		strncpy(oname, argv[2], 128);
	}

	FILE* fin = fopen(argv[1], "r");
	FILE* fout = fopen(oname, "wb");
	char line[256];
	uint64_t max_nid = 0;
	uint64_t edge_count = 0;

	while (!feof(fin)) {
		if( !fgets(line, 256, fin) ) break;

		char* from = strtok(line, " \t");
		char* to = strtok(NULL, " \t");


		uint64_t froml = atoll(from);
		uint64_t tol = atoll(to);

		if ( froml > max_nid ) max_nid = froml;
		if ( tol > max_nid ) max_nid = tol;

		edge_count ++;

		//printf( "%lx %lx\n", froml, tol );
		fwrite(&froml, sizeof(uint64_t), 1, fout);
		fwrite(&tol, sizeof(uint64_t), 1, fout);

		if ( edge_count % 100000 == 0 ) printf( "Edge %ld\n", edge_count );
	}

	fclose(fin);
	fclose(fout);

	printf( "Parse finished!\nParsed %ld nodes and %ld edges\n", max_nid, edge_count );
}
