CC=g++
CFLAGS=-Wall -pedantic -lpthread -O3
BLUEGRAPHDIR=../../src/
CPPFILES=main.cpp  $(wildcard $(BLUEGRAPHDIR)/*.cpp)
BLUEGRAPHINCLUDE= -I $(BLUEGRAPHDIR)/

#USERFLAGS=-DKEY64

all: $(CPPFILES)
	mkdir -p obj
	$(CC) -o obj/main $(CPPFILES) $(BLUEGRAPHINCLUDE) $(CFLAGS)
