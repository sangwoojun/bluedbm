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

#include "config.h"


double imat[2][2];
FILE* ofile;
//FILE* ifile;

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
			//fwrite(&poff, sizeof(uint64_t), 1, ifile);
			//fwrite(&cidx, sizeof(uint64_t), 1, ifile);
			lastpoff = poff;
		}
	}
}

/*
type: 2 bits
size: 2 bits
0000 is null (32 bits)
0010 is 14(row) 14(data) // ShortHalf

0100 is 28 bit col //ShortCol
0110 is 60 bit col //LongCol

1000 is 28 bit row //ShortRow
1001 is 14(row) 14(row) //ShortDouble
1010 is 60 bit row //LongRow

1100 is 28 bit data //ShortData
1110 is 60 bit data //LongData
*/

uint64_t stat_shorthalf = 0;
uint64_t stat_shortdouble = 0;
uint64_t stat_shortrow = 0;
uint64_t stat_longrow = 0;
uint64_t stat_padbytes = 0;

uint64_t last_cidx = 0;
uint64_t write_offset = 0;
uint64_t internal_offset = 0;
uint32_t* compress(uint64_t* rbuf, uint64_t cidx, int count, int& rbytes) {
	uint64_t max28 = (1<<headeroffset)-1;
	uint64_t max14 = (1<<14)-1;

	uint32_t* rowbuf = (uint32_t*)malloc(sizeof(uint32_t)*2*count + 8);// safe allocation
	uint64_t last_row = 0;
	int oidx = 0;
	for ( int i = 0; i < count; i++ ) {
		uint64_t row = rbuf[i];
		if ( i+1 < count 
			&& row-last_row < max14 
			&& rbuf[i+1] - row < max14 ) {
			uint64_t nrow = rbuf[i+1];
			
			rowbuf[oidx++] = (ShortDouble << headeroffset) | ((uint32_t)(row-last_row)<<14)
				| ((uint32_t)(nrow-row)); 
			last_row = nrow;
			oidx++;
			stat_shortdouble++;
/*
		} else if ( row - last_row < max14 ) {
			rowbuf[oidx++] = (ShortHalf << headeroffset) | ((uint32_t)row<<14) | 1; // data is 1
			last_row = row;
			stat_shorthalf++;
*/
		} else if ( row - last_row < max28 ) {
			rowbuf[oidx++] = (ShortRow << headeroffset) | ((uint32_t)(row-last_row));
			last_row = row;
			stat_shortrow ++;
		} else {
			rowbuf[oidx++] = (LongRow << headeroffset) | ((uint32_t)(row>>32));
			rowbuf[oidx++] = ((uint32_t)(row));
			last_row = row;
			stat_longrow ++;
		}
	}

	uint64_t rowbytes = oidx*4;
	uint64_t colbytes = 8;

	uint64_t padbytes = 0;
	if ( internal_offset + rowbytes + colbytes > block_mbs * 1024*1024) {
		//padbytes = internal_offset + rowbytes + colbytes - block_mbs*1024*1024;
		padbytes = block_mbs*1024*1024 - internal_offset;
	}
	stat_padbytes += padbytes;
	
	uint64_t allocsize = rowbytes+colbytes+padbytes;
	uint32_t* buf = (uint32_t*)malloc(allocsize);
	for ( uint64_t i = 0; i < padbytes/4; i++ ) {
		buf[i] = 0; // Null
	}
	buf[padbytes/4] = (LongCol<<headeroffset) | (uint32_t)(cidx>>32);
	buf[padbytes/4+1] = (uint32_t)cidx;
	for ( int i = 0; i < oidx; i++ ) {
		buf[i+padbytes/4+2] = rowbuf[i];
	}


	// if write_offset is 16MB aligned
	// or if cidx - last_cidx > 28 bits
	last_cidx = cidx;
	internal_offset = (internal_offset + allocsize)%(block_mbs*1024*1024);
	write_offset += allocsize;
	
	free(rowbuf);
	rbytes = allocsize;
	return buf;
}

void write_row(uint64_t* rbuf, uint64_t cidx, int count, int scale) {
	//write_ind(scale, cidx);
	int rbytes = 0;
	uint32_t* wbuf = compress(rbuf, cidx, count, rbytes);
	fwrite(wbuf, rbytes, 1 , ofile);
	free(wbuf);
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
	snprintf(oname, 128, "mat.%s", argv[2]);
	ofile = fopen(oname, "wb");

	int avgrowcount = 0;
	if ( argc >= 3 ) {
		avgrowcount = atoi(argv[3]);
	}

	// initialize initiator matrix
	imat[0][0] = 0.9;
	imat[0][1] = 0.6;
	imat[1][0] = 0.3;
	imat[1][1] = 0.7;
	if ( argc >= 7 ) {
		imat[0][0] = atof(argv[4]); 
		imat[0][1] = atof(argv[5]); 
		imat[1][0] = atof(argv[6]); 
		imat[1][1] = atof(argv[7]); 
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
	printf( "Writing to output file %s \n", oname );
	printf( "Node count %ld\n", ncount );
	printf( "Edge count (apprx) %ld\n", ecount );
	printf( "Initiator matrix: \n %f %f\n %f %f\n", imat[0][0], imat[0][1], imat[1][0], imat[1][1] );

	int avgpercol = (int)(ecount/ncount);
	if ( avgrowcount > 0 ) avgpercol = avgrowcount;
	if ( avgpercol < 1 ) avgpercol = 1;

	write_offset = 0;
	internal_offset = 0;
	last_cidx = 0;
	stat_longrow = 0;
	stat_shortrow = 0;
	stat_padbytes = 0;
	stat_shorthalf = 0;
	stat_shortdouble = 0;

	printf( "Average rows per column: %d\n", avgpercol );
	int bfactor = 2;
	uint64_t* rbuf = (uint64_t*)malloc(sizeof(uint64_t)*avgpercol*bfactor);
	for ( uint64_t cidx = 0; cidx < ncount; cidx++ ) {
		int rcount = rand()%(avgpercol*bfactor);
		if ( rcount < 1 ) rcount = 1; //FIXME 0 should be possible

		for ( int i = 0; i < rcount; i++ ) {
			uint64_t rv = kronecker_edge_generate(cidx&1, scale);
			rbuf[i] = rv;
		}
		edge_sort(rbuf, rcount);
		write_row(rbuf, cidx, rcount, scale);

	}
	while ( internal_offset > 0 ) {
		uint32_t zero = 0;
		fwrite(&zero, sizeof(uint32_t), 1 , ofile);
		internal_offset = (internal_offset + sizeof(uint32_t))%(block_mbs*1024*1024);
		stat_padbytes += 4;
	}

	printf( "stat_longrow : %ld\nstat_shortrow : %ld\n", stat_longrow, stat_shortrow );
	printf( "stat_shorthalf: %ld\nstat_shortdouble: %ld\n", stat_shorthalf, stat_shortdouble );

	printf( "stat_padbytes : %ld\n", stat_padbytes );
	printf( "Done!\n");

	fclose(ofile);
	//fclose(ifile);
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

