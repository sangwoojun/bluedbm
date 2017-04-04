#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <pthread.h>

#include <string>

#include "defines.h"

#include "VertexList.h"
#include "Sorters.h"


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
	uint64_t stat_lastpage;

	uint64_t vertexCount;
	uint64_t edgeSz;
public:
	uint64_t stat_readpagecnt;
	uint64_t matrixReadEdgeCount;
	void StatNewIter() {
		stat_readpagecnt = 0;
		stat_lastpage = 0xffffffffffffffff;
	}
};

class BlueGraph {
public:

	static BlueGraph* getInstance();

	BgEdgeList* LoadEdges(std::string idxname, std::string matname, BgKeyType keytype);
	BgVertexList* LoadVertices(std::string name, BgKeyType keyType, BgValType valType );

	BgVertexList* Execute(BgEdgeList* el, BgVertexList* vl, std::string newVertexListName, BgUserProgramType userProg, BgKeyType targetKeyType, BgValType targetValType, bool edgeCountArg);

	uint64_t EdgeProgram(uint64_t vertexValue, uint64_t edgeValue, BgUserProgramType userProg);
	uint64_t VertexProgram(uint64_t vertexValue1, uint64_t vertexValue2, BgUserProgramType userProg);
	bool Converged(uint64_t vertexValue1, uint64_t vertexValue2, BgUserProgramType userProg);

	int PageSort(BgKeyType keyType, BgValType valType, BgUserProgramType prog);

	// 16-way merge sort
	// stage is 0 when reading from 512MB block results
	int MergeSort16(BgKeyType keyType, BgValType valType, BgUserProgramType prog, int stage, int mergedBlockCount);


	BgVertexList* VectorDiff(BgVertexList* from, BgVertexList* term, std::string fname);
	BgVertexList* VectorUnion(BgVertexList* from, BgVertexList* term, BgUserProgramType prog, std::string fname);
	BgVertexList* VectorConverged(BgVertexList* from, BgVertexList* term, BgUserProgramType prog, std::string fname);



private:
	BlueGraph();
	static BlueGraph* m_pInstance;

	FILE* ftmp = NULL;

	int vectorGenIdx;
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

	uint64_t checklast;

	BgKeyType keyType;
	BgValType valType;
	
};



#endif
