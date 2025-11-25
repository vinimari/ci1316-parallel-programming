# makefile
MPICXX ?= mpicxx
CXXFLAGS ?= -std=c++11 -Wall -O3
TARGET := shsup_par
SRC := shortest_superstring_parallel.cc

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SRC)
	$(MPICXX) $(CXXFLAGS) $(SRC) -o $(TARGET)

clean:
	rm -f $(TARGET)
