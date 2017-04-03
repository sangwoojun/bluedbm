#include "sssp.h"

uint64_t
BgUserSSSP::EdgeProgram(uint64_t vertexValue, BgKvPair edge) {
	return vertexValue + edge.value;
}
uint64_t 
BgUserSSSP::VertexProgram(uint64_t v1, uint64_t v2) {
	return (v1>v2 ? v2 : v1);
}


