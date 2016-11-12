#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

#include <map>
#include <list>
#define LLU_MAX 0xFFFFFFFFFFFFFFFF

uint64_t llrand() {
	uint64_t r = 0;

	for (int i = 0; i < 5; ++i) {
		r = (r << 15) | (rand() & 0x7FFF);
	}

	return r;
}

std::map<uint64_t, uint64_t> visited;
std::list<uint64_t> next;
std::map<uint64_t, int> frontier;
void traverse_node(uint64_t node, FILE* fidx, FILE* fmat) {
	uint64_t idxoff = node*sizeof(uint64_t);
	fseek(fidx, idxoff, SEEK_SET);
	uint64_t matoffv[2] = {LLU_MAX,LLU_MAX};
	fread(matoffv, sizeof(uint64_t),2,fidx);
	uint64_t matoff =matoffv[0];
	uint64_t bytecount = matoffv[1]-matoffv[0];

		
	fseek(fmat, matoff, SEEK_SET);
	for ( uint64_t i = 0; i < bytecount/sizeof(uint64_t); i++ ) {
		uint64_t edge = 0;
		if ( fread(&edge, sizeof(uint64_t), 1, fmat) == 0 ) break;

		if ( visited.find(edge) != visited.end() ) continue;
		
		if ( frontier.find(edge) == frontier.end() ) frontier[edge] = 1;
		else frontier[edge] = frontier[edge]+1;
		visited[edge] = node;
	} 
}

int main(int argc, char** argv) {
	if ( argc < 3 ) {
		fprintf(stderr, "usage: %s [index filename] [matrix filename] [scale]\n", argv[0]);
		exit(1);
	}

	FILE* fidx = fopen(argv[1], "rb");
	FILE* fmat = fopen(argv[2], "rb");
	uint64_t scale = atoi(argv[3]);
	uint64_t nmax = (1<<(scale));
	uint64_t nmask = nmax-1;
	if ( fidx == NULL ) {
		fprintf(stderr, "Filename %s not found\n", argv[1]);
		exit(1);
	}
	if ( fmat == NULL ) {
		fprintf(stderr, "Filename %s not found\n", argv[2]);
		exit(1);
	}
	int rcount = 30;
	
	srand(time(0));

	for ( int r = 0; r < rcount; r++ ) {
		uint64_t src = llrand() & nmask;
		uint64_t dst = llrand() & nmask;

		printf("Starting bfs\nSrc: %ld Dst: %ld\n", src,dst);
		visited.clear();
		frontier.clear();
		frontier[src] = 1;
		visited[src] = src;

		bool found = false;

		std::list<uint64_t> current;

		while (!frontier.empty() && found == false) {
			// loop through frontier
			uint64_t travtotal = 0;
			uint64_t travnodes = 0;
			for ( std::map<uint64_t,int>::iterator it = frontier.begin();
				it != frontier.end(); it++ ) {
				//   check exist!
				if ( it->first == dst ) {
					found = true;
					break;
				}
				current.push_front(it->first);
				travtotal += it->second;
				travnodes += 1;
			}
			frontier.clear();
			double rat = ((double)travtotal)/((double)travnodes);
			printf( "Iterated -- %ld %ld [%ld/%ld](%f)\n", current.size(), visited.size(), travtotal, travnodes, rat );
			fflush(stdout);

			for ( std::list<uint64_t>::iterator it = current.begin();
				it != current.end(); it++ ) {
				traverse_node(*it, fidx, fmat);
			}
			current.clear();
		}
		
		printf("%s %ld\n", found?"Discovered":"Not discovered", dst);
		if ( found ) {
			uint64_t back = visited[dst];
			while (visited[back] != back) {
				printf( "Backtrace: %lu\n", back );
				back = visited[back];
			}
			printf( "Backtrace: %lu\n", back );
		}
		fflush(stdout);
	}
}
