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

void procFlashEvent(uint8_t tag, uint8_t code) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();
	void* dmabuffer = dma->dmaBuffer();
	uint8_t* bdb = (uint8_t*)dmabuffer;
	//FIXME
	int readcnt = 0;
	switch ( code ) {
		case 0: { // read done
			pthread_mutex_lock(&(flash->flashMutex));

			flash->tagBusy[tag] = false; 
			*flash->statusbuffer[tag] = 1;

			if ( flash->targetMap[tag] == 0 ) {
				//memcpy(flash->storebuffer[tag], bdb+(1024*8*flash->readCount), (1024*8));
				memcpy(flash->storebuffer[tag], bdb+(1024*8*tag), (1024*8));
				flash->readCount++;
				if ( flash->readCount >= 256 ) flash->readCount = 0;
			}


			timespec now;
			clock_gettime(CLOCK_REALTIME, & now);
			double diff = timespec_diff_sec(flash->sentTime[tag], now);
			//printf( "read done to tag %d > %d %f\n", tag, ++readcnt, diff); 
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
			fflush(stdout);
			pthread_mutex_lock(&(flash->flashMutex));
			uint32_t* buf = (uint32_t*)flash->storebuffer[tag];
			for ( int i = 0; i < (1024*8)/16; i++ ) {
				int idx = i*4;
				dma->sendWord(1, buf[idx], buf[idx+1], buf[idx+2], buf[idx+3]);
			}
			pthread_cond_broadcast(&(flash->flashCond));
			pthread_mutex_unlock(&(flash->flashMutex));
			//printf( "wrote to tag %d\n", tag );
		}
		break;
		default: {
			printf( "Uncaught flash event code: %x tag: %x\n", code, tag ); fflush(stdout);
		}
	}
}

void* flashManagerThread(void* arg) {
	BdbmPcie* pcie = BdbmPcie::getInstance();
	DMASplitter* dma = DMASplitter::getInstance();
	FlashManager* flash = FlashManager::getInstance();

	void* dmabuffer = dma->dmaBuffer();
	uint8_t* bdb = (uint8_t*)dmabuffer;

	while (1) {
		PCIeWord w = dma->recvWord();
		int rcount = 0;
		if ( w.header == 0 ) {
			for ( int i = 3; i >= 0; i-- ) {
				uint32_t msg1 = w.d[i] & 0xffff;
				uint32_t msg2 = (w.d[i]>>16) & 0xffff;
				uint8_t tag1 = (msg1>>8)&0xff;
				uint8_t tag2 = (msg2>>8)&0xff;
				uint8_t code1 = (msg1&0xff);
				uint8_t code2 = (msg2&0xff);
				if ( code2 != 0xff ) {
					procFlashEvent(tag2,code2);
					rcount++;
				} 
				if ( code1 != 0xff ) {
					procFlashEvent(tag1,code1);
					rcount++;
				}
			}
		} 
		else if ( w.header == 2 ) {
			uint64_t cidx = w.d[3];
			cidx = (cidx<<32)|w.d[2];
			uint64_t val = (((uint64_t)w.d[1])<<32)|w.d[0];
			printf( "VM result %ld %ld\n", cidx, val );
			fflush(stdout);
		} else {
			printf( "uncaught dma.enq %d\n", w.header );
		}
		//if ( rcount > 2 )
		//printf( "rcount= %d\n", rcount );
	}
}

FlashManager::FlashManager() {
	pthread_mutex_init(&flashMutex, NULL);
	pthread_cond_init(&flashCond, NULL);
	for ( int i = 0; i < TAG_COUNT; i++ ) {
		tagBusy[i] = false;
	}
	readCount = 0;
	
	DMASplitter* dma = DMASplitter::getInstance();
	void* dmabuffer = dma->dmaBuffer();
	uint8_t* bdb = (uint8_t*)dmabuffer;
	for ( int i = 0; i < 8192*256; i++ ) bdb[i] = 0xcc;


	pthread_create(&flashThread, NULL, flashManagerThread, NULL);
	
}

