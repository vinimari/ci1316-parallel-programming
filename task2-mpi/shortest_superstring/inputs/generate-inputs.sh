#!/bin/bash
set -euo pipefail

# generate-inputs.sh
# Gera arquivos de entrada com N linhas, cada linha com LENGTH caracteres.

generate() {
	local lines=$1
	local length=$2
	local out=$3

	# Use base64 from /dev/urandom, keep alphanumeric chars, fold to length and take needed lines
	base64 /dev/urandom | tr -dc 'A-Za-z0-9' | fold -w "${length}" | head -n "${lines}" > "${out}"
}

echo "Gerando arquivos de entrada (100, 200, 300 linhas; 30 caracteres por linha)..."

generate 100 30 input_100_30.txt
generate 200 30 input_200_30.txt
generate 300 30 input_300_30.txt

echo ""
echo "Arquivos gerados com sucesso:"
ls -lh input_*_30.txt