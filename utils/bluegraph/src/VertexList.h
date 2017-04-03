#ifndef __VERTEXLIST_H__
#define __VERTEXLIST_H__

#include <vector>

#include "defines.h"



class BgVertexList {
public:
	BgVertexList(BgKeyType keyType, BgValType valType);
	virtual bool HasNext()=0;
	virtual BgKvPair GetNext()=0;
	virtual void Rewind()=0;
	virtual BgKvPair PeekNext()=0;
	virtual bool IsEmpty()=0;

	BgKeyType keyType;
	BgValType valType;
};

class BgVertexListFile : public BgVertexList {
public:
	BgVertexListFile(BgKeyType keyType, BgValType valType);


	bool HasNext();
	BgKvPair GetNext();
	BgKvPair PeekNext();
	void Rewind();
	void OpenFile(std::string name);
	bool IsEmpty();



private:
	BgVertexListFile();
	BgKvPair LoadNext();


	FILE* fin;

	BgVertexList* vlToAnd = NULL; // key must be in both lists
	BgVertexList* vlToSub = NULL; // key must not be in vlToSub
	BgVertexList* vlToAdd = NULL; // key may be in any list

	BgKvPair readBuffer;// = {false, 0,0};

	uint64_t filesize;

};

class BgVertexListInMem : public BgVertexList {
public:
	BgVertexListInMem(BgKeyType keyType, BgValType valType);
	bool HasNext();
	BgKvPair GetNext();
	void Rewind();
	BgKvPair PeekNext();
	void addVal(uint64_t k, uint64_t v);
	bool IsEmpty();

private:
	BgVertexListInMem();

	unsigned int offset;
	uint64_t keyBuf;
	uint64_t valBuf;

	std::vector<BgKvPair> buffer;
};


#endif
