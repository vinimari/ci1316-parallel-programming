#!/usr/bin/env python3
"""
Gerador de entradas para o Shortest Superstring Problem
Gera strings com sobreposições controladas para testes realísticos
"""

import random
import sys

def generate_overlapping_strings(n, min_len=5, max_len=15, overlap_prob=0.7):
    """
    Gera N strings com probabilidade de sobreposição

    Args:
        n: número de strings
        min_len: tamanho mínimo de cada string
        max_len: tamanho máximo de cada string
        overlap_prob: probabilidade de ter sobreposição entre strings consecutivas
    """
    alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    strings = set()

    # Primeira string aleatória
    first_len = random.randint(min_len, max_len)
    current = ''.join(random.choices(alphabet, k=first_len))
    strings.add(current)

    # Gerar strings restantes com possível sobreposição
    while len(strings) < n:
        if random.random() < overlap_prob and len(current) >= 3:
            # Criar string com sobreposição
            overlap_size = random.randint(2, min(5, len(current) - 1))
            suffix = current[-overlap_size:]
            new_len = random.randint(min_len, max_len)
            rest = ''.join(random.choices(alphabet, k=new_len - overlap_size))
            new_string = suffix + rest
        else:
            # Criar string completamente aleatória
            new_len = random.randint(min_len, max_len)
            new_string = ''.join(random.choices(alphabet, k=new_len))

        if new_string not in strings and len(new_string) >= min_len:
            strings.add(new_string)
            current = new_string

    return sorted(strings)

def generate_permutation_strings(base_string):
    """
    Gera todas as permutações de uma string base
    Útil para testes com tamanho controlado
    """
    from itertools import permutations
    perms = set([''.join(p) for p in permutations(base_string)])
    return sorted(perms)

def write_input_file(strings, filename):
    """Escreve arquivo de entrada no formato esperado"""
    with open(filename, 'w') as f:
        f.write(f"{len(strings)}\n")
        for s in strings:
            f.write(f"{s}\n")
    print(f"✓ Gerado: {filename} ({len(strings)} strings)")

def main():
    print("=== Gerador de Entradas para SSP ===\n")

    # ENTRADA TINY: Para testes rápidos de corretude
    print("1. Entrada TINY (debug):")
    tiny = ["ABC", "BCD", "CDE", "DEF"]
    write_input_file(tiny, "input_tiny.txt")

    # ENTRADA SMALL: ~100 strings
    print("\n2. Entrada SMALL (~100 strings):")
    small = generate_overlapping_strings(100, min_len=5, max_len=10, overlap_prob=0.6)
    write_input_file(small, "input_small.txt")

    # ENTRADA MEDIUM: ~500 strings (tempo sequencial ~10-30s)
    print("\n3. Entrada MEDIUM (~500 strings):")
    medium = generate_overlapping_strings(500, min_len=6, max_len=12, overlap_prob=0.7)
    write_input_file(medium, "input_medium.txt")

    # ENTRADA LARGE: ~1000 strings (tempo sequencial ~60-120s)
    print("\n4. Entrada LARGE (~1000 strings):")
    large = generate_overlapping_strings(1000, min_len=7, max_len=15, overlap_prob=0.7)
    write_input_file(large, "input_large.txt")

    # ENTRADA XLARGE: ~2000 strings (escalabilidade forte)
    print("\n5. Entrada XLARGE (~2000 strings):")
    xlarge = generate_overlapping_strings(2000, min_len=8, max_len=15, overlap_prob=0.8)
    write_input_file(xlarge, "input_xlarge.txt")

    # ENTRADA com permutações (para input-generator.cc)
    print("\n6. Entrada PERMUTATIONS (6! = 720 strings):")
    perms = generate_permutation_strings("ABCDEF")
    write_input_file(perms, "input_perm720.txt")

if __name__ == "__main__":
    # Seed para reprodutibilidade
    random.seed(42)
    main()