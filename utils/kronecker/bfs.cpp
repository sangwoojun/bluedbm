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

uint64_t last_idx_page = 0;
uint64_t idx_page_cnt = 0;
uint64_t last_mat_page = 0;
uint64_t mat_page_cnt = 0;
void traverse_node(uint64_t node, FILE* fidx, FILE* fmat, int perword) {
	uint64_t idxoff = node*sizeof(uint64_t);
	fseek(fidx, idxoff, SEEK_SET);
	uint64_t matoffv[2] = {LLU_MAX,LLU_MAX};
	fread(matoffv, sizeof(uint64_t),2,fidx);
	uint64_t matoff =matoffv[0];
	uint64_t bytecount = matoffv[1]-matoffv[0];

	uint64_t idxpoff = (idxoff>>13);
	if ( idxpoff != last_idx_page ) {
		last_idx_page = idxpoff;
		idx_page_cnt++;
	}
	idxpoff = ((idxoff+8)>>13);
	if ( idxpoff != last_idx_page ) {
		last_idx_page = idxpoff;
		idx_page_cnt++;
	}

		
	uint64_t last_edge = 0;
	fseek(fmat, matoff, SEEK_SET);

	uint64_t matpoff = (matoff*4/perword)>>13;
	uint64_t matpoff2 = ((matoff+bytecount)*4/perword)>>13;
	for ( uint64_t mio = matpoff; mio <= matpoff2; mio++ ) {
		if ( last_mat_page != mio ) {
			last_mat_page = mio;
			mat_page_cnt++;
		}
	}

	for ( uint64_t i = 0; i < bytecount/sizeof(uint64_t); i++ ) {
		uint64_t edge = 0;
		if ( fread(&edge, sizeof(uint64_t), 1, fmat) == 0 ) break;

		if ( visited.find(edge) != visited.end() ) continue;
		
		if ( frontier.count(edge) > 0 ) {
			frontier[edge] = frontier[edge]+1;
			printf( "jj!\n" ); fflush(stdout);
		}
		else frontier[edge] = 1;
		if ( edge < last_edge ) {
			printf( "%ld smaller than last %ld!\n", edge, last_edge );
			fflush(stdout);
		}

		//if ( frontier.find(edge) == frontier.end() ) frontier[edge] = 1;
		//else frontier[edge] = frontier[edge]+1;
		visited[edge] = node;
	} 
}

int main(int argc, char** argv) {
	if ( argc < 3 ) {
		fprintf(stderr, "usage: %s [index filename] [matrix filename] [scale]\n", argv[0]);
		exit(1);
	}

	int perword = 8;

	FILE* fidx = fopen(argv[1], "rb");
	FILE* fmat = fopen(argv[2], "rb");
	uint64_t scale = atoi(argv[3]);
	if ( argc >=5 ) {
		perword = atoi(argv[4]);
		printf( "Packing %d per word\n", perword );
	}
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
	
	srand(time(NULL));

	for ( int r = 0; r < rcount; r++ ) {
		uint64_t src = llrand() & nmask;
		uint64_t dst = llrand() & nmask;

		printf("Starting bfs\nSrc: %lu Dst: %lu\n", src,dst);
		visited.clear();
		frontier.clear();
		frontier[src] = 1;
		visited[src] = src;

		bool found = false;

		std::list<uint64_t> current;

		while (!frontier.empty() && found == false) {
			last_idx_page = -1;
			idx_page_cnt = 0;
			last_mat_page = -1;
			mat_page_cnt = 0;

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
				traverse_node(*it, fidx, fmat, perword);
			}
			printf( "Pages -- %ld + %ld = %ld  %ld\n", idx_page_cnt, mat_page_cnt, idx_page_cnt+mat_page_cnt, current.size() );
			fflush(stdout);
			current.clear();
		}
		
		printf("%s %lu\n", found?"Discovered":"Not discovered", dst);
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
