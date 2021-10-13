#include <stdio.h>
#include <unistd.h>
#include <time.h>

#include "bdbmpcie.h"
#include "dmasplitter.h"

//------------------------------------------------------------------
//DEFINITION of Global Vars
//------------------------------------------------------------------
int myid;

//------------------------------------------------------------------
//FUNCTIONS
//------------------------------------------------------------------
double timespec_diff_sec( timespec start, timespec end ) {
	double t = end.tv_sec - start.tv_sec;
	t += ((double)(end.tv_nsec - start.tv_nsec)/1000000000L);
	return t;
}

//------------------------------------------------------------------
//MAIN
//------------------------------------------------------------------
int main(int argc, char** argv) {
	printf( "Software startec\n" ); fflush(stdout);
	BdbmPcie* pcie = BdbmPcie::getInstance();

	unsigned int d = pcie->readWord(0);
	printf( "Magic: %x\n", d );
	fflush(stdout);
	if ( d != 0xc001d00d ) {
		printf( "Magic number is incorrect (0xc001d00d)\n" );
		return -1;
	}
	
	//Getting my ID
	char hostname[32];
	gethostname(hostname, 32);

	char* userhostid = getenv("BDBM_ID");
	if ( userhostid != NULL ) {
			myid = atoi(userhostid);
	}
	else {
		myid = atoi(hostname+strlen("bdbm"));
		if ( strstr(hostname, "bdbm") == NULL ) {
			myid = 1;
		}
	}

	fprintf(stderr, "Main: myid=%d\n", myid);

	//Start AuroraExt
	auroraifc_start(myid);

	timespec start;
	timespec now;

	clock_gettime(CLOCK_REALTIME, & start);

	pcie->userWriteWord(0, 0xdeadbeef);
	
	clock_gettime(CLOCK_REALTIME, & now);
	double diff = timespec_diff_sec(start, now);

	printf( "read: %x\n", pcie->userReadWord(0) );
	printf( "Write elapsed: %f\n", diff );
	fflush(stdout);

	clock_gettime(CLOCK_REALTIME, & start);

	pcie->userReadWord(0);
	clock_gettime(CLOCK_REALTIME, & now);
	diff = timespec_diff_sec(start, now);
	printf( "Read elapsed: %f\n", diff );
	
	return 0;
}
