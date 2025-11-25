#!/bin/bash

linha=""
retorno=""

cd results

touch resultado_$1.csv
echo "id,1 thread,2 threads,3 threads,6 threads, 12 threads" > resultado_$1.csv
for i in {1..20}
do
	echo "rodando teste $i"
	linha="$i"
	for j in 1 2 3 6 12
	do
		retorno=$(mpirun --hostfile ./../host.txt -np $j ./../parallel/shsup_par < ./../inputs/input_$1\_20.txt | tail -n 1)
		linha="$linha,$retorno"
	done
	echo "$linha" >> resultado_$1.csv
done