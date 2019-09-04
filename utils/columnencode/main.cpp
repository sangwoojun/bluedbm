#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

#include <cstring>

typedef enum {
	BYTE1,
	BYTE4,
	BYTE8,
	DATE,
	VARCHAR,
} ParseType;

static uint64_t varchar_alignment = 8;
static uint64_t page_alignment = 8192;

uint64_t encodeout(FILE* fout, char* str, ParseType type, uint64_t bytes) {
	switch (type) {
		case BYTE1: {
			int8_t val = atoi(str);
			fwrite(&val, sizeof(int8_t), 1, fout);
			return sizeof(int8_t);
		} break;
		case BYTE4: {
			int32_t val = atoi(str);
			fwrite(&val, sizeof(int32_t), 1, fout);
			return sizeof(int32_t);
		} break;
		case BYTE8: {
			int64_t val = strtoll(str, NULL, 0);
			fwrite(&val, sizeof(int64_t), 1, fout);
			return sizeof(int64_t);
		} break;
		case DATE: {
			struct tm dd;
			strptime(str, "%Y-%m-%d", &dd);
			uint32_t val = ((dd.tm_year&&0xffff)<<16) | ((dd.tm_mon&&0xff)<<8) | (dd.tm_mday);
			fwrite(&val, sizeof(uint32_t), 1, fout);
			return sizeof(uint32_t);
		} break;
		case VARCHAR: {
			uint8_t len = strlen(str);
			uint8_t zero = 0;

			uint64_t retbytes = 0;

			
			if ( (bytes%page_alignment) + len + 1 >= page_alignment ) {
				uint64_t page_padding = page_alignment - (bytes%page_alignment);
				uint8_t ffchar = 0xff;
				for ( uint64_t i = 0; i < page_padding; i++ ) fwrite(&ffchar, sizeof(uint8_t), 1, fout);
				retbytes += page_padding;
			}

			fwrite(str, sizeof(char), len, fout);
			fwrite(&zero, sizeof(uint8_t), 1, fout);
			retbytes += len + 1;

			if ( len+1 % varchar_alignment > 0 ) {
				uint64_t alignment_padding = varchar_alignment - ((len+1)%varchar_alignment);
				uint8_t ffchar = 0xff;
				for ( uint64_t i = 0; i < alignment_padding; i++ ) fwrite(&ffchar, sizeof(uint8_t), 1, fout);
				retbytes += alignment_padding;
			}

			return retbytes;
		}break;
	}
	
	return 0;
}

int main(int argc, char** argv) {
	// usage: columnencode filename delimiter columnidx type(1B,4B,8B,D(ate),V(archar))

	if ( argc < 5 ) {
		printf( "usage: %s filename delimiter columnidx type (1B,4B,8B,D(ate),V(archar)) [outfile]\n", argv[0] );
		exit(1);
	}

	char* filename = argv[1];
	char* delim = argv[2];
	int cidx = atoi(argv[3]);
	char typec = argv[4][0];
	char* outname = (char*)malloc(32);
	strcpy(outname, "output.dat");

	if ( argc >= 6 ) {
		outname = argv[5];
	}

	ParseType type = BYTE4;
	switch(typec) {
		case '1': type = BYTE1; break;
		case '4': type = BYTE4; break;
		case '8': type = BYTE8; break;
		case 'D': type = DATE; break;
		case 'V': type = VARCHAR; break;
	}

	FILE* fin = fopen(filename, "r");
	FILE* fout = fopen(outname, "wb");
	char buffer[512];
	uint64_t elements = 0;
	uint64_t bytes = 0;
	while (!feof(fin)) {
		if ( fgets(buffer, 512, fin) == NULL ) break;

		char* tok = strtok(buffer, delim);
		for ( int i = 0; i < cidx; i++ ) {
			tok = strtok(NULL, delim);
		}

		bytes += encodeout(fout, tok, type, bytes);
		elements ++;

	}

	printf( "Column encoding done to file %s, %ld elements, %ld bytes\n", outname, elements, bytes );

}
