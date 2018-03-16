#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>

int main(int argc, char** argv) {
	if ( argc < 2 ) {
		fprintf(stderr, "usage: %s filename [32bit?] [text source?]\n", argv[0]);
		exit(1);
	}

	FILE* fin = fopen(argv[1], "rb");
	if ( fin == NULL ) {
		fprintf(stderr, "Filename %s not found\n", argv[1]);
		exit(1);
	}
	FILE* fint = fopen(argv[1], "r");


	bool file32 = false;
	if ( argc >= 3 ) {
		file32 = true;
	}
	
	bool textsource = false;
	if ( argc >= 4 ) {
		textsource = true;
	}

	printf( "Starting encoding!\n Input: %s Output: %dbit\n", textsource?"text":"binary", file32?32:64 );

	FILE* fidx = fopen("ridx.dat", "wb");
	FILE* fdat = fopen("matrix.dat", "wb");

	uint64_t cur_node = 0;
	uint64_t cur_boff = 0; // byte offset of matrix

	uint64_t cur[2] = {0,0};
	fwrite(&cur_boff, sizeof(uint64_t), 1, fidx);
	uint64_t last_edge = 0;//xFFFFFFFFFFFFFFFF;

	uint64_t total_edges = 0;
	uint64_t nodes_noedge = 0;
	char line[256];
	while (!feof(fin)) {
		if ( textsource == true ) {
			if( !fgets(line, 256, fint) ) break;
			char* from = strtok(line, " \t");
			char* to = strtok(NULL, " \t");

			cur[0] = atoll(from);
			cur[1] = atoll(to);
		} else {
			if ( fread(cur, sizeof(uint64_t)*2, 1, fin) == 0 ) break;
		}

		uint64_t rnode = cur[0];
		uint64_t redge = cur[1];

		if ( rnode == redge ) continue;
		if ( rnode < cur_node ) {
			printf( "node order wrong! %ld -> %ld\n", cur_node, rnode );
			continue;
		}

		if ( cur_node == rnode ) {
			if ( last_edge > redge ) {
				printf( "edge order wrong! %ld -> %ld\n", last_edge, redge );
				continue;
			}
			if ( last_edge > redge ) {
				printf( "Error!! Dest edge not sorted!\n" ); // FIXME! rnode < cur_node already checks for this...
				exit(1);
			}
			if ( last_edge == redge ) continue;

			if ( file32 ) {
				uint32_t sedge = (uint32_t)redge;
				fwrite(&sedge, sizeof(uint32_t), 1, fdat);
			} else {
				fwrite(&redge, sizeof(uint64_t), 1, fdat);
			}
			if ( file32 ) {
				cur_boff+=sizeof(uint32_t);
			} else {
				cur_boff+=sizeof(uint64_t);
			}
			last_edge = redge;
			total_edges++;
		} else {
			if ( cur_node > rnode ) { // FIXME rnode< cur_node already checks for this
				printf( "Error!! Source node not sorted!\n" );
				exit(0);
			}
			if ( rnode-cur_node > 1 ) {
				nodes_noedge += rnode-cur_node-1;
			}

			while (cur_node < rnode) {
				fwrite(&cur_boff, sizeof(uint64_t), 1, fidx);
				cur_node++;
				//cur_boff+=sizeof(uint64_t);
				//printf("Node %lx Edge boffset %lx\n", cur_node, cur_boff);

			}
			if ( file32 ) {
				uint32_t sedge = (uint32_t)redge;
				fwrite(&sedge, sizeof(uint32_t), 1, fdat);
			} else {
				fwrite(&redge, sizeof(uint64_t), 1, fdat);
			}
			total_edges++;
			if ( file32 ) {
				cur_boff+=sizeof(uint32_t);
			} else {
				cur_boff+=sizeof(uint64_t);
			}
			last_edge = redge;
		}

		if ( total_edges % (1024L*1024L*64L) == 0 ) {
			printf( "Total edges: %ld\n", total_edges );
		}

	}
	printf("Total edges: %ld\n", total_edges);
	printf("Isolated nodes: %ld\n", nodes_noedge);
	fclose(fidx);
}
