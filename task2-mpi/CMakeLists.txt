cmake_minimum_required(VERSION 4.0)
project(task2_mpi)

set(CMAKE_CXX_STANDARD 14)

add_executable(task2_mpi
        shortest_superstring/inputs/input-generator.cc
        shortest_superstring/parallel/shortest_superstring_parallel.cc)
