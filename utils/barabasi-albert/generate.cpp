#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

// 4KB
#define BLOCK_SIZE (1024)
//#define BLOCK_CACHE_COUNT 256

uint64_t llrand() {
	uint64_t r = 0;

	for (int i = 0; i < 5; ++i) {
		r = (r << 15) | (rand() & 0x7FFF);
	}

	return r;
}

uint64_t* block_edgecount = NULL;
//(uint64_t*)malloc(sizeof(uint64_t)*blockcount);
uint64_t total_edgecount = 0;
uint64_t blockcount = 0;
uint64_t nodecount = 1;

FILE* fvertex = NULL;
void incr_vec_count(uint64_t v) {
	uint64_t tfv = 0;
	fseek(fvertex,v*sizeof(uint64_t),SEEK_SET);
	int rr = fread(&tfv, sizeof(uint64_t),1,fvertex);
	if ( rr != 1 ) {
		printf( "Error reading %d\n", rr );
	}
	tfv++;
	//printf( "%ld >> %ld\n", v,tfv );
	fseek(fvertex,v*sizeof(uint64_t),SEEK_SET);
	int r = fwrite(&tfv,sizeof(uint64_t),1,fvertex);
	if ( r != 1 ) {
		printf( "Error writing %d\n", r );
	}
}

FILE* fout = 0;

void
add_edge(uint64_t from, uint64_t to) {
	if ( from == to ) return;
	if ( from > to ) {
		uint64_t t = from;
		from = to; to = t;
	}

	total_edgecount += 2;
	block_edgecount[ from/BLOCK_SIZE ] += 1;
	block_edgecount[ to/BLOCK_SIZE ] += 1;

	// update block in vertex file
	incr_vec_count(from);
	incr_vec_count(to);

	//printf( "Adding edge from %ld <-> %ld\n", from,to );

	uint64_t wv[4];
	wv[0] = from;
	wv[1] = to;
	wv[2] = to;
	wv[3] = from;

	fwrite(wv, sizeof(uint64_t), 4, fout);
}

/*
uint64_t
vertex_edgecount(uint64_t vidx) {
	return 0;
}
*/


uint64_t rbuffer[BLOCK_SIZE];

uint64_t
random_vertex() {
	//FIXME randomness expects total_edgecount to be much smaller than 2^64
	uint64_t nv = llrand()%total_edgecount;
	uint64_t tsum = 0;

	//printf( "%ld %ld\n", nv, total_edgecount );

	for ( uint64_t i = 0; i < blockcount; i++ ) {
		uint64_t ntsum = tsum + block_edgecount[i];
		if ( ntsum >= nv ) {
			// read block from vertex file
			uint64_t nntsum = tsum;
			fseek(fvertex,i*BLOCK_SIZE*sizeof(uint64_t),SEEK_SET);
			fread(rbuffer, sizeof(uint64_t), BLOCK_SIZE, fvertex);
			for ( uint64_t j = 0; j < BLOCK_SIZE; j++ ) {
				nntsum += rbuffer[j];
				if ( nntsum >= nv ) {
					return (i*BLOCK_SIZE)+j;
				}
			}

			printf( "Error! random_vertex block check didn't catch %ld %ld\n", tsum, nntsum );
			return (i*BLOCK_SIZE);
		}
		tsum = ntsum;
	}

	printf( "Error! random_vertex didn't catch\n" );
	return 0;
}

void init(uint64_t scale, char* ofilename) {
	nodecount = 1;
	nodecount <<= scale;
	blockcount = nodecount/BLOCK_SIZE+1;

	block_edgecount = (uint64_t*)malloc(sizeof(uint64_t)*blockcount);
	total_edgecount = 0;

	fvertex = fopen("vertex.dat", "wb+");
	uint64_t wbuf[1024];
	memset(wbuf, 0, 1024*sizeof(uint64_t));
	for ( unsigned int i = 0; i < (nodecount/1024)+1; i++ ) {
		fwrite(wbuf,sizeof(uint64_t),1024,fvertex);
	}
	fout = fopen(ofilename, "wb");
}

int 
main(int argc, char** argv) {
	srand(time(0));
	uint64_t scale = 5;
	char ofilename[128] = "generated.dat";
	float random_edge_rate = 0.1f;
	uint64_t edgefactor = 16;

	if ( argc >= 2 ) {
		strncpy(ofilename, argv[1], 128);
	}

	if ( argc >= 3 ) {
		scale = atoi(argv[2]);
	}

	if ( argc >= 4 ) {
		edgefactor = atoi(argv[3]);
	}
	
	if ( argc >= 5 ) {
		random_edge_rate = atof(argv[4]);
	}

	init(scale, ofilename);

	printf( "Scale: %ld Node Count: %ld, Block Count: %ld\n", scale, nodecount, blockcount );


	// add initial clique
	add_edge(0,1);
	add_edge(1,2);
	add_edge(2,0);


	for (uint64_t nidx = 2; nidx < nodecount; nidx++) {
		for ( uint64_t eidx = 0; eidx < edgefactor; eidx++ ) {
			uint32_t redgev = rand()%1000;
			if ( redgev < random_edge_rate*1000 ) {
				uint64_t tv = llrand()%(nidx-1);
				add_edge(tv,nidx);
			} else {
				uint64_t tv = random_vertex();
				add_edge(tv,nidx);
			}
		}
	}
	for ( uint64_t i = 0; i < blockcount; i++ ) {
		printf( "-- %ld\n", block_edgecount[i] );
	}

	printf( "Done\n" );

	
	fclose(fvertex);
	fclose(fout);
	return 0;

	//return 0;
}
