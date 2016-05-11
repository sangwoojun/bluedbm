#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "smithwaterman.h"

void init() {
}

int smithwatermandist(char* a, char* b) {
	int alen = strlen(a);
	int blen = strlen(b);
	int* dmat = (int*)malloc(sizeof(int)*alen*blen);
	
	for ( int i = 0; i < alen; i++ ) {
		int idx = i * blen;
		dmat[idx] = 0;
	}
	for ( int j = 0; j < blen; j++ ) {
		int idx = j;
		dmat[idx] = 0;
	}

	for ( int i = 1; i < alen; i++ ) {
		for ( int j = 1; j < blen; j++ ) {
			int lidx = (i-1)*blen + j;
			int uidx = (i)*blen + j-1;
			int didx = (i-1)*blen + j-1;
			int idx = i*blen + j;
			int ld = dmat[lidx] - 1;
			int ud = dmat[uidx] - 1;
			int dd = dmat[didx];
			if ( a[i] == b[i] ) dd += 2;
			if ( ld > ud && ld > dd ) dmat[idx] = ld;
			else if ( ud > ld && ud > dd ) dmat[idx] = ud;
			else if ( dd > ud && dd > ld ) dmat[idx] = dd;
		}
	}


	int idx = (alen-1)*blen + (blen-1);
	int res = dmat[idx];
	free(dmat);
	return res;
}
