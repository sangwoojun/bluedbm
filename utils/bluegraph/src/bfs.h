#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#include <string>

#include "defines.h"

#ifndef __BFS_H__
#define __BFS_H__

class BgUserBFS : BgUserProgram {
public:
	static uint64_t EdgeProgram(uint64_t vertexValue, uint64_t edgeValue);
	static uint64_t VertexProgram(uint64_t v1, uint64_t v2);
	static bool Converged(uint64_t v1, uint64_t v2);

};

#endif


