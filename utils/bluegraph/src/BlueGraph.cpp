#include "BlueGraph.h"
#include "Sorters.h"

#include "sssp.h"
#include "bfs.h"

#include <pthread.h>

#include <cstdio>

ReducerWriter::ReducerWriter(std::string filename, BgUserProgramType prog, BgKeyType keyType, BgValType valType) {
	this->prog = prog;
	this->fout = fopen(filename.c_str(), "wb");
	this->keyType = keyType;
	this->valType = valType;
	this->lastValid = false;
	this->writecnt = 0;

	checklast = 0;
}

ReducerWriter::~ReducerWriter() {
	fclose(fout);
}
void 
ReducerWriter::RawWrite(uint64_t key, uint64_t val) {
	if ( checklast > key ) {
		printf( "Warning: lastKey > key!! %lx > %lx %ld\n", checklast, key, writecnt );
	}
	checklast = key;
	if ( keyType == BGKEY_BINARY32 ) {
		uint32_t skey = (uint32_t)key;
		fwrite(&skey, sizeof(uint32_t), 1, fout);
	} else if ( keyType == BGKEY_BINARY64 ) {
		fwrite(&key, sizeof(uint64_t), 1, fout);
	}

	if ( valType == BGVAL_BINARY32 ) {
		uint32_t sval = (uint32_t)val;
		fwrite(&sval, sizeof(uint32_t), 1, fout);
	} else if ( valType == BGVAL_BINARY64 ) {
		fwrite(&val, sizeof(uint64_t), 1, fout);
	}

	writecnt++;
}
void 
ReducerWriter::Finish() {
	if ( lastValid == false ) return;

	this->RawWrite(lastKey,lastVal);
	lastValid = false;
}


void 
ReducerWriter::ReduceWrite(uint64_t key, uint64_t val, bool last) {

	BlueGraph* bgraph = BlueGraph::getInstance();
	if ( last == true ) {
		if ( lastValid ) {
			if ( key == lastKey ) {
				uint64_t vr = bgraph->VertexProgram(val, lastVal, prog);
				this->RawWrite(key, vr);
			} else {
				this->RawWrite(lastKey,lastVal);
				this->RawWrite(key,val);
			}
		} else {
			this->RawWrite(key,val);
		}
		return;
	}

	if ( ! lastValid ) {
		lastKey = key;
		lastVal = val;
		lastValid = true;
		return;
	}


	if ( lastKey == key ) {
		uint64_t vr = bgraph->VertexProgram(val, lastVal, prog);
		lastVal = vr;
		return;
	}
	
	

	this->RawWrite(lastKey,lastVal);
	lastKey = key;
	lastVal = val;
}

void
ReducerWriter::ReduceWriteBlock(uint8_t* buffer, int count){
	printf( "ReduceWriteBlock %d\n", count );
	int keysize = 0;
	int valsize = 0;
	if ( keyType == BGKEY_BINARY32 ) keysize+=4;
	if ( keyType == BGKEY_BINARY64 ) keysize+=8;
	if ( valType == BGVAL_BINARY32 ) valsize+=4;
	if ( valType == BGVAL_BINARY64 ) valsize+=8;
	int objsize = keysize + valsize;

	for ( int i = 0; i < count; i++) {
		int off = objsize*i;
		uint64_t key = 0;
		if ( keyType == BGKEY_BINARY32 ) key = *((uint32_t*)(buffer+off));
		if ( keyType == BGKEY_BINARY64 ) key = *((uint64_t*)(buffer+off));
		uint64_t val = 0;
		if ( valType == BGVAL_BINARY32 ) val = *((uint32_t*)(buffer+off+keysize));
		if ( valType == BGVAL_BINARY64 ) val = *((uint64_t*)(buffer+off+keysize));

		//if ( i == 0 ) printf( "First pair of ReduceWriteBlock %lx %lx\n", key, val );

		this->ReduceWrite(key, val, i>=(count-1));
	}
}

