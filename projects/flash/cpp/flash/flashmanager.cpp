#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "flashmanager.h"
#include "dmasplitter.h"

double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

FlashManager*
FlashManager::m_pInstance = NULL;

FlashManager*
FlashManager::getInstance() {
	if ( m_pInstance == NULL ) m_pInstance = new FlashManager();

	return m_pInstance;
}

void* flashManagerThread(void* arg) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();

	void* dmabuffer = dma->dmaBuffer();
	uint8_t* bdb = (uint8_t*)dmabuffer;

	int readpagetotal = 0;
	while (1) {
		PCIeWord w = dma->recvWord();
		uint32_t msg = w.d[0];
		uint32_t tag = msg & 0xffff;
		uint8_t code = (msg>>16)&0xff;
		switch ( code ) {
			case 0: { // read done
				pthread_mutex_lock(&(flash->flashMutex));

				flash->tagBusy[tag] = false; 
				*flash->statusbuffer[tag] = 1;
				//timespec now;
				//clock_gettime(CLOCK_REALTIME, & now);
				//double diff = timespec_diff_sec(flash->sentTime[tag], now);
				//readpagetotal++;
				//flash->readinflight--;
				//printf( "read done to tag %d Latency %f total %d inflight %d \n", tag, diff, readpagetotal, flash->readinflight ); 
				memcpy(flash->storebuffer[tag], bdb+(1024*8*tag), (1024*8));
				pthread_cond_broadcast(&(flash->flashCond));
				pthread_mutex_unlock(&(flash->flashMutex));
			}
			break;
			case 1: {
				//printf( "write done to tag %d\n", tag );
				pthread_mutex_lock(&(flash->flashMutex));
				flash->tagBusy[tag] = false; 
				*flash->statusbuffer[tag] = 1;
				pthread_cond_broadcast(&(flash->flashCond));
				pthread_mutex_unlock(&(flash->flashMutex));
			}
			break;
			case 2: {
				//printf( "erase done to tag %d\n", tag ); fflush(stdout);
				pthread_mutex_lock(&(flash->flashMutex));
				uint8_t* buf = flash->statusbuffer[tag];
				*buf = FLASHSTAT_ERASE_DONE;
				flash->tagBusy[tag] = false;
				pthread_cond_broadcast(&(flash->flashCond));
				pthread_mutex_unlock(&(flash->flashMutex));
			}
			break;
			case 3: {
				pthread_mutex_lock(&(flash->flashMutex));
				uint8_t* buf = flash->statusbuffer[tag];
				*buf = FLASHSTAT_ERASE_FAIL;
				//printf( "erase failed to tag %d\n", tag ); 
				flash->tagBusy[tag] = false;
				pthread_cond_broadcast(&(flash->flashCond));
				pthread_mutex_unlock(&(flash->flashMutex));
			}
			break;
			case 4: {
				//printf( "ready to write to tag %d\n", tag );
				pthread_mutex_lock(&(flash->flashMutex));
				uint32_t* buf = (uint32_t*)flash->storebuffer[tag];
				for ( int i = 0; i < (1024*8)/8; i++ ) {
					int idx = i*2;
					dma->sendWord(buf[idx], buf[idx+1], 0, 1);
				}
				pthread_cond_broadcast(&(flash->flashCond));
				pthread_mutex_unlock(&(flash->flashMutex));
				//printf( "wrote to tag %d\n", tag );
			}
			break;
			case 0xff: {
				int cmdc = (w.d[1] & 0xffff);
				int wc = (w.d[1]>>16);
				int up = (w.d[2]>>16);
				int budget = (w.d[2]& 0xffff);

				printf( "Flash state: %d %d %d %d\n", up, budget, cmdc, wc );
				printf( "%x %x %x %x\n", w.d[0], w.d[1], w.d[2], w.d[3] );
			}
			break;
			default: {
				printf( "Uncaught %x %x %x %x\n", w.d[0], w.d[1], w.d[2], w.d[3] );
			}
		}
	}
}

FlashManager::FlashManager() {
	pthread_mutex_init(&flashMutex, NULL);
	pthread_cond_init(&flashCond, NULL);
	for ( int i = 0; i < TAG_COUNT; i++ ) {
		tagBusy[i] = false;
	}
	pthread_create(&flashThread, NULL, flashManagerThread, NULL);
	
}

int
FlashManager::getIdleTag() {
	for ( int i = 0; i < TAG_COUNT; i++ ) {
		if ( tagBusy[i] == false ) {
			return i;
		}
	}
	return -1;
}

/*
0: op
1: blockpagetag
2: buschip
*/
void FlashManager::eraseBlock(int bus, int chip, int block, uint8_t* status) {
	DMASplitter* dma = DMASplitter::getInstance();
	
	pthread_mutex_lock(&flashMutex);
	int page = 0;
	int tag = getIdleTag();
	while (tag < 0 ) {
		pthread_cond_wait(&flashCond, &flashMutex);
		//usleep(10);
		tag = getIdleTag();
	}
	tagBusy[tag] = true;
	
	this->statusbuffer[tag] = status;

	uint32_t blockpagetag = (block<<16) | (page<<8) | tag;
	uint32_t buschip = (bus<<8) | chip;
	dma->sendWord(0, blockpagetag, buschip, 0);//erase
	pthread_mutex_unlock(&flashMutex);
//	printf( "Erase sent to %d: %d %d %d\n", tag, bus,chip,block ); fflush(stdout);
}
void FlashManager::writePage(int bus, int chip, int block, int page, void* buffer, uint8_t* status) {
	DMASplitter* dma = DMASplitter::getInstance();
	
	pthread_mutex_lock(&flashMutex);
	int tag = getIdleTag();
	while (tag < 0 ) {
		pthread_cond_wait(&flashCond, &flashMutex);
		//usleep(10);
		tag = getIdleTag();
	}
	tagBusy[tag] = true;
	this->storebuffer[tag] = buffer;
	this->statusbuffer[tag] = status;
	
	uint32_t blockpagetag = (block<<16) | (page<<8) | tag;
	uint32_t buschip = (bus<<8) | chip;
	dma->sendWord(2, blockpagetag, buschip, 0);//write
	pthread_mutex_unlock(&flashMutex);
//	printf( "Write command sent to %d: %d %d %d %d\n", tag, bus,chip,block,page ); fflush(stdout);
}
void FlashManager::readPage(int bus, int chip, int block, int page, void* buffer, uint8_t* status) {
	
	DMASplitter* dma = DMASplitter::getInstance();
	BdbmPcie* pcie = BdbmPcie::getInstance();
	
	timespec start;
	clock_gettime(CLOCK_REALTIME, & start);



	pthread_mutex_lock(&flashMutex);

	int tag = getIdleTag();
	while (tag < 0 ) {
		//usleep(50);
		pthread_cond_wait(&flashCond, &flashMutex);
		tag = getIdleTag();
	}
	tagBusy[tag] = true;
	sentTime[tag] = start;
	this->storebuffer[tag] = buffer;
	this->statusbuffer[tag] = status;

	readinflight++;
	pthread_mutex_unlock(&flashMutex);

	
	uint32_t blockpagetag = (block<<16) | (page<<8) | tag;
	uint32_t buschip = (bus<<8) | chip;
	dma->sendWord(1, blockpagetag, buschip, 0);//read

	//printf( "sent read req %d %d %d %d %d\n", tag, bus, chip, block, page ); fflush(stdout);


}
