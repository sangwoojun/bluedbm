#include "stdio.h"
#include "stdlib.h"
#include "unistd.h"
#include "string.h"
#include "stdint.h"
#include "math.h"
#include "time.h"

#include "pthread.h"

#include "config.h"

int main(int argc, char** argv) {
	if ( argc < 2 ) {
		printf( "usage: ./%s filename\n", argv[0] );
		exit(1);
	}

	FILE* fin = fopen(argv[1], "rb");
	uint32_t* blockbuf = (uint32_t*)malloc(block_mbs*1024*1024);
	while(!feof(fin)) {
		int res = fread(blockbuf, block_mbs*1024*1024, 1, fin);
		if ( res > 0 ) {
			uint32_t first = blockbuf[0];
			if ( first>>headeroffset != LongCol ) {
				printf( "Block does not start with LongCol! Starts with : %x\n", first>>headeroffset );
			}
			for ( uint64_t i = 0; i < block_mbs*1024*1024/4;i++ ) {
				uint32_t v = blockbuf[i];
				int header = (v>>headeroffset);
				switch(header) {
					case LongCol: 
					{
						uint64_t top = v & bodymask;
						uint64_t bot = blockbuf[i+1];
						uint64_t target = (top<<32)|bot;
						printf( "%lx\n", target );
						i++;
					}
						break;
					case LongRow: 
						i++;
						break;
					case LongData: 
						i++ ;
						break;
				}
			}
		}
	}
}
