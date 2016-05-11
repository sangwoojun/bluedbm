#include <map>
#include <string>

#ifndef __SMITHWATERMAN__H__
#define __SMITHWATERMAN__H__

//std::map<string, int> blosum;

typedef struct {
	char* desc;
	char* seq;
	int score;
}Protein ;



int smithwatermandist(char* a, char* b);

#endif
