#include <algorithm>
#include <iostream>
#include <set>
#include <string>
#include <utility>
#include <vector>
#include <mpi.h>
#include <cstring>

#define standard_input  std::cin
#define standard_output std::cout

using Boolean = bool ;
using Size    = std::size_t ;
using String  = std::string ;

using InStream  = std::istream ;
using OutStream = std::ostream ;

template <typename T, typename U>
using Pair = std::pair <T, U> ;

template <typename T, typename C = std::less <T>>
using Set = std::set <T> ;

template <typename T>
using SizeType = typename T :: size_type ;

template <typename C> inline auto
size (const C& x) -> SizeType <C>
{
    return x.size () ;
}

template <typename C> inline auto
at_least_two_elements_in (const C& c) -> Boolean
{
    return size (c) > SizeType <C> (1) ;
}

template <typename T> inline auto
first_element (const Set <T>& x) -> T
{
    return *(x.begin ()) ;
}

template <typename T> inline auto
second_element (const Set <T>& x) -> T
{
    return *(std::next (x.begin ())) ;
}

template <typename T> inline auto
remove (Set <T>& x, const T& e) -> Set <T>&
{
    x.erase (e) ;
    return x ;
}

template <typename T> inline auto
push (Set <T>& x, const T& e) -> Set <T>&
{
    x.insert (e) ;
    return x ;
}

template <typename C> inline auto
empty (const C& x) -> Boolean
{
    return x.empty () ;
}

Boolean is_prefix (const String& a, const String& b)
{
    if (size (a) > size (b))
        return false ;
    if ( !
            ( std::mismatch
                ( a.begin ()
                , a.end   ()
                , b.begin () )
                    .first == a.end () ) )
        return false ;
    return true ;
}

inline auto
suffix_from_position (const String& x, SizeType <String> i) -> String
{
    return x.substr (i) ;
}

inline auto
remove_prefix (const String& x, SizeType <String> n) -> String
{
    if (size (x) > n)
        return suffix_from_position (x, n) ;
    return x ;
}

auto
all_suffixes (const String& x) -> Set <String>
{
    Set <String> ss ;
    SizeType <String> n = size (x) ;
    while (-- n) {
        ss.insert (x.substr (n)) ;
    }
    return ss ;
}

auto
commom_suffix_and_prefix (const String& a, const String& b) -> String
{
    if (empty (a)) return "" ;
    if (empty (b)) return "" ;
    String x = "" ;
    for (const String& s : all_suffixes (a)) {
        if (is_prefix (s, b) && size (s) > size (x)) {
            x = s ;
        }
    }
    return x ;
}

inline auto
overlap_value (const String& s, const String& t) -> SizeType <String>
{
    return size (commom_suffix_and_prefix (s, t)) ;
}

auto
overlap (const String& s, const String& t) -> String
{
    String c = commom_suffix_and_prefix (s, t) ;
    return s + remove_prefix (t, size (c)) ;
}

inline auto
pop_two_elements_and_push_overlap
        (Set <String>& ss, const Pair <String, String>& p) -> Set <String>&
{
    ss = remove (ss, p.first)  ;
    ss = remove (ss, p.second) ;
    ss = push   (ss, overlap (p.first, p.second)) ;
    return ss ;
}

auto
all_distinct_pairs (const Set <String>& ss) -> Set <Pair <String, String>>
{
    // Convert set to vector for fast index access
    std::vector<String> vec(ss.begin(), ss.end());
    Size n = vec.size();

    Set <Pair <String, String>> result;

    for (Size i = 0; i < n; ++i) {
        for (Size j = 0; j < n; ++j) {
            if (i != j) {
                result.insert(std::make_pair(vec[i], vec[j]));
            }
        }
    }
    return result;
}

