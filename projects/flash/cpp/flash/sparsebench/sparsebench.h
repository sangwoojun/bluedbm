#ifndef __SPARSEBENCH_H__
#define __SPARSEBENCH_H__

#include <stdio.h>
#include <unistd.h>

#include "bdbmpcie.h"
#include "flashmanager.h"
#include "dmasplitter.h"
#include "bsbfs.h"

void sparsebench(int accelcount, int pages, int vlen, int* vector);
void loadFiles();

#endif
