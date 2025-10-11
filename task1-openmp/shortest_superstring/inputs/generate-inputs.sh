g++ -std=c++11 -O3 input-generator.cc -o input-gen

echo "ABCD" | ./input-gen > input_24.txt
echo "ABCDE" | ./input-gen > input_120.txt
echo "ABCDEF" | ./input-gen > input_720.txt