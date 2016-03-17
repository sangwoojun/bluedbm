#include "bdbmpcie.h"

#ifndef __FLASHMANAGER__H__
#define __FLASHMANAGER__H__

#define TAG_COUNT 256
#define TAG_PERBUS 16

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
	int getIdleTag(int bbus); //board(1bit)/bus(3bits)
	
	FlashManager();


public:
	//FIXME use dma Buffer instead
	void* storebuffer[TAG_COUNT];
	uint8_t* statusbuffer[TAG_COUNT];

	bool tagBusy[TAG_COUNT];
	timespec sentTime[TAG_COUNT];

	pthread_mutex_t flashMutex;
	pthread_cond_t flashCond;

	int readInFlight;
};
#endif

