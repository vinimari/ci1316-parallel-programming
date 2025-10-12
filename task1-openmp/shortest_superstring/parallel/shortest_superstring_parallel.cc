#include <algorithm>
#include <iostream>
#include <set>
#include <string>
#include <utility>
#include <vector>
#include <omp.h>

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

    #pragma omp parallel
    {
        // Set local for each thread (avoids contention)
        Set<Pair<String, String>> local_pairs;

        // schedule(static): divides iterations evenly between threads
        // Good choice because each iteration has a similar cost
        #pragma omp for schedule(static)
        for (Size i = 0; i < n; ++i) {
            for (Size j = 0; j < n; ++j) {
                if (i != j) {
                    local_pairs.insert(std::make_pair(vec[i], vec[j]));
                }
            }
        }

        // Merge: only 1 synchronization per thread
        #pragma omp critical
        {
            result.insert(local_pairs.begin(), local_pairs.end());
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
    if (sp.empty()) {
        return Pair<String, String>("", "");
    }

    std::vector<Pair<String, String>> vec(sp.begin(), sp.end());
    Size n = vec.size();

    Pair <String, String> best_pair = vec[0];
    Size max_overlap = overlap_value(best_pair.first, best_pair.second);

    #pragma omp parallel
    {
        // Each thread maintains its own local maximum
        Pair<String, String> local_best = vec[0];
        Size local_max = overlap_value(local_best.first, local_best.second);

        // schedule(dynamic, 4):
        // - Variable-length tasks (strings of different sizes)
        // - Chunk size 4: balances overhead vs. load balancing
        #pragma omp for schedule(dynamic, 4)
        for (Size i = 0; i < n; ++i) {
            Size ov = overlap_value(vec[i].first, vec[i].second);
            if (ov > local_max || (ov == local_max && vec[i] < local_best)) {
                local_max = ov;
                local_best = vec[i];
            }
        }

        // Update global maximum in critical region
        // Only N threads accesses (low contention)
        #pragma omp critical
        {
            if (local_max > max_overlap || (local_max == max_overlap && local_best < best_pair)) {
                max_overlap = local_max;
                best_pair = local_best;
            }
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
    Set <String> ss = read_strings_from_standard_input () ;
    write_string_to_standard_ouput (shortest_superstring (ss)) ;
    return 0 ;
}