#include <stdio.h>

#include "BlueGraph.h"
#include "VertexList.h"

int main(int argc, char** argv) {
	// parse arguments
	BlueGraph* bgraph = BlueGraph::getInstance();
	BgEdgeList* graph = bgraph->LoadEdges("../../../../../twitter/twitter_ridx_32.dat", "../../../../../twitter/twitter_matrix_32.dat", BGKEY_BINARY32);

	BgVertexListInMem* vertices_init = new BgVertexListInMem(BGKEY_BINARY32, BGVAL_BINARY32);
	vertices_init->addVal(12,1);
	//vertices_init->addVal(13,1);

	BgVertexList* visitedList = (BgVertexList*)(new BgVertexListInMem(BGKEY_BINARY32, BGVAL_BINARY32));
	vertices_init->addVal(12,1);

	BgVertexList* activeList = (BgVertexList*)vertices_init;
	char outfilename[128];
	for(int i = 0; ; i++) {
		printf( "Iteration %d\n", i );
		sprintf(outfilename, "vres%03d.dat", i);
		BgVertexList* resv = bgraph->Execute(graph, activeList,outfilename , BGUSERPROG_SSSP, BGKEY_BINARY32, BGVAL_BINARY32);
		activeList = bgraph->VectorConverged(resv,visitedList, BGUSERPROG_SSSP, "");
		visitedList = bgraph->VectorUnion(resv, visitedList, BGUSERPROG_SSSP, "");

		if ( activeList->IsEmpty() ) break;
	}

	// bgraph.convertGraph(argv..., argv..., FROM_FORMAT, TO_FORMAT); // e.g., BINARY_64 BINARY_31?
	// bgraph.convertVertices(argv..., argv..., FROM_FORMAT, TO_FORMAT);
	
	//BgVertexList* vertices = bgraph->LoadVertices("initvertex.dat",BGKEY_BINARY32,BGVAL_BINARY32);

	//BgVertexList* resv = bgraph->Execute(graph, (BgVertexList*)vertices_init,"newvlist.dat" , BGUSERPROG_SSSP, BGKEY_BINARY32, BGVAL_BINARY32);
	
	//BgVertexList* resv = bgraph->LoadVertices("newvlist.dat",BGKEY_BINARY32,BGVAL_BINARY32);
	//BgVertexList* resv2 = bgraph->Execute(graph, resv,"newvlist2.dat" , BGUSERPROG_SSSP, BGKEY_BINARY32, BGVAL_BINARY32);

	// BVertices* nvertices = bgraph.execute(graph, vertices, bv, "newvertexlist")
	// BVertices* nvertices = bgraph.executeHw(graph, vertices, bvhw, "newvertexlist_")


	// BVertices* tv = bgraph->verticesAnd(nvertices, vertices) verticesSubtract verticesOr
	// bgraph->export






	return 0;
}
