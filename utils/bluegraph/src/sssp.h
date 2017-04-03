#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#include <string>

#include "defines.h"

#ifndef __SSSP_H__
#define __SSSP_H__

class BgUserSSSP : BgUserProgram {
public:
	static uint64_t EdgeProgram(uint64_t vertexValue, BgKvPair edge);
	static uint64_t VertexProgram(uint64_t v1, uint64_t v2);

};

#endif

