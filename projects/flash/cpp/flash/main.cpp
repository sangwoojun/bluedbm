#include <stdio.h>
#include <unistd.h>

#include <string>

#include "bdbmpcie.h"
#include "flashmanager.h"
#include "dmasplitter.h"
#include "bsbfs.h"
#include "proteinbench/proteinbench.h"
#include "sparsebench/sparsebench.h"

extern double timespec_diff_sec( timespec start, timespec end );

int main(int argc, char** argv) {
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

#ifdef BLUESIM
	uint64_t pages = 512; // 2*...
#else
	uint64_t pages = 4096; // 16*256Kcol*8bytes each
#endif

	int vector[128] = {123, 346, 54734, 62634, 99999,0};
	sparsebench(1, pages, 5, vector);
	//sparsebench(2, pages, 5, vector);
	exit(0);

	if ( argc > 1 ) {
		proteinbench(argv[1]);
	} else {
		char defaultq[1024] = "VMVWLRRTTHYLFIVVVAVNSTLLTINAGDYIFYTDWAWTSFVVFSISQSTMLVVGAIYYMLFTGVPGTATYYATIMTIYTWVAKGAWFALGYPYDFIVVPVWIPSAMLLDLTYWATRRNKHAAIIIGGTLVGLSLPMFNMINLLLIRDPLEMAFKYPRPTLPPYMTPIEPQVGKFYNSPVALGSGAGAVLSVPIAALGAKLNTWTYRWMAA";

		proteinbench(defaultq );
	}
	//fs->storeConfig();
	exit(0);

//#ifdef BLUESIM
	fs->createFile("mat.test");
	fs->createFile("testfile1.txt");
	fs->createFile("testfile2.txt");
//#endif
	int fdm = fs->open("mat.test");
	int fd = fs->open("testfile1.txt");
	int fd2 = fs->open("testfile2.txt");

#ifdef BLUESIM
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
#endif
				
	//dma->sendWord(2, buf[idx], buf[idx+1], buf[idx+2], buf[idx+3]);
	timespec start, now;
	bool block = true;
#ifndef BLUESIM
	block = false;
#endif
	uint32_t* pageBufferR = (uint32_t*)malloc(8192*2);
	
	/*
	while ( !fs->feof(fd) ) {
		uint64_t read = fs->pread(fd, pageBufferR, 1,0,true);
		//uint64_t read = fs->pread(fdm2, pageBufferR, 1,1,true);
		for ( int i = 0; i < 16;i++ ) {
			printf("----%x\n", pageBufferR[i]);
		}
		printf( "\n" );
	}
	printf( "scan done\n" );
	fflush(stdout);
	*/

	int fdm2 = fs->open("mat.test");
	
	clock_gettime(CLOCK_REALTIME, & start);

	fs->fseek(fdm2, 0, File::FSEEK_SET);
	//while ( !fs->feof(fdm2) ) {
	for ( int i = 0; i < pages; i++ ) {
		//uint64_t read = fs->pread(fdm2, pageBufferR, 1,0,true);
		uint64_t read = fs->pread(fdm2, NULL, 1,5,block);
	}
	clock_gettime(CLOCK_REALTIME, & now);
	printf( "Elapsed: %f\n", timespec_diff_sec(start, now) );
	printf( "scan done\n" );
	fflush(stdout);
}
