.PHONY = all clean bin

all : bin

bin : shsup_seq

clean:
	rm -rf shsup_seq

shsup_seq: shortest_superstring.cc
	$(CXX) -std=c++11 -Wall -O3 shortest_superstring.cc -o shsup_seq

