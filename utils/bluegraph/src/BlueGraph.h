#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <pthread.h>

#include <string>

#include "defines.h"

#include "VertexList.h"
#include "Sorters.h"

#define SORTER_THREAD_COUNT 4

#ifndef __BLUEGRAPH_H__
#define __BLUEGRAPH_H__

struct block_sorter_worker_info {
	pthread_t tid;
	uint8_t* tbuf;
	int objcount;
	BgKeyType keyType;
	BgValType valType;
};

class BgEdgeList {
public:
	BgEdgeList(std::string idxname, std::string matname, BgKeyType keytype);

	bool HasNext();
	BgKvPair GetNext();
	bool LoadOutEdges(uint64_t key);

private:
	FILE* fidx;
	FILE* fmat;
	BgKeyType keyType;
	
	BgKvPair LoadNext();
	BgKvPair readBuffer;// = {false, 0,0};

	uint64_t matrixFileOffset;
	uint64_t matrixReadLimit;
	uint64_t matrixCurOffset;
};

class BlueGraph {
public:

	static BlueGraph* getInstance();

	BgEdgeList* LoadEdges(std::string idxname, std::string matname, BgKeyType keytype);
	BgVertexList* LoadVertices(std::string name, BgKeyType keyType, BgValType valType );

	BgVertexList* Execute(BgEdgeList* el, BgVertexList* vl, std::string newVertexListName, BgUserProgramType userProg, BgKeyType targetKeyType, BgValType targetValType);

	uint64_t EdgeProgram(uint64_t vertexValue, BgKvPair edge, BgUserProgramType userProg);
	uint64_t VertexProgram(uint64_t vertexValue1, uint64_t vertexValue2, BgUserProgramType userProg);

	int PageSort(BgKeyType keyType, BgValType valType, BgUserProgramType prog);

	// 16-way merge sort
	// stage is 0 when reading from 512MB block results
	int MergeSort16(BgKeyType keyType, BgValType valType, BgUserProgramType prog, int stage, int mergedBlockCount);



private:
	static BlueGraph* m_pInstance;

	FILE* ftmp = NULL;
};

class ReducerWriter {
public:
	ReducerWriter(std::string filename, BgUserProgramType prog, BgKeyType keyType, BgValType valType);
	~ReducerWriter();
	void ReduceWriteBlock(uint8_t* buffer, int count);
	void ReduceWrite(uint64_t key, uint64_t val, bool last);
	void RawWrite(uint64_t key, uint64_t val);
	void Finish();
	
	uint64_t writecnt;
private:
	FILE* fout;
	BgUserProgramType prog;

	bool lastValid;
	uint64_t lastKey;
	uint64_t lastVal;

	BgKeyType keyType;
	BgValType valType;
	
};



#endif
