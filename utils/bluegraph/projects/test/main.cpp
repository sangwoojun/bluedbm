#include <stdio.h>

#include "BlueGraph.h"
#include "VertexList.h"

int main(int argc, char** argv) {
	// parse arguments
	BlueGraph* bgraph = BlueGraph::getInstance();

	BgVertexListInMem* vertices_init = new BgVertexListInMem(BGKEY_BINARY32, BGVAL_BINARY32);
	vertices_init->addVal(12,1);
	vertices_init->addVal(13,1);

	// bgraph.convertGraph(argv..., argv..., FROM_FORMAT, TO_FORMAT); // e.g., BINARY_64 BINARY_31?
	// bgraph.convertVertices(argv..., argv..., FROM_FORMAT, TO_FORMAT);
	
	BgEdgeList* graph = bgraph->LoadEdges("../../../twitter/twitter_ridx_32.dat", "../../../twitter/twitter_matrix_32.dat", BGKEY_BINARY32);
	//BgVertexList* vertices = bgraph->LoadVertices("initvertex.dat",BGKEY_BINARY32,BGVAL_BINARY32);

	BgVertexList* resv = bgraph->Execute(graph, (BgVertexList*)vertices_init,"newvlist.dat" , BGUSERPROG_SSSP, BGKEY_BINARY32, BGVAL_BINARY32);
	
	BgVertexList* resv2 = bgraph->Execute(graph, resv,"newvlist2.dat" , BGUSERPROG_SSSP, BGKEY_BINARY32, BGVAL_BINARY32);

	// BVertices* nvertices = bgraph.execute(graph, vertices, bv, "newvertexlist")
	// BVertices* nvertices = bgraph.executeHw(graph, vertices, bvhw, "newvertexlist_")


	// BVertices* tv = bgraph->verticesAnd(nvertices, vertices) verticesSubtract verticesOr
	// bgraph->export






	return 0;
}
