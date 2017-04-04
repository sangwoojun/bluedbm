#include "sssp.h"

uint64_t
BgUserSSSP::EdgeProgram(uint64_t vertexValue, uint64_t edgeValue) {
	return vertexValue + edgeValue;
}
uint64_t 
BgUserSSSP::VertexProgram(uint64_t v1, uint64_t v2) {
	return (v1>v2 ? v2 : v1);
}

bool 
BgUserSSSP::Converged(uint64_t v1, uint64_t v2) {
	return (v1>v2)?true:false;
}


