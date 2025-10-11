.PHONY = all clean

all : shsup_par

clean:
	rm -rf shsup_par

shsup_par: shortest_superstring_parallel.cc
	$(CXX) -std=c++11 -Wall -O3 -fopenmp shortest_superstring_parallel.cc -o shsup_par