/*
 * PARALELIZAÇÃO 2: highest_overlap_value()
 *
 * ESTRATÉGIA:
 * - Converter set para vector
 * - Cada thread procura o máximo em sua partição
 * - Usar critical section para atualizar máximo global
 *
 * VANTAGENS:
 * - Paraleliza o cálculo mais custoso (overlap_value)
 * - Apenas leitura dos dados (sem race conditions)
 * - Schedule dynamic: balanceia carga (overlap_value varia muito)
 *
 * DESVANTAGENS:
 * - Critical section serializa atualizações do máximo
 * - Conversão set→vector tem overhead
 *
 * ALTERNATIVA MELHOR:
 * - Usar reduction customizado (mais complexo de implementar)
 * - Usar array de máximos locais + reduce manual
 *
 * IMPLEMENTAÇÃO ATUAL (simplificada):
 * - Máximo local por thread
 * - Critical section para comparar com global
 */
auto
highest_overlap_value
        (const Set <Pair <String, String>>& sp) -> Pair <String, String>
{
    // This function is no longer used in MPI version. Keep simple sequential scan
    if (sp.empty()) {
        return Pair<String, String>("", "");
    }
    std::vector<Pair<String, String>> vec(sp.begin(), sp.end());
    Size n = vec.size();
    Pair <String, String> best_pair = vec[0];
    Size max_overlap = overlap_value(best_pair.first, best_pair.second);
    for (Size i = 1; i < n; ++i) {
        Size ov = overlap_value(vec[i].first, vec[i].second);
        if (ov > max_overlap || (ov == max_overlap && vec[i] < best_pair)) {
            max_overlap = ov;
            best_pair = vec[i];
        }
    }
    return best_pair;
}

auto
pair_of_strings_with_highest_overlap_value
        (const Set <String>& ss) -> Pair <String, String>
{
    return highest_overlap_value (all_distinct_pairs (ss)) ;
}

// Helper: broadcast a vector<String> from root to all ranks
inline void
broadcast_string_vector(std::vector<String>& vec, int root, MPI_Comm comm)
{
    int rank;
    MPI_Comm_rank(comm, &rank);

    int n = 0;
    if (rank == root) n = int(vec.size());
    MPI_Bcast(&n, 1, MPI_INT, root, comm);

    std::vector<int> lengths(n);
    if (rank == root) {
        for (int i = 0; i < n; ++i) lengths[i] = int(vec[i].size());
    }
    if (n > 0) MPI_Bcast(lengths.data(), n, MPI_INT, root, comm);

    int total = 0;
    for (int i = 0; i < n; ++i) total += lengths[i];

    std::vector<char> buffer(total);
    if (rank == root) {
        int off = 0;
        for (int i = 0; i < n; ++i) {
            if (lengths[i] > 0) {
                std::memcpy(buffer.data() + off, vec[i].data(), lengths[i]);
                off += lengths[i];
            }
        }
    }
    if (total > 0) MPI_Bcast(buffer.data(), total, MPI_CHAR, root, comm);

    if (rank != root) {
        vec.clear();
        vec.reserve(n);
        int off = 0;
        for (int i = 0; i < n; ++i) {
            vec.emplace_back(std::string(buffer.data() + off, lengths[i]));
            off += lengths[i];
        }
    }
}

