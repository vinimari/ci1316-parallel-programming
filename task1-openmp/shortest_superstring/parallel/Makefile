.PHONY = all clean

all : shsup

clean:
	rm -rf shsup

shsup: shortest_superstring_parallel.cc
	$(CXX) -std=c++11 -Wall -O3 -fopenmp shortest_superstring_parallel.cc -o shsup_par