static void* block_sorter_worker(void *arg) 
{
	struct block_sorter_worker_info* info = (struct block_sorter_worker_info*)arg;
	
	uint8_t* tbuf = info->tbuf;

	if ( info->keyType == BGKEY_BINARY32 ) {
		if ( info->valType == BGVAL_NONE ) {
			//TODO
		} else if ( info->valType == BGVAL_BINARY32 ) {
			int objcount = info->objcount; 
			quick_sort_block<uint32_t,uint32_t>(tbuf,objcount);
			if ( !check_sorted<uint32_t,uint32_t>(tbuf,objcount) ) {
				printf( "Error : block sorter failed\n" );
			}
		} else if ( info->valType == BGVAL_BINARY64 ) {
			int objcount = info->objcount; 
			quick_sort_block<uint32_t,uint64_t>(tbuf,objcount);
			if ( !check_sorted<uint32_t,uint64_t>(tbuf,objcount) ) {
				printf( "Error : block sorter failed\n" );
			}
		} else {
			printf( "Error: invalid value type to block sorter\n" );
		}
	} else if ( info->keyType == BGKEY_BINARY64 ) {
		if ( info->valType == BGVAL_NONE ) {
			//TODO
		} else if ( info->valType == BGVAL_BINARY32 ) {
			int objcount = info->objcount; 
			quick_sort_block<uint64_t,uint32_t>(tbuf,objcount);
			if ( !check_sorted<uint64_t,uint32_t>(tbuf,objcount) ) {
				printf( "Error : block sorter failed\n" );
			}
		} else if ( info->valType == BGVAL_BINARY64 ) {
			int objcount = info->objcount; 
			quick_sort_block<uint64_t,uint64_t>(tbuf,objcount);
			if ( !check_sorted<uint64_t,uint64_t>(tbuf,objcount) ) {
				printf( "Error : block sorter failed\n" );
			}
		} else {
			printf( "Error: invalid value type to block sorter\n" );
		}
	} else {
		printf( "Error: invalid key type to block sorter\n" );
	}

	return NULL;
}


/////////////////BgEdgeList

BgEdgeList::BgEdgeList(std::string idxname, std::string matname, BgKeyType keytype) {
	this->readBuffer.valid = false;
	this->fidx = fopen(idxname.c_str(), "rb");
	this->fmat = fopen(matname.c_str(), "rb");
	this->keyType = keytype;
	this->matrixFileOffset = 0;
	this->stat_lastpage = 0xffffffffffffffff;
	this->stat_readpagecnt=0;

	fseek(fidx,0,SEEK_END);
	uint64_t idxfsz = ftell(fidx);
	this->vertexCount = idxfsz/sizeof(uint64_t);
	fseek(fidx,0,SEEK_SET);
	
	fseek(fmat,0,SEEK_END);
	this->edgeSz = ftell(fmat);
	
	fseek(fmat,0,SEEK_SET);

	if ( this->fidx == NULL ) {
		fprintf(stderr, "Error: BgEdgeList initialization failed. Cannot load %s\n", idxname.c_str() );
	}
	if ( this->fmat == NULL ) {
		fprintf(stderr, "Error: BgEdgeList initialization failed. Cannot load %s\n", matname.c_str() );
	}
}

bool
BgEdgeList::LoadOutEdges(uint64_t key) {
	readBuffer.valid = false;
	if ( this->fidx == NULL ) return false;
	uint64_t koff = key*sizeof(uint64_t);
	fseek(fidx, koff, SEEK_SET);
	uint64_t trv[2];
	int r = fread(trv, sizeof(uint64_t), 2, fidx);
	if ( r == 0 ) return false;
	matrixFileOffset = trv[0];
	matrixReadLimit = trv[1];
	if ( r == 1 ) {
		matrixReadLimit = this->edgeSz;
	}
	matrixCurOffset = matrixFileOffset;

	matrixReadEdgeCount = matrixReadLimit - matrixFileOffset;
	if ( keyType == BGKEY_BINARY32 ) matrixReadEdgeCount /= sizeof(uint32_t);
	if ( keyType == BGKEY_BINARY64 ) matrixReadEdgeCount /= sizeof(uint64_t);

	uint64_t startpage = (matrixFileOffset>>13);
	uint64_t endpage = (matrixReadLimit>>13);
	if ( stat_lastpage != 0xffffffffffffffff && startpage <= stat_lastpage ) startpage = stat_lastpage+1;
	uint64_t pagereadcnt = endpage-startpage+1;
	//printf( "read %ld pages, %ld edges\n",pagereadcnt, matrixReadEdgeCount );
	stat_readpagecnt+=pagereadcnt;
	stat_lastpage = endpage;

	if ( matrixFileOffset == matrixReadLimit ) return false;

	//printf ( "reading edges for key %ld, %lx-%lx\n", key, matrixFileOffset, matrixReadLimit );
	return true;
}

