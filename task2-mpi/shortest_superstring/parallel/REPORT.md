# Relatório: Paralelização com MPI — Shortest Superstring

**Resumo**

Convertemos a implementação anterior (que usava OpenMP) para uma versão baseada em MPI voltada para execução distribuída em múltiplos processos. O objetivo principal foi paralelizar a etapa mais custosa: calcular o par de strings com maior overlap entre todos os pares distintos.

**Decisões de projeto e justificativas**

- Modelo de paralelismo: escolhi MPI (processos) em vez de threads porque o pedido explicitou MPI; MPI é mais adequado para execução em clusters e máquinas com múltiplos nós. Mantive a lógica central do algoritmo (greedy merge of best-overlap pairs) para preservar correção e comparabilidade.

- Distribuição de trabalho: ao invés de materializar explicitamente todos os pares (que pode crescer O(n^2)), distribuí as iterações por índice `i` entre ranks: cada processo toma responsabilidade por `i` = rank, rank + nprocs, ... e calcula os melhores pares locais (i,j). Isso reduz memória temporária e aproveita balanceamento simples.

- Comunicação: cada iteração do laço global (redução de vetor de strings) segue este protocolo:
  - `broadcast_string_vector`: o root (rank 0) mantém a lista de strings e faz broadcast compactado (tamanhos + buffer contínuo de bytes) para todos os ranks.
  - Cada rank computa seu melhor par local (índices e valor de overlap) e envia (MPI_Gather) para o root.
  - O root reduz (seleciona o melhor par global), aplica o merge localmente (remove dois elementos e insere a string mesclada) e volta a broadcastar a nova lista.

- Formato de dados: usei um esquema simples e eficiente para broadcast de vetores de strings: primeiro o número de strings, depois um array de comprimentos, e finalmente um buffer concatenado. Isso evita múltiplos calls MPI_Bcast por string e minimiza overhead.

- Ordem e determinismo: para desempates com o mesmo valor de overlap, comparei pares lexicograficamente (`std::pair<string,string>`) para garantir comportamento determinístico entre execuções.

**Complexidade**

- Cálculo de overlaps: cada iteração onde vetor tem tamanho `n` faz O(n^2) cálculos de overlap no total. Com `p` processos, cada rank faz aproximadamente O(n^2 / p) trabalho.

- Comunicação: cada iteração faz um `Bcast` do vetor de strings (custo proporcional ao total de bytes) e três `Gather` com O(p) mensagens com poucos bytes. O custo de comunicação pode se tornar dominante se `n` for pequeno ou se o número total de caracteres for grande.

**Vantagens e limitações**

- Vantagens:
  - Simplicidade: protocolo claro com apenas Gather e Bcast por iteração.
  - Escalabilidade a nível de processos para casos em que `n` (número de strings) é suficientemente grande.
  - Reuso do código lógico existente — mantém corretude conhecida.

- Limitações:
  - O algoritmo é inerentemente iterativo (merge greedy), cada etapa reduz `n` em 1, exigindo sincronização a cada passo.
  - A comunicação do vetor completo a cada iteração pode ser custosa; otimizações possíveis:
    - Enviar apenas índices ou enviar updates incrementais ao invés do vetor inteiro.
    - Usar uma estratégia hierárquica (tree-based reduce) para diminuir custo de gather/broadcast.
    - Balanceamento dinâmico mais sofisticado com distribuição de pares (i,j) em blocos ao invés de `i` intercalados.

**Testes e verificação**

- O root (rank 0) ainda realiza a leitura da entrada padrão (mesma interface do executável sequencial). Para testar localmente com 4 processos:

```
mpicxx -O2 -std=c++17 -o shsup_par_mpi shortest_superstring_parallel.cc
mpirun -n 4 ./shsup_par_mpi < input_24_4.txt
```

- Recomenda-se comparar a saída com a versão sequencial (`shsup_seq`) para verificar correção.

**Instruções de build e execução**

- Compilar:

```
mpicxx -O2 -std=c++17 -o shsup_par_mpi shortest_superstring_parallel.cc
```

- Rodar (exemplo):

```
mpirun -n 4 ./shsup_par_mpi < inputs/input_24_4.txt
```

- Observações:
  - Em clusters use `mpirun`/`mpiexec` conforme seu scheduler (Slurm, PBS, etc.).
  - Ajuste `-O2`/`-O3` e flags de link conforme necessário.

**Possíveis melhorias futuras**

- Evitar broadcast total do vetor: comunicar apenas os índices e strings afetadas pelo merge.
- Implementar `allreduce` custom para reduzir o melhor par sem usar `Gather`.
- Uso de compressão/serialização mais eficiente quando as strings forem longas.

---

Se desejar, posso:
- Ajustar o algoritmo para reduzir comunicação incrementalmente.
- Implementar uma versão que usa `MPI_Allreduce` com um operador customizado para encontrar o melhor par.
- Rodar testes automatizados na sua árvore de testes existente e gerar tempos de comparação.
