#include "bdbmpcie.h"

#ifndef __FLASHMANAGER__H__
#define __FLASHMANAGER__H__

#define TAG_COUNT 64

class FlashManager {
public:
FlashManager();
void eraseBlock(int bus, int chip, int block);
void writePage(int bus, int chip, int block, int page, void* buffer);
void readPage(int bus, int chip, int block, int page, void* buffer);

	static FlashManager* getInstance();

private:
	pthread_t flashThread;
	static FlashManager* m_pInstance;
	int getIdleTag();


public:
	//FIXME use dma Buffer instead
	void* storebuffer[TAG_COUNT];
	bool tagBusy[TAG_COUNT];
	timespec sentTime[TAG_COUNT];

	int readinflight;
	pthread_mutex_t flashMutex;
	pthread_cond_t flashCond;
};
#endif

