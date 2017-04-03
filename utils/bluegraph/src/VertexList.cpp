#include "VertexList.h"

BgVertexList::BgVertexList(BgKeyType keyType, BgValType valType) {
	this->keyType = keyType;
	this->valType = valType;
}


BgVertexListFile::BgVertexListFile(BgKeyType keyType, BgValType valType) : BgVertexList(keyType,valType) {
	this->readBuffer.valid = false;
}

void
BgVertexListFile::OpenFile(std::string name) {
	this->fin = fopen(name.c_str(), "rb");
	if ( this->fin == NULL ) {
		fprintf(stderr, "Error: BgVertexListFile initialization failed. Cannot load %s\n", name.c_str() );
	}
}

void
BgVertexListFile::Rewind() {
	readBuffer.valid = false;

	if ( fin == NULL ) return;

	fseek(fin, 0, SEEK_SET);
}

bool
BgVertexListFile::HasNext() {
	if ( feof(fin) ) return false;

	if ( readBuffer.valid ) return true;

	BgKvPair kvp = this->LoadNext();
	readBuffer = kvp;

	return kvp.valid;
}

BgKvPair
BgVertexListFile::GetNext() {
	if ( readBuffer.valid ) {
		BgKvPair kvp = readBuffer;
		readBuffer.valid = false;
		return kvp;
	}

	return this->LoadNext();
}

BgKvPair
BgVertexListFile::LoadNext() {
	BgKvPair kvp = {false, 0,0};
	if ( fin == NULL ) return kvp;

	switch (keyType) {
		case BGKEY_BINARY32: {
			uint32_t trv;
			int r = fread(&trv, sizeof(uint32_t), 1, fin);
			if ( r == 1 ) {
				kvp.valid = true;
				kvp.key = trv; //kvp.value=trv[1];
			}
			break;
		}
		case BGKEY_BINARY64: {
			uint64_t trv;
			int r = fread(&trv, sizeof(uint64_t), 1, fin);
			if ( r == 1 ) {
				kvp.valid = true;
				kvp.key = trv; //kvp.value=trv[1];
			}
			break;
		}
	}
	switch (valType) {
		case BGVAL_NONE: break;
		case BGVAL_BINARY32: {
			uint32_t trv;
			int r = fread(&trv, sizeof(uint32_t), 1, fin);
			if ( r == 1 ) {
				kvp.value=trv;
			}
			break;
		}
		case BGVAL_BINARY64: {
			uint64_t trv;
			int r = fread(&trv, sizeof(uint64_t), 1, fin);
			if ( r == 1 ) {
				kvp.value=trv;
			}
			break;
		}
	}
	return kvp;
}


BgVertexListInMem::BgVertexListInMem(BgKeyType keyType, BgValType valType) : BgVertexList(keyType, valType) {
	offset = 0;
}
bool 
BgVertexListInMem::HasNext() {
	return (offset < buffer.size());
}
BgKvPair 
BgVertexListInMem::GetNext() {
	if (offset < buffer.size() ) {
		BgKvPair kvp = buffer[offset];
		offset++;
		return kvp;
	} else {
		BgKvPair kvp = {false, 0,0};
		return kvp;
	}
}
void 
BgVertexListInMem::Rewind() {
	offset = 0;
}
void 
BgVertexListInMem::addVal(uint64_t k, uint64_t v) {
	BgKvPair kvp = {true,k,v};
	buffer.push_back(kvp);
}
