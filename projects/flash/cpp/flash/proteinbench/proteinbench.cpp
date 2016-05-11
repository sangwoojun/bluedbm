#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"
#include "flashmanager.h"
#include "dmasplitter.h"
#include "bsbfs.h"
#include "proteinbench.h"
#include "config.h"
#include "smithwaterman.h"
std::vector<Protein*> plist;
char* query;
void proteinbench(char* query_) {
	query = query_;
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();
	BSBFS* fs = BSBFS::getInstance();

	int fd = fs->open("seqdict.bin");
	if ( fd < 0 ) {
		fs->createFile("seqdict.bin");
		fd = fs->open("seqdict.bin");

		FILE* fin = fopen("seqdict.bin", "rb");
		uint32_t* frb = (uint32_t*)calloc(64,8192);
		while (!feof(fin)
		#ifdef BLUESIM
			&& ftell(fin) <= (8192*64)
		#endif
		) {
			int count = fread(frb,8192, 64, fin);
			if ( count > 0 ) {
				printf( "appending %d pages (%ld)\n", count, fs->files[fd]->size );
				fflush(stdout);
				fs->fappend(fd, frb, 8192*count);
			}
		}
		free(frb);
		fs->storeConfig();
	}
	int* dict_idx = (int*)malloc(sizeof(int)*DICT_SIZE);
	FILE* fsel = fopen("idx.txt", "r");
	if ( !fsel ) {
		fprintf(stderr, "error: file idx.txt does not exist\n" );
		exit(1);
	}

	int len = strlen(query);
	char ibuf[256];
	int cidx = 0;
	while (!feof(fsel)) {
		char* cres = fgets(ibuf, 256, fsel);
		if ( !cres ) break;
		int idx = atoi(ibuf);

		if ( cidx >= DICT_SIZE ) {
			break;
		}

		dict_idx[cidx] = idx;
		cidx++;
	}
	fclose(fsel);
	char codemap[256] = {0,};
	for ( int i = 0; i < 256; i++ ) codemap[i] = -1;
	for ( int i = 0; i < CODE_COUNT; i++ ) {
		int idx = acidcodes[i];
		codemap[idx] = (char)i;
		//printf( "(%d %d %d)", idx, codemap[idx], idx );
	}

	int* dict_local = (int*)malloc(sizeof(int)*CODE_COUNT3);
	memset(dict_local, 0, CODE_COUNT3*sizeof(int));
	for ( int i = 0; i < len -2; i++ ) {
		char* c = query+i;
		int poff = 0;
		poff += (codemap[(int)c[0]])*CODE_COUNT*CODE_COUNT;
		poff += (codemap[(int)c[1]])*CODE_COUNT;
		poff += (codemap[(int)c[2]]);
		dict_local[poff]++;
	}
			
	char dcnt[DICT_SIZE] = {0,};
	for ( int i = 0; i < DICT_SIZE; i++ ) {
		int cidx = dict_idx[i];
		int cnt = dict_local[cidx];
		if ( cnt >= 255 ) cnt = 255;
		dcnt[i] = (char)cnt;
	}

	uint32_t* udc = (uint32_t*)dcnt;


	// set Dict size
	// insert Query
	int accelidx = 2;
	int ptype = 1; // query
	for ( int i = 0; i < DICT_SIZE/16; i++ ) {
		int header = accelidx | (ptype<<(16+8)) | (i<<16);
		dma->sendWord(header, 
			udc[i*4],
			udc[i*4+1],
			udc[i*4+2],
			udc[i*4+3]);
	}
	accelidx = 3;
	for ( int i = 0; i < DICT_SIZE/16; i++ ) {
		int header = accelidx | (ptype<<(16+8)) | (i<<16);
		dma->sendWord(header, 
			udc[i*4],
			udc[i*4+1],
			udc[i*4+2],
			udc[i*4+3]);
	}

	//read file
	fs->fseek(fd, 0, File::FSEEK_SET);
	uint32_t cnt = 0;
	while ( !fs->feof(fd) ) {
		cnt++;

		uint64_t read = fs->pread(fd, NULL, 8,cnt%1==0?2:3,false);
	}
	fs->fseek(fd, 0, File::FSEEK_SET);
	uint64_t read = fs->pread(fd, NULL, 1,3,false);
	read = fs->pread(fd, NULL, 1,2,false);

	printf( "Done!\n" );
	int pcount = plist.size();

	for ( int i = 0; i < pcount; i++ ) {
		for ( int j = i+1; j < pcount; j++ ) {
			if ( plist[i]->score < plist[j]->score ) {
				Protein* tp = plist[i];
				plist[i] = plist[j];
				plist[j] = tp;
			}
		}
	}

	printf( "Query: %s\n", query );
	for ( int i = 0; i < 10; i++ ) {
		Protein* np = plist[i];

		printf( "%s", np->desc );
		printf( "%d %s\n", np->score, np->seq );
	}

	exit(0);
}
FILE* forig = NULL;
char ibuf[1024];
char* sequence = NULL;
void detailcalc(uint64_t off) {
	if ( forig == NULL ) forig = fopen("uniprot_trembl.fasta", "r");

	fseek(forig, off, SEEK_SET);
	fgets(ibuf, 1024, forig);
	int len = strlen(ibuf);
	char* desc = (char*)malloc(sizeof(char)*len);
	strncpy(desc, ibuf, len);
	if ( sequence==NULL )sequence = (char*)malloc(sizeof(char)*MAX_SEQ);
	int seq_count = 0;


	fgets(ibuf, 1024, forig);

	while( ibuf[0] != '>' ) {
		len = strlen(ibuf);
		if ( ibuf[len-1] == '\n' ) len--; //trim
		if ( len + seq_count ) {
			strncpy(sequence+seq_count, ibuf, len);
			seq_count += len;
		}

		fgets(ibuf, 1024, forig);
	}
	char* tseq = (char*)malloc(sizeof(char)*seq_count);
	strncpy(tseq,sequence, seq_count);
	tseq[seq_count-1] = 0;

	Protein* np = new Protein();
	np->desc = desc;
	np->seq = tseq;
	np->score = smithwatermandist(query, tseq);

	plist.push_back(np);
}
