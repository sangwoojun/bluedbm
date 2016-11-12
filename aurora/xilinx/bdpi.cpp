#include <stdio.h>
#include <fcntl.h>
#include <stdlib.h>
#include <errno.h>
#include <poll.h>
#include <unistd.h>
#include <string.h>

# include <sys/types.h>
# include <sys/stat.h>

#define RD_PORT (0<<3)
#define WR_PORT (1<<3)


bool fifo_exists[16] = {0};
int fifo_fd[16];

bool read_recv[8]= {true};
bool getPipes(unsigned char nidx, unsigned char pidx) {
	if ( nidx > 20 ) return false;
	
	unsigned char rdidx = pidx | RD_PORT;
	unsigned char wridx = pidx | WR_PORT;
	if ( fifo_exists[rdidx] && fifo_exists[wridx] ) return true;

	unsigned char off = 0;
	
	char fifonamerd[35];
	char fifonamewr[35];

	umask(0);

	// port 3 connects to port 0, port 2 to port 1
	if ( pidx <= 1 ) { // goes up
		off = pidx;

		sprintf(fifonamewr, "../../aurorapipes/aurora%02d_%02dup", nidx,off);
		sprintf(fifonamerd, "../../aurorapipes/aurora%02d_%02ddown", nidx,off);
		// these will probably not fail, or fail with EEXIST
		if( access( fifonamerd, F_OK ) == -1 ) {
			if (mkfifo(fifonamerd, S_IRUSR| S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH) < 0)
				fprintf(stderr, "%s:%d mkfifo returned errno=%d:%s\n", __FUNCTION__, __LINE__, errno, strerror(errno));
		}
		if( access( fifonamewr, F_OK ) == -1 ) {
			if (mkfifo(fifonamewr, S_IRUSR| S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH) < 0)
				fprintf(stderr, "%s:%d mkfifo returned errno=%d:%s\n", __FUNCTION__, __LINE__, errno, strerror(errno));
		}

	} else if ( pidx >= 2 && pidx < 4 && nidx > 0) { // comes up
		if ( pidx == 2 ) off = 1;
		if ( pidx == 3 ) off = 0;
		sprintf(fifonamerd, "../../aurorapipes/aurora%02d_%02dup", nidx-1,off);
		sprintf(fifonamewr, "../../aurorapipes/aurora%02d_%02ddown", nidx-1,off);
		// these will probably not fail, or fail with EEXIST
		if( access( fifonamerd, F_OK ) == -1 ) {
			if (mkfifo(fifonamerd, S_IRUSR| S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH) < 0)
				fprintf(stderr, "%s:%d mkfifo returned errno=%d:%s\n", __FUNCTION__, __LINE__, errno, strerror(errno));
		}
		if( access( fifonamewr, F_OK ) == -1 ) {
			if (mkfifo(fifonamewr, S_IRUSR| S_IWUSR | S_IRGRP | S_IWGRP | S_IROTH | S_IWOTH) < 0)
				fprintf(stderr, "%s:%d mkfifo returned errno=%d:%s\n", __FUNCTION__, __LINE__, errno, strerror(errno));
		}
	}

	if ( !fifo_exists[rdidx] ) {
		fifo_fd[rdidx] = open(fifonamerd, O_RDONLY | O_NONBLOCK);
		if ( fifo_fd[rdidx] != -1 ) {
			read_recv[pidx] = true;
			fifo_exists[rdidx] = true;
			fprintf(stderr,  "Created and opened read fd for %d(%d)\n", nidx, pidx );
		} else {
			//NOTE: Because FIFOs cannot be opened for writes before before the reading side has already opened it yet
			// (It will fail with ENXIO(6), the error message below is unneeded. Entering this else block is normal behavior

			//if (errno != EAGAIN)
			//	fprintf(stderr, "%s:%d failed to open fifo %s errno=%d:%s\n", __FUNCTION__, __LINE__, fifonamerd, errno, strerror(errno));
		}
	}

	if ( !fifo_exists[wridx] ) {
		fifo_fd[wridx] = open(fifonamewr, O_WRONLY| O_NONBLOCK);
		if ( fifo_fd[wridx] != -1 ) {
			fifo_exists[wridx] = true;
			fprintf(stderr, "Created and opened write fd for %d(%d)\n", nidx, pidx );
		} else {
			//NOTE: Because FIFOs cannot be opened for writes before before the reading side has already opened it yet
			// (It will fail with ENXIO(6), the error message below is unneeded. Entering this else block is normal behavior

			//fprintf(stderr, "%s:%d failed to open fifo %s errno=%d:%s\n", __FUNCTION__, __LINE__, fifonamewr, errno, strerror(errno));
		}
	}

	return true;
}

unsigned long long lastread[8];
extern "C" bool bdpiRecvAvailable(unsigned char nidx, unsigned char pidx) {
  //fprintf(stderr, "bdpiRecvAvailable %d, %d\n", nidx, pidx ); // Too verbose
	if ( ! getPipes(nidx, pidx) ) return false;

	if ( !read_recv[pidx] ) return true;

	unsigned char rdidx = pidx | RD_PORT;
	
	unsigned long long d;

	int r = read(fifo_fd[rdidx], &d, sizeof(unsigned long long));

	if ( r > 0 ) {
		lastread[pidx] = d;
		read_recv[pidx] = false;
		//fprintf(stderr, "read %d bytes %llx %d(%d)\n", r, lastread[pidx], nidx, pidx ); // Too verbose
		return true;
	} else if ( r < 0) {
		//fprintf(stderr, "%s:%d: fd=%d errno=%d:%s\n", __FUNCTION__, __LINE__, fifo_fd[rdidx], errno, strerror(errno));
	}
	return false;
}

extern "C" bool bdpiSendAvailable(unsigned char nidx, unsigned char pidx) {
	if ( ! getPipes(nidx, pidx) ) return false;
	//unsigned char wridx = pidx | WR_PORT;

	return true;
}

extern "C" unsigned long long bdpiRead(unsigned char nidx, unsigned char pidx) {
	if ( ! getPipes(nidx, pidx) ) {
		return 0xcccccccc;
	}
	//printf( "read data %llx %d(%d)\n", lastread[pidx], nidx, pidx );
	read_recv[pidx] = true;
	return lastread[pidx];
}

extern "C" bool bdpiWrite(unsigned char nidx, unsigned char pidx, unsigned long long data) {
	//fprintf(stderr, "write data %llx %d(%d)\n", data, nidx, pidx ); // Too verbose
	if ( ! getPipes(nidx, pidx) ) return false;
	unsigned char wridx = pidx | WR_PORT;

	int r = write(fifo_fd[wridx], &data, sizeof(unsigned long long));
	if ( r < 8 ) return false;

	return true;
}
