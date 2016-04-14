#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"
#include "flashmanager.h"
#include "dmasplitter.h"
#include "bsbfs.h"

extern double timespec_diff_sec( timespec start, timespec end );

int main() {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();

	void* dmabuffer = pcie->dmaBuffer();
	unsigned int* ubuf = (unsigned int*)dmabuffer;

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	printf( "All Init Done\n" );
	fflush(stdout);

	BSBFS* fs = BSBFS::getInstance();
	//fs->startEraser();
	fs->fileList();
	
	uint32_t* testBuf = (uint32_t*)malloc(8192);
	for ( int i = 0; i < 8192/4; i++ ) {
		testBuf[i] = i;
	}

//#ifdef BLUESIM
	fs->createFile("mat.test");
	fs->createFile("testfile1.txt");
	fs->createFile("testfile2.txt");
//#endif
	int fdm = fs->open("mat.test");
	int fd = fs->open("testfile1.txt");
	int fd2 = fs->open("testfile2.txt");

#ifdef BLUESIM
	FILE* fsparse = fopen("mat.test", "rb");
	if ( fsparse == NULL ) {
		fprintf(stderr, "file not found!\n");
	} else {
		uint32_t* frb = (uint32_t*)calloc(64,8192);
		while (!feof(fsparse) ) {
			int count = fread(frb,8192, 64, fsparse);
			if ( count > 0 ) {
				fs->fappend(fdm, frb, 8192*count);
				printf( "appending %d pages (%ld)\n", count, fs->files[fdm]->size );
			}
		}
		free(frb);
	}

	for ( int i = 0; i < 64; i++ ) {
		for ( int j = 0; j < 8192/4;j++ ) {
			testBuf[j] = i+j;
		}
		testBuf[0] = 0xdeadbeef;
		testBuf[8192/4-1] = 0xf00dd00d;

		//printf( "%d--\n", i ); fflush(stdout);
		fs->fappend(fd, testBuf, 8192);

		//if ( i % 100 == 0 ) fs->fileList();
	}

	fs->storeConfig();
#endif
				
	//dma->sendWord(2, buf[idx], buf[idx+1], buf[idx+2], buf[idx+3]);
#ifdef BLUESIM
	int pages = 32;
#else
	int pages = 4*1024*1024/8;
#endif
	dma->sendWord(2, 5, pages, 0, 0); // tokens 5 vidx 32 pages
	dma->sendWord(2, 1105, 0, 0, 1); // tokens 5 vidx 32 pages
	dma->sendWord(2, 8682, 0, 0, 1); // tokens 5 vidx 32 pages
	dma->sendWord(2, 9281, 0, 0, 1); // tokens 5 vidx 32 pages
	dma->sendWord(2, 9514, 0, 0, 1); // tokens 5 vidx 32 pages
	dma->sendWord(2, 11751, 0, 0, 1); // tokens 5 vidx 32 pages

	fs->fileList();
	int fdm2 = fs->open("mat.test");

	FILE* fread = fopen("fread.dat", "wb");

	fflush(stdout);

	timespec start, now;
	clock_gettime(CLOCK_REALTIME, & start);
	uint32_t* pageBufferR = (uint32_t*)malloc(8192*2);
	bool block = true;
#ifndef BLUESIM
	block = false;
#endif
	for ( int i = 0; i < pages && !fs->feof(fdm2); i++ ) {
		uint64_t read = fs->pread(fdm2, NULL, 1,/*target*/1,block);

		if ( i % 1000 == 0 ) printf( "Page %d\n", i );
	}
	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %f\n", timespec_diff_sec(start, now) );
	printf( "scan done\n" );
	fflush(stdout);
	fclose(fread);
	
	dma->sendWord(2, 5, pages, 0, 0); // tokens 5 vidx 32 pages
	dma->sendWord(2, 1105, 0, 0, 1); // tokens 5 vidx 32 pages
	dma->sendWord(2, 8682, 0, 0, 1); // tokens 5 vidx 32 pages
	dma->sendWord(2, 9281, 0, 0, 1); // tokens 5 vidx 32 pages
	dma->sendWord(2, 9514, 0, 0, 1); // tokens 5 vidx 32 pages
	dma->sendWord(2, 11751, 0, 0, 1); // tokens 5 vidx 32 pages

	fs->fseek(fdm2, 0, File::FSEEK_SET);
	//while ( !fs->feof(fdm2) ) {
	for ( int i = 0; i < pages; i++ ) {
		//uint64_t read = fs->pread(fdm2, pageBufferR, 1,0,true);
		uint64_t read = fs->pread(fdm2, NULL, 1,1,true);
	}
	printf( "scan done\n" );
	fflush(stdout);

	exit(0);

	FILE* fread1 = fopen("fread1.dat", "wb");
	while ( !fs->feof(fd) ) {
		uint64_t read = fs->pread(fd, pageBufferR, 1,0,true);
		//uint64_t read = fs->pread(fdm2, pageBufferR, 1,1,true);
		fwrite(pageBufferR, FPAGE_SIZE, 1, fread1);
		/*
		for ( int i = 0; i < 16;i++ ) {
			printf("----%x\n", pageBufferR[i]);
		}
		*/
	}
	fclose(fread1);
	exit(0);


	uint32_t* pageBufferR0 = (uint32_t*)malloc(8192+32);
/*
	fs->fappend(fd, testBuf, 128);
	fs->fappend(fd, testBuf, 8192);
	for ( int i = 0; i < 64; i++ ) {
		printf( "%d--\n", i ); fflush(stdout);
		fs->fappend(fd, testBuf, 8192);

		//if ( i % 100 == 0 ) fs->fileList();
	}
	*/



/*
	for ( int i = 0; i < 16; i++ ) {
		uint8_t s = 0;
		flash->eraseBlock(i,1,1, &s);
		while (s == 0 ) usleep(100);
	}
	printf( "Erase done!\n" ); fflush(stdout);

	uint32_t* pageBufferW = (uint32_t*)malloc(8192);
	for ( int i = 0; i < 16; i++ ) {
		for( int j = 0; j < 8192/4; j++ ) {
			pageBufferW[j] = i;
		}
		uint8_t s = 0;
		flash->writePage(i, 1,1,0,pageBufferW,&s);
		while (s == 0 ) usleep(100);
	}
	printf( "Write done!\n" ); fflush(stdout);

	
	for ( int i = 0; i < 16; i++ ) {
		uint8_t s = 0;
		flash->readPage(i,1,1,0, pageBufferR0, &s);
		while ( s == 0 ) usleep(100);

		for ( int j = 0; j < 8192/4; j++ ) {
			if ( pageBufferR0[j] != i ) {
				printf ( "%d %d != %d\n", j, i, pageBufferR0[j] );
			}
		}
	}
	*/

	uint8_t stat = 0;
	//int rcount = 256;
	int rcount = 1024*1024/2;
	for ( int i = 0; i < rcount; i++ ) {
		int bus = (i % 16);

		int chip = (i>>4) & 0x7;
		int block = (i>>7) & 0xfff;
		int page = (i>>19);
#ifdef BSIM	
		block = (block % 128);
		page = page % 16;
#endif
		if ( i % (1024*8) == 1 ) {
			printf( "sending req %d\n", i ); fflush(stdout);
		}
		//if ( bus == 1 && chip == 1 && block == 1 && page == 0 ) {
			flash->readPage(bus,chip,block,page, pageBufferR0, 0, &stat);
		//} else {
		//	flash->readPage(bus,chip,block,page, pageBufferR, &stat);
		//}
	}
	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %f\n", timespec_diff_sec(start, now) );

	sleep(1);
	for ( int i = 0; i < TAG_COUNT; i++ ) {
		if ( flash->tagBusy[i] ) printf( "tag %d still busy!!\n", i );
	}
	for ( int i = 0; i < 3; i++ ) {
		sleep(1);
		fflush(stdout);
	}

	exit(0);

	/*
	uint32_t* pageBufferW = (uint32_t*)malloc(8192+32);
	for ( int i = 0; i < 8192/4; i++ ) {
		pageBufferW[i] = i;
	}
	printf( "Sending erase message:\n" );
	flash->eraseBlock(1,1,1);
	sleep(1);
	printf( "Sending write message:\n" );
	flash->writePage(1,1,1,0, pageBufferW);

*/
/*
	printf( "\t\tSending read cmd\n" ); fflush(stdout);
	sleep (2);
	
	//flash->readPage(1,1,1,0, pageBufferR0);

	timespec start, now;
	clock_gettime(CLOCK_REALTIME, & start);
	//int rcount = 10;
	int rcount = (1024*1024)/8;
	for ( int i = 0; i < rcount; i++ ) {
		int bus = i & 0x7;
		int chip = (i>>3) &0x7;
		int block = (i>>6) & 0xfff;
		int page = (i>>18);
#ifdef BSIM	
		block = (block % 128);
		page = page % 16;
#endif
		if ( bus == 1 && chip == 1 && block == 1 && page == 0 ) {
			//flash->readPage(bus,chip,block,page, pageBufferR0);
		} else {
			//flash->readPage(bus,chip,block,page, pageBufferR);
		}
	}
	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %f\n", timespec_diff_sec(start, now) );
	*/
	/*
	for ( int i = 0; i < 16; i++ ) {
		flash->readPage(1,1,1,i, pageBufferR);
	}
	*/

	sleep (2);

	for ( int i = 0; i < 32; i++ ) {
		printf( "%x ", pageBufferR0[i] );
	}

}