bool
BgEdgeList::HasNext() {
	if ( feof(fmat) ) return false;

	if ( readBuffer.valid ) return true;

	BgKvPair kvp = this->LoadNext();
	readBuffer = kvp;

	return kvp.valid;
}

BgKvPair
BgEdgeList::GetNext() {
	if ( readBuffer.valid ) {
		BgKvPair kvp = readBuffer;
		readBuffer.valid = false;
		return kvp;
	}

	return this->LoadNext();
}

BgKvPair
BgEdgeList::LoadNext() {
	BgKvPair kvp = {false, 0,0};
	if ( fmat == NULL ) return kvp;

	if ( matrixCurOffset >= matrixReadLimit ) return kvp;

	fseek(fmat, matrixCurOffset, SEEK_SET);

	switch (keyType) {
		case BGKEY_BINARY32: {
			uint32_t trv;
			int r = fread(&trv, sizeof(uint32_t), 1, fmat);
			if ( r == 1 ) {
				kvp.valid = true;
				kvp.key = trv; kvp.value=1;
				matrixCurOffset += sizeof(uint32_t);
			}
			break;
		}
		case BGKEY_BINARY64: {
			uint64_t trv;
			int r = fread(&trv, sizeof(uint64_t), 1, fmat);
			if ( r == 1 ) {
				kvp.valid = true;
				kvp.key = trv; kvp.value=1;
				matrixCurOffset += sizeof(uint64_t);
			}
			break;
		}
	}
	return kvp;
}

/////////////////BlueGraph

BlueGraph* BlueGraph::m_pInstance = NULL;
BlueGraph* BlueGraph::getInstance() {
	if ( m_pInstance == NULL ) {
		m_pInstance = new BlueGraph();
	}

	return m_pInstance;
}

BlueGraph::BlueGraph() {
	vectorGenIdx = 0;
}


BgEdgeList*
BlueGraph::LoadEdges(std::string idxname, std::string matname, BgKeyType keyType) {
	BgEdgeList* el = new BgEdgeList(idxname, matname, keyType);

	return el;
}

BgVertexList*
BlueGraph::LoadVertices(std::string name, BgKeyType keyType, BgValType valType) {
	BgVertexListFile* vl = new BgVertexListFile(keyType, valType);
	vl->OpenFile(name);
	return vl;
}
	
uint64_t 
BlueGraph::EdgeProgram(uint64_t vertexValue, uint64_t edgeValue, BgUserProgramType userProg) {
	switch(userProg) {
		case(BGUSERPROG_SSSP): {
			return BgUserSSSP::EdgeProgram(vertexValue, edgeValue);
			break;
		}
		case(BGUSERPROG_BFS): {
			return BgUserBFS::EdgeProgram(vertexValue, edgeValue);
			break;
		}
		default:
			return 0;
	}
}
uint64_t 
BlueGraph::VertexProgram(uint64_t vertexValue1, uint64_t vertexValue2, BgUserProgramType userProg) {
	switch(userProg) {
		case(BGUSERPROG_SSSP): {
			return BgUserSSSP::VertexProgram(vertexValue1, vertexValue2);
			break;
		}
		case(BGUSERPROG_BFS): {
			return BgUserBFS::VertexProgram(vertexValue1, vertexValue2);
			break;
		}
		default:
			return vertexValue1;
	}
}

