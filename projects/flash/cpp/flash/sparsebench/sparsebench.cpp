#include "sparsebench.h"

extern double timespec_diff_sec( timespec start, timespec end );



void loadFiles()
{
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();
	BSBFS* fs = BSBFS::getInstance();


	int fdm = fs->open("mat.tiled");
	if ( fdm < 0 ) {
		fs->createFile("mat.tiled");
		int fdm = fs->open("mat.tiled");
		uint8_t* bdb = (uint8_t*)dma->dmaBuffer();
		//memset(bdb,0xaa, 8192*256);
		
		FILE* fsparse = fopen("mat.test", "rb");
		if ( fsparse == NULL ) {
			fprintf(stderr, "file not found!\n");
		} else {
			uint32_t* frb = (uint32_t*)calloc(64,8192);
			while (!feof(fsparse) ) {
				int count = fread(frb,8192, 64, fsparse);
				if ( count > 0 ) {
					printf( "appending %d pages (%ld)\n", count, fs->files[fdm]->size );
					fflush(stdout);
					fs->fappend(fdm, frb, 8192*count);
				}
			}
			free(frb);
		}
			

		fs->storeConfig();
	}
}

void sparsebench(int accelcount, int pages, int vlen, int* vector)
{
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();
	BSBFS* fs = BSBFS::getInstance();
		

	loadFiles();
		

	uint32_t* pageBufferR = (uint32_t*)malloc(8192*2);
	
	
	bool block = true;
#ifndef BLUESIM
	block = false;
#endif
	

	printf( "Starting read\n" );
	fflush(stdout);
	
	int fd = fs->open("mat.tiled");
	fs->fseek(fd, 0, File::FSEEK_SET);


	timespec start, now;
	clock_gettime(CLOCK_REALTIME, & start);


	for ( int iter = 0; iter < 128; iter ++ ) {
		printf( "Sending init msg\n" );
		dma->sendWord(1, iter*pages*8192,pages*8192, 0, 0);

		for ( int i = 0; i < pages && !fs->feof(fd); i++ ) {
			fs->fseek(fd, i*FPAGE_SIZE, File::FSEEK_SET);
			if ( i+1 < pages ) {
				uint64_t read = fs->pread(fd, NULL, 1,1,block);
			} else {
				uint64_t read = fs->pread(fd, NULL, 1,1,true);
			}

			if ( i % 1000 == 0 ) {
				printf( "Page %d\n", i );
				//fflush(stdout);
			}
		}
		fflush(stdout);
		fs->fseek(fd, 0, File::FSEEK_SET);
		//uint64_t read = fs->pread(fd, pageBufferR, 1, 0,true);
		//usleep(100000);

	}

	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %f\n", timespec_diff_sec(start, now) );
	printf( "scan done\n" );
	fflush(stdout);

	return;


/*
	printf( "Starting vector load\n" ); fflush(stdout);
	
	for ( int i = 0; i < accelcount; i++ ) {
		if ( vlen >= 512 ) vlen = 512;
		dma->sendWord(i+1, vlen, pages, 0, 0); // tokens 5 vidx 
		for ( int j = 0; j < vlen; j++ ) {
			dma->sendWord(i+1, vector[j], 0, 0, 1); // tokens 5 vidx 
		}
	}

	printf( "Loaded vector\n" ); fflush(stdout);

	clock_gettime(CLOCK_REALTIME, & start);
	for ( int i = 0; i < pages && !fs->feof(fd); i++ ) {
		for ( int j = 0; j < accelcount; j++ ) {
			fs->fseek(fd, (i*accelcount+j)*FPAGE_SIZE, File::FSEEK_SET);
			//uint64_t read = fs->pread(fd, pageBufferR, 1, 3,block);
			uint64_t read = fs->pread(fd, NULL, 1,j+1,block);
		}

		if ( i % 1000 == 0 ) printf( "Page %d\n", i );
	}
	fs->fseek(fd, 0, File::FSEEK_SET);
	read = fs->pread(fd, pageBufferR, 1, 0,true);


	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %f\n", timespec_diff_sec(start, now) );
	printf( "scan done\n" );
	fflush(stdout);
	*/
}
