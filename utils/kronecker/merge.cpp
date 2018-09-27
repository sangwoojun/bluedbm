#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#include <cstdio>

// returns true if a <= b
bool compare(uint64_t a[2], uint64_t b[2]) {
	if ( a[0] > b[0] ) return false;
	if ( a[0] < b[0] ) return true;
	if ( a[1] > b[1] ) return false;
	return true;
}

int main( int argc, char** argv ) {
	if ( argc < 4 ) {
		fprintf(stderr, "usage: %s filenameout filename1 filename2\n", argv[0]);
		exit(1);
	}

	FILE* fin1 = fopen(argv[2], "rb");
	FILE* fin2 = fopen(argv[3], "rb");
	FILE* fout = fopen(argv[1], "wb");

	uint64_t buf1[2];
	uint64_t buf2[2];
	if ( fread(buf1, sizeof(uint64_t)*2, 1, fin1) == 0 ) {
		fprintf(stderr, "file 1 empty\n");
		exit(1);
	}
	if ( fread(buf2, sizeof(uint64_t)*2, 1, fin2) == 0 ) {
		fprintf(stderr, "file 2 empty\n");
		exit(1);
	}

	while (1) {
		if ( compare(buf1,buf2) ) {
			fwrite(buf1,sizeof(uint64_t)*2,1,fout);
			if ( fread(buf1, sizeof(uint64_t)*2, 1, fin1) == 0 ) break;
		} else {
			fwrite(buf2,sizeof(uint64_t)*2,1,fout);
			if ( fread(buf2, sizeof(uint64_t)*2, 1, fin2) == 0 ) break;
		}
		
	}

	//either fin1 or fin2 are one

	while ( !feof(fin1) ) {
		fwrite(buf1,sizeof(uint64_t)*2,1,fout);
		if ( fread(buf1, sizeof(uint64_t)*2, 1, fin1) == 0 ) break;
	}

	while ( !feof(fin2) ) {
		fwrite(buf2,sizeof(uint64_t)*2,1,fout);
		if ( fread(buf2, sizeof(uint64_t)*2, 1, fin2) == 0 ) break;
	}

	fclose(fin1);
	fclose(fin2);
	fclose(fout);
	
	printf( "Checking final file, %s\n", argv[1] );
	
	FILE* fchin = fopen(argv[1], "rb");

	uint64_t last[2] = {0,0};

	uint64_t count = 0;
	while (!feof(fchin)) {
		uint64_t cur[2] = {0,0};
		if ( fread(cur, sizeof(uint64_t)*2, 1, fchin) == 0 ) break;

		if ( !compare(last, cur) ) {
			printf( "Sort error @ %ld (%ld %ld) > (%ld %ld)\n", count,
				last[0], last[1], cur[0], cur[1]);
		}
		last[0] = cur[0];
		last[1] = cur[1];
		count++;
	}
	printf ( "Checked %ld samples\n", count );

}