bool
BlueGraph::Converged(uint64_t vertexValue1, uint64_t vertexValue2, BgUserProgramType userProg) {
	switch(userProg) {
		case(BGUSERPROG_SSSP): {
			return BgUserSSSP::Converged(vertexValue1, vertexValue2);
			break;
		}
		case(BGUSERPROG_BFS): {
			return BgUserBFS::Converged(vertexValue1, vertexValue2);
			break;
		}
		default:
			return vertexValue1;
	}
}

BgVertexList* 
BlueGraph::Execute(BgEdgeList* el, BgVertexList* vl, std::string newVertexListName, BgUserProgramType userProg, BgKeyType targetKeyType, BgValType targetValType, bool edgeCountArg) {

	el->StatNewIter();

	printf( "Starting execution\n"  ); fflush(stdout);

	ftmp = fopen("ftmp.dat", "wb+");
	if ( ftmp == NULL ) {
		fprintf(stderr, "Error: BlueGraph:Execute failed. Cannot open temporary file\n" );
		return NULL;
	}

	uint64_t initlogcount = 0;

	// Generate read-modify-write list from edge program
	vl->Rewind();
	while ( vl->HasNext() ) {
		BgKvPair kv = vl->GetNext();
		if ( kv.valid == false ) break; // Just to be safe

		//printf( "active vertex %ld %ld\n", kv.key, kv.value );

		if ( !el->LoadOutEdges(kv.key) ) continue;

		while (el->HasNext()) {
			BgKvPair edge = el->GetNext();
			if ( edge.valid == false ) break;


			uint64_t edgeres = EdgeProgram(kv.value, edgeCountArg?el->matrixReadEdgeCount:edge.value, userProg);
			switch (targetKeyType) {
				case BGKEY_BINARY32: {
					fwrite(&edge.key, sizeof(uint32_t), 1, ftmp);
					break;
				}
				case BGKEY_BINARY64: {
					fwrite(&edge.key, sizeof(uint64_t), 1, ftmp);
					break;
				}
			}
			switch(targetValType) {
				case BGVAL_NONE: break;
				case BGVAL_BINARY32: {
					 fwrite(&edgeres, sizeof(uint32_t), 1, ftmp);
					 break;
				}
				case BGVAL_BINARY64: {
					 fwrite(&edgeres, sizeof(uint64_t), 1, ftmp);
					 break;
				}
			}
			initlogcount ++;
		}
	}

	//TODO pad 8KB!
	// Maybe pad 512MB
	// def pad 512MB
	// TODO may not be aligned to 512!!

	// Sort edge read-modify-write list while reducing
	printf( "STAT Finished generating edge log %ld\n", initlogcount );
	printf( "STAT edge log generation page read: %ld\n", el->stat_readpagecnt );
	int mergedBlockCount = PageSort(targetKeyType, targetValType, userProg);
	fclose(ftmp);
	std::remove("ftmp.dat");

	if ( mergedBlockCount == 1 ) {
		while(!std::rename("sort_00_0000.dat", newVertexListName.c_str()));
		BgVertexList* rv = this->LoadVertices(newVertexListName.c_str(),targetKeyType,targetValType);
		printf( "Reduction done! Finishing Execution\n" ); fflush(stdout);
		return rv;
	}

	int externalMergeStage = 0;
	while (mergedBlockCount > 1 ) {
		mergedBlockCount = MergeSort16(targetKeyType, targetValType, userProg, externalMergeStage, mergedBlockCount);
		externalMergeStage++;
	}

	if ( initlogcount > 0 ) {
		char outfilename[128];
		sprintf(outfilename, "sort_%02d_0000.dat",externalMergeStage);
		while (!std::rename(outfilename, newVertexListName.c_str()));
		BgVertexList* rv = this->LoadVertices(newVertexListName.c_str(),targetKeyType,targetValType);
		printf( "Reduction done! Finishing Execution\n" ); fflush(stdout);
		return rv;
	}

	//MergeSort
	BgVertexList* rv = (BgVertexList*)(new BgVertexListInMem(targetKeyType, targetValType));
	return rv;
}