// MPI-parallel shortest superstring: ranks collaboratively find best pair
auto
shortest_superstring_mpi(Set <String> t, MPI_Comm comm) -> String
{
    int rank, nprocs;
    MPI_Comm_rank(comm, &rank);
    MPI_Comm_size(comm, &nprocs);

    std::vector<String> vec(t.begin(), t.end());
    int root = 0;

    // Initial broadcast so all ranks have the vector
    broadcast_string_vector(vec, root, comm);

    while (int(vec.size()) > 1) {
        int n = int(vec.size());

        // Each rank searches a subset of i indices: i = rank; i < n; i += nprocs
        int local_i = -1, local_j = -1;
        unsigned long long local_ov = 0ULL;
        for (int i = rank; i < n; i += nprocs) {
            for (int j = 0; j < n; ++j) {
                if (i == j) continue;
                unsigned long long ov = overlap_value(vec[i], vec[j]);
                if (local_i == -1
                    || ov > local_ov
                    || (ov == local_ov && std::make_pair(vec[i], vec[j]) < std::make_pair(vec[local_i], vec[local_j])))
                {
                    local_ov = ov;
                    local_i = i;
                    local_j = j;
                }
            }
        }

        if (local_i == -1) {
            local_i = 0; local_j = (n > 1 ? 1 : 0); local_ov = 0ULL;
        }

        // Gather local results at root
        std::vector<int> all_i, all_j;
        std::vector<unsigned long long> all_ov;
        if (rank == root) {
            all_i.resize(nprocs);
            all_j.resize(nprocs);
            all_ov.resize(nprocs);
        }

        MPI_Gather(&local_i, 1, MPI_INT, (rank == root ? all_i.data() : nullptr), 1, MPI_INT, root, comm);
        MPI_Gather(&local_j, 1, MPI_INT, (rank == root ? all_j.data() : nullptr), 1, MPI_INT, root, comm);
        MPI_Gather(&local_ov, 1, MPI_UNSIGNED_LONG_LONG, (rank == root ? all_ov.data() : nullptr), 1, MPI_UNSIGNED_LONG_LONG, root, comm);

        int best_i = 0, best_j = 0;
        unsigned long long best_ov = 0ULL;

        if (rank == root) {
            bool set = false;
            for (int r = 0; r < nprocs; ++r) {
                int ii = all_i[r];
                int jj = all_j[r];
                unsigned long long ov = all_ov[r];
                if (!set || ov > best_ov || (ov == best_ov && std::make_pair(vec[ii], vec[jj]) < std::make_pair(vec[best_i], vec[best_j]))) {
                    best_ov = ov; best_i = ii; best_j = jj; set = true;
                }
            }

            String merged = overlap(vec[best_i], vec[best_j]);
            if (best_i > best_j) std::swap(best_i, best_j);
            vec.erase(vec.begin() + best_j);
            vec.erase(vec.begin() + best_i);
            vec.push_back(merged);
        }

        // Broadcast updated vector for next iteration
        broadcast_string_vector(vec, root, comm);
    }

    if (rank == 0) {
        if (vec.empty()) return "";
        return vec[0];
    }
    return String("");
}

auto
shortest_superstring (Set <String> t) -> String
{
    if (empty (t)) return "" ;
    while (at_least_two_elements_in (t)) {
        t = pop_two_elements_and_push_overlap
            ( t
            , pair_of_strings_with_highest_overlap_value (t) ) ;
    }
    return first_element (t) ;
}

inline auto
write_string_and_break_line (OutStream& out, String s) -> void
{
    out << s << std::endl ;
}

inline auto
read_size (InStream& in) -> Size
{
    Size n ;
    in >>  n ;
    return n ;
}

inline auto
read_string (InStream& in) -> String
{
    String s ;
    in >>  s ;
    return s ;
}

auto
read_strings_from_standard_input () -> Set <String>
{
    using N = SizeType <Set <String>> ;
    Set <String> x ;
    N n = N (read_size (standard_input)) ;
    while (n --) x.insert (read_string (standard_input)) ;
    return x ;
}

inline auto
write_string_to_standard_ouput (const String& s) -> void
{
    write_string_and_break_line (standard_output, s) ;
}

auto
main (int argc, char const* argv[]) -> int
{
    MPI_Init(nullptr, nullptr);
    int rank = 0;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);

    Set <String> ss;
    if (rank == 0) {
        ss = read_strings_from_standard_input();
    }

    String result = shortest_superstring_mpi(ss, MPI_COMM_WORLD);

    if (rank == 0) {
        write_string_to_standard_ouput(result);
    }

    MPI_Finalize();
    return 0 ;
}