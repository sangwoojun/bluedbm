#include <stdio.h>
#include <unistd.h>

#include <string>

#include "bdbmpcie.h"
#include "flashmanager.h"
#include "dmasplitter.h"
#include "bsbfs.h"
#include "proteinbench/proteinbench.h"
#include "sparsebench/sparsebench.h"
#include "docsearch/docsearch.h"

extern double timespec_diff_sec( timespec start, timespec end );

void loadFile(char* fname) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();
	BSBFS* fs = BSBFS::getInstance();
	fs->deleteFile(fname);

	int fd = fs->open(fname);
	if ( fd < 0 ) {
		fs->createFile(fname);
		int fd = fs->open(fname);
		
		FILE* fin = fopen(fname, "rb");
		if ( fin == NULL ) {
			fprintf(stderr, "file not found!\n");
		} else {
			uint32_t* frb = (uint32_t*)calloc(128,8192);
			while (!feof(fin) ) {
				int count = fread(frb,8192, 128, fin);
				if ( count > 0 ) {
					printf( "appending %d pages (%ld)\n", count, fs->files[fd]->size );
					fflush(stdout);
					fs->fappend(fd, frb, 8192*count);
				}
			}
			free(frb);
		}
			

		fs->storeConfig();
	}
}

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
	
	uint32_t* testBuf = (uint32_t*)malloc(8192);
	for ( int i = 0; i < 8192/4; i++ ) {
		testBuf[i] = i;
	}

	char* filename = (char*)"docword.bin";
	loadFile(filename);

///////////// Document search?
	docsearch(filename);


	exit(0);
///////////// Sparse mult?
#ifdef BLUESIM
	uint64_t pages = 512; // 2*...
#else
	uint64_t pages = 4096; // 16*256Kcol*8bytes each
#endif

	int vector[128] = {123, 346, 54734, 62634, 99999,0};
	sparsebench(1, pages, 5, vector);
	//sparsebench(2, pages, 5, vector);
	exit(0);




////////// Protein search?
	if ( argc > 1 ) {
		proteinbench(argv[1]);
	} else {
		char defaultq[1024] = "VMVWLRRTTHYLFIVVVAVNSTLLTINAGDYIFYTDWAWTSFVVFSISQSTMLVVGAIYYMLFTGVPGTATYYATIMTIYTWVAKGAWFALGYPYDFIVVPVWIPSAMLLDLTYWATRRNKHAAIIIGGTLVGLSLPMFNMINLLLIRDPLEMAFKYPRPTLPPYMTPIEPQVGKFYNSPVALGSGAGAVLSVPIAALGAKLNTWTYRWMAA";

		proteinbench(defaultq );
	}
	//fs->storeConfig();
	exit(0);
}
