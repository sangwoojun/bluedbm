all:
	mkdir -p obj
	gcc -o obj/generate generate.cpp -Wall -pedantic
	gcc -o obj/sort sort.cpp -Wall -pedantic -g
	gcc -o obj/encode encode.cpp -Wall -pedantic -g
	gcc -o obj/parse parse.cpp -Wall -pedantic -g
	g++ -o obj/bfs bfs.cpp -Wall -pedantic
	g++ -o obj/tostring tostring.cpp -Wall -pedantic
	g++ -o obj/checksort checksort.cpp -Wall -pedantic
clean:
	rm -r obj
