/**
 generates a sparse matrix in Compressed Row Storage (CRS) format
 using kronecker graph generation

 creates two files: row-value pairs and column indices
 row-value pairs file is 8k page aligned, and column indices are page indices

 delta compression per column

*/

#include "stdio.h"
#include "stdlib.h"
#include "unistd.h"
#include "string.h"
#include "stdint.h"
#include "math.h"
#include "time.h"

#include "pthread.h"
#define THREAD_COUNT 24

#define FPAGE_SIZE 8192

double imat[2][2];
FILE* ofile;
FILE* ifile;

uint64_t kronecker_edge_generate(int coff, int scale) {
	double* im = imat[coff&1];
	uint64_t rv = 0;
	for ( int i = 0; i < scale; i++ ) {
		int m1 = im[0]*10000;
		int m2 = im[1]*10000;
		int mt = m1+m2;
		int rn = rand()%mt;

		if ( rn < m1 ) {
			rv = (rv<<1);
		} else {
			rv = (rv<<1)|1;
		}
	}

	return rv;
}

void edge_sort(uint64_t* rbuf, int count) {
	for ( int i = 0; i < count; i++ ) {
		for ( int j = i; j < count; j++ ) {
			if ( rbuf[i] > rbuf[j] ) {
				uint64_t t = rbuf[j];
				rbuf[j] = rbuf[i];
				rbuf[i] = t;
			}
		}
	}
}

/*
00 : 30 bit delta
01 : 62 bit idx ( not delta )
10 : 30 bit delta (incr cidx)
11 : 62 bit idx ( not delta ) (incr cidx)

64'b11111... is considered nop
*/
uint64_t totalrcount = 0;
uint64_t woff = 0;
uint64_t lastpoff = -1;
void write_ind(int scale, uint64_t cidx) {
	if ( woff % 8192 == 0 ) {
		//printf( "cidx %ld is aligned\n", cidx );
		uint64_t poff = (woff>>13);
		if ( poff > lastpoff + scale*4 ) { // scale*4 is arbitrary
			fwrite(&poff, sizeof(uint64_t), 1, ifile);
			fwrite(&cidx, sizeof(uint64_t), 1, ifile);
			lastpoff = poff;
		}
	}
}
void write_row(uint64_t* rbuf, uint64_t cidx, int count, int scale) {
	write_ind(scale, cidx);
	uint64_t last = 0;
	for ( int i = 0; i < count; i++ ) {
		if ( rbuf[i] != last ) {
			//printf( "%lx, %lx\n", cidx, rbuf[i] );
			if ( rbuf[i] - last < (1<<30) ) {
				uint32_t data = (( rbuf[i] - last ) << 2);
				if( i == 0 ) data |= 0x2;
				fwrite(&data, sizeof(uint32_t), 1, ofile);
				woff += sizeof(uint32_t);
			} else {
				uint64_t data = (rbuf[i]<< 2) | 0x1;
				if( i == 0 ) data |= 0x2;
				fwrite(&data, sizeof(uint64_t), 1, ofile);
				woff += sizeof(uint64_t);
			}

			last = rbuf[i];
			totalrcount ++;
		}
	}
}

// usage: ./kronecker SCALE OUTPUT.dat
int main(int argc, char** argv) {
	if ( argc < 3 ) {
		fprintf(stderr, "usage: %s SCALE OUTPUT\n", argv[0] );
		exit(0);
	}

	srand(time(NULL));

	// determine output file names
	int scale = atoi(argv[1]);
	char oname[128];
	char iname[128];
	snprintf(oname, 128, "mat.%s", argv[2]);
	snprintf(iname, 128, "ind.%s", argv[2]);
	ofile = fopen(oname, "wb");
	ifile = fopen(iname, "wb");

	// initialize initiator matrix
	imat[0][0] = 0.9;
	imat[0][1] = 0.6;
	imat[1][0] = 0.3;
	imat[1][1] = 0.7;
	if ( argc >= 7 ) {
		imat[0][0] = atof(argv[3]); 
		imat[0][1] = atof(argv[4]); 
		imat[1][0] = atof(argv[5]); 
		imat[1][1] = atof(argv[6]); 
	}

	double imatt = 0;
	for ( int i = 0; i < 2; i ++ ) {
		for ( int j = 0; j < 2; j++ ) {
			imatt += imat[i][j];
		}
	}
	uint64_t ecount = pow(imatt, scale);

	uint64_t ncount = pow(2,scale);
	
	// print run info
	printf( "Starting graph generation with scale = %d\n", scale );
	printf( "Writing to output file %s and %s\n", oname, iname );
	printf( "Node count %ld\n", ncount );
	printf( "Edge count (apprx) %ld\n", ecount );
	printf( "Initiator matrix: \n %f %f\n %f %f\n", imat[0][0], imat[0][1], imat[1][0], imat[1][1] );

	int avgpercol = (int)(ecount/ncount);
	if ( avgpercol < 1 ) avgpercol = 1;

	printf( "Average rows per column: %d\n", avgpercol );
	int bfactor = 2;
	uint64_t* rbuf = (uint64_t*)malloc(sizeof(uint64_t)*avgpercol*bfactor);
	for ( uint64_t cidx = 0; cidx < ncount; cidx++ ) {
		int rcount = rand()%(avgpercol*2);
		if ( rcount < 1 ) rcount = 1; //FIXME 0 should be possible

		for ( int i = 0; i < rcount; i++ ) {
			uint64_t rv = kronecker_edge_generate(cidx&1, scale);
			rbuf[i] = rv;
		}
		edge_sort(rbuf, rcount);
		write_row(rbuf, cidx, rcount, scale);

	}
	printf( "Done!\n" );

	fclose(ofile);
	fclose(ifile);
	exit(0);
}

bool kronecker_edge_exist(uint64_t col, uint64_t row, int scale) {
	double prob = 1;
	for ( int i = 0; i < scale; i++ ) {
		uint64_t npow = pow(2,i);
		int xidx = (col/npow)&0x1;
		int yidx = (row/npow)&0x1;
		double pprob = imat[xidx][yidx];
		prob *= pprob;
	}

	int mord = 50;
	uint64_t mult = (1<<mord);
	uint64_t al = prob*mult;
	uint64_t rv = rand()%mult;

	//printf( "%ld %ld\n", al, rv );

	if ( rv < al ) return true;
	return false;
}

