#include "bdbmpcie.h"

#ifndef __FLASHMANAGER__H__
#define __FLASHMANAGER__H__

#define TAG_COUNT 64

//Flash page size
#define FPAGE_SIZE 8192

#define FLASHSTAT_ERASE_DONE 1
#define FLASHSTAT_ERASE_FAIL 2
#define FLASHSTAT_ERASE_WAIT 3

typedef struct PhysPage {
	int bus;
	int chip;
	int block;
	int page;
} PhysPage;

class FlashManager {
public:
void eraseBlock(int bus, int chip, int block, uint8_t* status);
void writePage(int bus, int chip, int block, int page, void* buffer, uint8_t* status);
void readPage(int bus, int chip, int block, int page, void* buffer, uint8_t* status);

	static FlashManager* getInstance();

private:
	pthread_t flashThread;
	static FlashManager* m_pInstance;
	int getIdleTag();
	
	FlashManager();


public:
	//FIXME use dma Buffer instead
	void* storebuffer[TAG_COUNT];
	uint8_t* statusbuffer[TAG_COUNT];

	bool tagBusy[TAG_COUNT];
	timespec sentTime[TAG_COUNT];

	int readinflight;
	pthread_mutex_t flashMutex;
	pthread_cond_t flashCond;
};
#endif

