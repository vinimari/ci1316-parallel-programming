#!/bin/bash
set -euo pipefail

# generate-inputs.sh
# Gera arquivos de entrada com N linhas, cada linha com LENGTH caracteres.

generate() {
	local lines=$1
	local length=$2
	local out=$3

	# Use base64 from /dev/urandom, keep alphanumeric chars, fold to length and take needed lines
		# The pipeline may get a SIGPIPE when `head` exits early; with `set -euo pipefail`
		# that would abort the script. Appending `|| true` prevents the script
		# from exiting on SIGPIPE while still producing the file.
		base64 /dev/urandom | tr -dc 'A-Z' | fold -w "${length}" | head -n "${lines}" > "${out}" || true
}

echo "Gerando arquivos de entrada..."

generate 100 20 input_100_20.txt
generate 150 20 input_150_20.txt
generate 200 20 input_200_20.txt
generate 300 20 input_300_20.txt    

echo ""
echo "Arquivos gerados com sucesso:"
ls -lh input_*_20.txt