int
BlueGraph::PageSort(BgKeyType keyType, BgValType valType, BgUserProgramType prog) {
	if ( ftmp == NULL ) return 0;
	fseek(ftmp, 0, SEEK_SET);

	int itemsz = sizeof(BgKeyType)+sizeof(BgValType);
	int cntinword = 32/itemsz;
	int wordinblk = 512*1024*1024/32;

	int cntinblk = wordinblk*cntinword;
	int bytesinblk = cntinword*itemsz;

	struct block_sorter_worker_info* ainfo = (struct block_sorter_worker_info*)calloc(SORTER_THREAD_COUNT, sizeof(struct block_sorter_worker_info));
	int spawn_tid = 0;
	bool thread_working[SORTER_THREAD_COUNT];
	for ( int i = 0; i < SORTER_THREAD_COUNT; i++ ) thread_working[i] = false;

	//FILE* ftmp1 = fopen("ftmp1.dat", "wb");

	int blockidx = 0;
	char outfilename[128];

	uint64_t sortedblocks = 0;

	while ( !feof(ftmp) ) {
		uint8_t* tbuf = (uint8_t*)calloc(itemsz,cntinblk);
		int objcount = fread(tbuf, itemsz, cntinblk, ftmp);
		if ( objcount == 0 ) break;

		if ( thread_working[spawn_tid] == true ) {
			void* res;
			pthread_join(ainfo[spawn_tid].tid, &res);
			thread_working[spawn_tid] = false;
			//fwrite(ainfo[spawn_tid].tbuf, itemsz, ainfo[spawn_tid].objcount, ftmp1);

			sprintf(outfilename, "sort_00_%04d.dat", blockidx);
			ReducerWriter* writer = new ReducerWriter(outfilename, prog, keyType, valType);
			writer->ReduceWriteBlock(ainfo[spawn_tid].tbuf, ainfo[spawn_tid].objcount);
			delete writer;
			blockidx++;

			free(ainfo[spawn_tid].tbuf);
			sortedblocks++;

			printf( "Block sort finished by thread %d\n", spawn_tid );
		}
			
		ainfo[spawn_tid].tbuf = tbuf;
		ainfo[spawn_tid].objcount = objcount;
		ainfo[spawn_tid].keyType = keyType;
		ainfo[spawn_tid].valType = valType;
		
		printf( "Starting thread to sort block\n" );
		thread_working[spawn_tid] = true;
		pthread_create(&ainfo[spawn_tid].tid, NULL, &block_sorter_worker, &ainfo[spawn_tid]);
		
		if ( objcount < bytesinblk ) break;

		spawn_tid = (spawn_tid+1)%SORTER_THREAD_COUNT;
	}

	for ( int i = 0; i < SORTER_THREAD_COUNT; i++ ) {
		if ( ! thread_working[i] ) continue;

		void* res;
		pthread_join(ainfo[i].tid, &res);
		//fwrite(ainfo[i].tbuf, itemsz, ainfo[i].objcount, ftmp1);
		//writer->ReduceWriteBlock(ainfo[i].tbuf, ainfo[i].objcount);

		sprintf(outfilename, "sort_00_%04d.dat", blockidx);
		ReducerWriter* writer = new ReducerWriter(outfilename, prog, keyType, valType);
		writer->ReduceWriteBlock(ainfo[i].tbuf, ainfo[i].objcount);
		delete writer;
		blockidx++;

		free(ainfo[i].tbuf);
		sortedblocks++;
		thread_working[i] = false;
		printf( "Block sort finished by thread %d\n", i );
	}

	printf( "STAT sorted-blocks: %ld\n", sortedblocks );
	return blockidx;
	//fclose(ftmp1);
	//delete writer;

	//return writer->writecnt;

	//close and delete ftmp.dat after done
}


