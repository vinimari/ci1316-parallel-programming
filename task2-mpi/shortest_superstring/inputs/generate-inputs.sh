#!/bin/bash

# Compile the input generator
g++ -std=c++11 -O3 input-generator.cc -o input-gen

echo "ABCD" | ./input-gen > input_24_4.txt
echo "ABCDE" | ./input-gen > input_120_5.txt
echo "ABCDEF" | ./input-gen > input_720_6.txt

echo ""
echo "All input files generated successfully!"
ls -lh input_*.txt