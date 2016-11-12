#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char** argv) {
	if ( argc < 2 ) {
		fprintf(stderr, "usage: %s [filename]\n", argv[0]);
		exit(1);
	}

	FILE* fin = fopen(argv[1], "rb");
	if ( fin == NULL ) {
		fprintf(stderr, "Filename %s not found\n", argv[1]);
		exit(1);
	}

	FILE* fidx = fopen("ridx.dat", "wb");
	FILE* fdat = fopen("matrix.dat", "wb");

	uint64_t cur_node = 0;
	uint64_t cur_boff = 0; // byte offset of matrix

	uint64_t cur[2] = {0,0};
	fwrite(&cur_boff, sizeof(uint64_t), 1, fidx);
	uint64_t last_edge = 0xFFFFFFFFFFFFFFFF;

	uint64_t total_edges = 0;
	uint64_t nodes_noedge = 0;
	while (!feof(fin)) {
		if ( fread(cur, sizeof(uint64_t)*2, 1, fin) == 0 ) break;

		uint64_t rnode = cur[0];
		uint64_t redge = cur[1];

		if ( rnode == redge ) continue;

		if ( cur_node == rnode ) {
			if ( last_edge == redge ) continue;

			fwrite(&redge, sizeof(uint64_t), 1, fdat);
			cur_boff+=sizeof(uint64_t);
			last_edge = redge;
			total_edges++;
		} else {
			if ( rnode-cur_node > 1 ) {
				nodes_noedge += rnode-cur_node-1;
			}

			while (cur_node < rnode) {
				fwrite(&cur_boff, sizeof(uint64_t), 1, fidx);
				cur_node++;
				//cur_boff+=sizeof(uint64_t);
				//printf("Node %lx Edge boffset %lx\n", cur_node, cur_boff);

			}
			fwrite(&redge, sizeof(uint64_t), 1, fdat);
			total_edges++;
			cur_boff+=sizeof(uint64_t);
			last_edge = redge;
		}
	}
	printf("Total edges: %ld\n", total_edges);
	printf("Isolated nodes: %ld\n", nodes_noedge);
	fclose(fidx);
}