int
BlueGraph::MergeSort16(BgKeyType keyType, BgValType valType, BgUserProgramType prog, int stage, int blockCnt) {
	char outfilename[128];
	char infilename[128];

	int resBlockCount = (blockCnt+16-1)/16; //ceiling round up

	int keysz = 0;
	if ( keyType == BGKEY_BINARY32 ) keysz = 4;
	if ( keyType == BGKEY_BINARY64 ) keysz = 8;
	int valsz = 0;
	if ( valType == BGVAL_BINARY32 ) valsz = 4;
	if ( valType == BGVAL_BINARY64 ) valsz = 8;
	//int objsz = keysz + valsz;

	uint64_t readkbp = 0;
	uint64_t writekbp = 0;

	for ( int i = 0; i < resBlockCount; i++ ){
		FILE* fins[16];
		sprintf(outfilename, "sort_%02d_%04d.dat",stage+1, i);

		uint64_t keys[16];
		uint64_t vals[16];
		bool valids[16];
		for ( int j = 0; j < 16; j++ ) {
			fins[j] = NULL;
			valids[j] = false;
			keys[j] = 0;
			vals[j] = 0;
		}

		//FILE* fout = fopen(outfilename, "wb");
		ReducerWriter* writer = new ReducerWriter(outfilename, prog, keyType, valType);
		printf( "External merger creating file %s\n", outfilename );
		for ( int j = 0; j < 16; j++ ) {
			int bidx = i*16 + j;
			if ( bidx >= blockCnt ) break;

			sprintf(infilename, "sort_%02d_%04d.dat",stage, bidx);
			fins[j] = fopen(infilename, "rb");
			if ( fins[j] == NULL ) printf( "FAILED TO OPEN %s\n", infilename );
		}

		uint64_t lastkey = 0;

		while(true) {
			for ( int j = 0; j < 16; j++ ) {
				if (fins[j] == NULL) continue;
				if (feof(fins[j])) continue;
				if ( valids[j] ) continue;

			
				int r = fread(&keys[j], keysz, 1, fins[j]);
				r += fread(&vals[j], valsz, 1, fins[j]);
				if ( r == 2 ) {
					valids[j] = true;
					readkbp++;
				}
			}

			bool exist = false;
			uint64_t minkey = 0xffffffffffffffff;
			int minloc = 0;
			for ( int j = 0; j < 16; j++ ) {
				if ( valids[j] == false ) continue;
				if ( minkey > keys[j] ) {
					minkey = keys[j];
					minloc = j;
				}
				exist = true;
			}

			if ( exist == false ) {
				break;
			}

			if ( lastkey > keys[minloc] ) {
				printf( "Merge sort error!! %lx %lx\n", lastkey, keys[minloc] );
			} else {
				lastkey = keys[minloc];
			}

			writer->ReduceWrite(keys[minloc], vals[minloc], false);
			valids[minloc] = false;
			writekbp ++;
		}
		for ( int j = 0; j < 16; j++ ) {
			int bidx = i*16 + j;
			if ( bidx >= blockCnt ) break;

			sprintf(infilename, "sort_%02d_%04d.dat",stage, bidx);
			std::remove(infilename);
		}
		writer->Finish();
		delete writer;
	}
	printf( "STAT merge-sort stage %d into %d %ld -> %ld\n", stage, resBlockCount, readkbp, writekbp );

	return resBlockCount;
}



BgVertexList* 
BlueGraph::VectorDiff(BgVertexList* from, BgVertexList* term, std::string fname) {
	if ( from->keyType != term->keyType ) return NULL;
	if ( from->valType != term->valType ) return NULL;

	BgKeyType keyType = from->keyType;
	BgValType valType = from->valType;

	const char* strfname = fname.c_str();
	char genfname[128];
	if ( fname == "" ) {
		sprintf(genfname, "tempvec%04d.dat", vectorGenIdx);
		vectorGenIdx++;
		strfname = genfname;
	}

	uint64_t readcnt = 0;
	from->Rewind();
	term->Rewind();
	ReducerWriter* writer = new ReducerWriter(strfname, BGUSERPROG_NULL, keyType, valType);
	while (from->HasNext() ) {
		BgKvPair kv = from->GetNext();
		readcnt++;
		if ( kv.valid == false ) break; // Just to be safe
		
		bool exist = false;
		while ( term->HasNext() ) {
			BgKvPair kvt = term->PeekNext();
			if ( kvt.valid == false ) break;

			if ( kv.key == kvt.key ) {
				exist = true;
				term->GetNext();
				readcnt++;
				break;
			}
			if ( kv.key < kvt.key ) {
				break;
			}
			term->GetNext();
			readcnt++;
		}

		if ( exist ) {
			continue;
		}

		writer->ReduceWrite(kv.key, kv.value, false);
	}
	writer->Finish();
	printf( "STAT VectorDiff write %ld pairs read %ld pairs\n", writer->writecnt, readcnt );
	delete writer;


	BgVertexList* rv = this->LoadVertices(strfname,keyType,valType);
	return rv;
}