int
FlashManager::getIdleTag(int bbus) {
	for ( int i = 0; i < TAG_PERBUS; i++ ) {
		int idx = (bbus<<4) | i;
		if ( tagBusy[idx] == false ) {
			return idx;
		}
	}
	return -1;
}

/*
New encoding!
0: op
1: blockpagechip
2: tag (board(1), bus(3), tag(3))
*/
void FlashManager::eraseBlock(int bus, int chip, int block, uint8_t* status) {
	DMASplitter* dma = DMASplitter::getInstance();
	
	pthread_mutex_lock(&flashMutex);
	int page = 0;
	int tag = getIdleTag(bus);
	while (tag < 0 ) {
		pthread_cond_wait(&flashCond, &flashMutex);
		//usleep(10);
		tag = getIdleTag(bus);
	}
	tagBusy[tag] = true;
	
	this->statusbuffer[tag] = status;

	//uint32_t blockpagetag = (block<<16) | (page<<8) | tag;
	//uint32_t buschip = (bus<<8) | chip;
	uint32_t blockpagechip = (block<<16) | (page<<8) | chip;
	dma->sendWord(0, 0, blockpagechip, tag, 0);//erase
	pthread_mutex_unlock(&flashMutex);
//	printf( "Erase sent to %d: %d %d %d\n", tag, bus,chip,block ); fflush(stdout);
}
void FlashManager::writePage(int bus, int chip, int block, int page, void* buffer, uint8_t* status) {
	DMASplitter* dma = DMASplitter::getInstance();
	
	pthread_mutex_lock(&flashMutex);
	int tag = getIdleTag(bus);
	while (tag < 0 ) {
		pthread_cond_wait(&flashCond, &flashMutex);
		//usleep(10);
		tag = getIdleTag(bus);
	}
	tagBusy[tag] = true;
	this->storebuffer[tag] = buffer;
	this->statusbuffer[tag] = status;
	
	//uint32_t blockpagetag = (block<<16) | (page<<8) | tag;
	//uint32_t buschip = (bus<<8) | chip;
	uint32_t blockpagechip = (block<<16) | (page<<8) | chip;
	dma->sendWord(0, 2, blockpagechip, tag, 0);//write
	pthread_mutex_unlock(&flashMutex);
	//printf( "Write command sent to %d: %d %d %d %d\n", tag, bus,chip,block,page ); fflush(stdout);
}

void FlashManager::readPage(int bus, int chip, int block, int page, void* buffer, uint8_t* status) {
	this->readPage(bus,chip,block,page,buffer,0,status);
}
void FlashManager::readPage(int bus, int chip, int block, int page, void* buffer, int target, uint8_t* status) {
	
	DMASplitter* dma = DMASplitter::getInstance();
	BdbmPcie* pcie = BdbmPcie::getInstance();

	



	pthread_mutex_lock(&flashMutex);
	timespec start;
	clock_gettime(CLOCK_REALTIME, & start);

	int tag = getIdleTag(bus);
	while (tag < 0 ) { 
		pthread_cond_wait(&flashCond, &flashMutex);
		tag = getIdleTag(bus);
	}
	tagBusy[tag] = true;
	this->storebuffer[tag] = buffer;
	this->statusbuffer[tag] = status;
	
	void* dmabuffer = dma->dmaBuffer();
	uint8_t* bdb = (uint8_t*)dmabuffer;
	for ( int i = 0; i < 8192; i++ ) {
		bdb[8192*tag+i] = 0xcc;
	}


	
	uint32_t blockpagechip = (block<<16) | (page<<8) | chip;
	uint32_t desttag = (target<<16) | tag;
	dma->sendWord(0, 1, blockpagechip, desttag, 0);//read
	
	sentTime[tag] = start;
	targetMap[tag] = target;
	pthread_mutex_unlock(&flashMutex);

	//printf( "sent read req %d %d %d %d %d\n", tag, bus, chip, block, page ); fflush(stdout);


}