BgVertexList* 
BlueGraph::VectorUnion(BgVertexList* from, BgVertexList* term, BgUserProgramType prog, std::string fname) {
	if ( from->keyType != term->keyType ) return NULL;
	if ( from->valType != term->valType ) return NULL;

	BgKeyType keyType = from->keyType;
	BgValType valType = from->valType;

	const char* strfname = fname.c_str();
	char genfname[128];
	if ( fname == "" ) {
		sprintf(genfname, "tempvec%04d.dat", vectorGenIdx);
		vectorGenIdx++;
		strfname = genfname;
	}

	uint64_t readcnt = 0;
	from->Rewind();
	term->Rewind();
	ReducerWriter* writer = new ReducerWriter(strfname, prog, keyType, valType);
	while (from->HasNext() ) {
		BgKvPair kv = from->GetNext();
		readcnt++;
		if ( kv.valid == false ) break; // Just to be safe
		
		while ( term->HasNext() ) {
			BgKvPair kvt = term->PeekNext();
			if ( kvt.valid == false ) break;

			if ( kv.key >= kvt.key ) {
				writer->ReduceWrite(kvt.key, kvt.value, false);
				term->GetNext();
				readcnt++;
				continue;
			}
			if ( kv.key < kvt.key ) {
				break;
			}
		}

		writer->ReduceWrite(kv.key, kv.value, false);
	}
	while ( term->HasNext() ) {
		BgKvPair kvt = term->GetNext();
		readcnt++;
		if ( kvt.valid == false ) break;
		writer->ReduceWrite(kvt.key, kvt.value, false);
	}

	writer->Finish();
	printf( "STAT VectorUnion write %ld pairs read %ld pairs\n", writer->writecnt, readcnt );
	delete writer;
	BgVertexList* rv = this->LoadVertices(strfname,keyType,valType);
	return rv;
}

BgVertexList* 
BlueGraph::VectorConverged(BgVertexList* from, BgVertexList* term, BgUserProgramType prog, std::string fname) {
	if ( from->keyType != term->keyType ) return NULL;
	if ( from->valType != term->valType ) return NULL;

	BgKeyType keyType = from->keyType;
	BgValType valType = from->valType;

	const char* strfname = fname.c_str();
	char genfname[128];
	if ( fname == "" ) {
		sprintf(genfname, "tempvec%04d.dat", vectorGenIdx);
		vectorGenIdx++;
		strfname = genfname;
	}

	uint64_t readcnt = 0;

	from->Rewind();
	term->Rewind();
	ReducerWriter* writer = new ReducerWriter(strfname, prog, keyType, valType);
	while (from->HasNext() ) {
		BgKvPair kv = from->GetNext();
		readcnt++;
		if ( kv.valid == false ) break; // Just to be safe
		
		bool exist = false;
		uint64_t existVal = 0;
		while ( term->HasNext() ) {
			BgKvPair kvt = term->PeekNext();
			if ( kvt.valid == false ) break;

			if ( kv.key == kvt.key ) {
				exist = true;
				existVal = kvt.value;
				term->GetNext();
				readcnt++;
				break;
			}
			if ( kv.key < kvt.key ) {
				break;
			}
			term->GetNext();
			readcnt++;
		}

		if ( exist ) {
			if ( !Converged(kv.value,existVal, prog) ) {
				writer->ReduceWrite(kv.key, kv.value, false);
			}
			continue;
		}

		writer->ReduceWrite(kv.key, kv.value, false);
	}
	writer->Finish();
	printf( "STAT VectorConverged write %ld pairs read %ld pairs\n", writer->writecnt, readcnt );
	delete writer;


	BgVertexList* rv = this->LoadVertices(strfname,keyType,valType);
	return rv;
}
