# gleamgraph

Graph algorithms in pure [Gleam](https://gleam.run), with no dependencies
beyond `gleam_stdlib`. Graphs are immutable values, every algorithm is
deterministic, and the test suite checks each algorithm against a slow,
obviously-correct reference (brute force or a simpler algorithm) on
hundreds of seeded random graphs.

## What's inside

| Module | What it does |
| --- | --- |
| `gleamgraph/graph` | Immutable directed/undirected weighted multigraph over `Int` nodes |
| `gleamgraph/heap` | Persistent pairing heap (min-priority queue) |
| `gleamgraph/traverse` | BFS (order, layers, hop distances), DFS preorder, reachability, topological sort with cycle witness |
| `gleamgraph/shortest` | Dijkstra, Bellman-Ford with negative-cycle witnesses, DAG shortest paths, Floyd-Warshall, A* |
| `gleamgraph/disjoint` | Persistent union-find with union by rank and path compression |
| `gleamgraph/components` | Connected components, Tarjan SCC, condensation DAG, bridges, articulation points |
| `gleamgraph/mst` | Kruskal and Prim minimum spanning forests |
| `gleamgraph/flow` | Edmonds-Karp maximum flow with a minimum cut |
| `gleamgraph/matching` | Bipartite two-colouring and maximum matching (augmenting paths) |
| `gleamgraph/parse` | Plain-text edge-list reader and writer |

## Quick start

Requires Gleam 1.11+ and Erlang/OTP 26+.

```sh
gleam test                                          # run the test suite
gleam run -- path examples/roads.txt 1 5            # shortest path
gleam run -- maxflow examples/network.txt 0 5       # max flow / min cut
gleam run -- matching examples/jobs.txt             # bipartite matching
gleam run -- help                                   # every command
```

```gleam
import gleamgraph/graph
import gleamgraph/shortest
import gleamgraph/traverse

let g =
  graph.from_edges(graph.Directed, [#(1, 2, 7), #(1, 3, 9), #(3, 2, 1)])

traverse.bfs(g, 1)                // [1, 2, 3]
traverse.topological_sort(g)      // Ok([1, 3, 2])
shortest.shortest_path(g, 1, 2)   // Ok(Ok(#(8, [1, 3, 2])))
```

## Command line

```text
$ gleam run -- maxflow examples/network.txt 0 5
value 23
source side 0 1 2 4
cut 1-3, 4-3, 4-5
```

Commands: `info`, `bfs`, `dfs`, `topo`, `path`, `distances`, `components`,
`scc`, `bridges`, `mst`, `maxflow`, `matching`. Input files look like this:

```text
# comments start with '#'
undirected        # optional header, `directed` is the default
1 2 7             # edge 1 - 2 with weight 7
2 3               # weight defaults to 1
9                 # a lone number declares an isolated node
```

`path` and `distances` switch from Dijkstra to Bellman-Ford automatically
when any weight is negative.

## Design notes

* **Witnesses, not just booleans.** `topological_sort` returns
  `Error(cycle)` with an actual directed cycle; `bellman_ford` and
  `floyd_warshall` return `Error(NegativeCycle(cycle))`; `max_flow` returns
  the minimum cut that proves its value is optimal.
* **Negative weights.** In an undirected graph a negative edge is itself a
  negative cycle (walk it back and forth), and the library reports it that
  way.
* **Multigraphs.** Parallel edges are kept. Shortest paths use the lightest
  one, max flow adds their capacities, and a doubled edge is never a bridge.
* **A\*** re-expands nodes when it finds a cheaper route, so any admissible
  heuristic gives optimal answers, consistent or not.
* **Purely functional.** No mutable state or processes: union-find, Tarjan's
  lowlinks and the residual network are all threaded through persistent
  dictionaries.

## Testing

`gleam test` runs 54 test functions. Beyond hand-checked textbook examples
(CLRS flow network, Dijkstra's road map, the classic 9-node MST), the
randomized tests compare against references:

* Dijkstra and Bellman-Ford against relax-until-stable; negative-cycle
  witnesses are checked to be real cycles of negative weight
* DAG shortest paths and Floyd-Warshall against Bellman-Ford; A* against
  Dijkstra on random weighted grids
* Tarjan SCC against pairwise mutual reachability
* bridges and articulation points against delete-and-count brute force
* Kruskal and Prim against exhaustive search over edge subsets
* max flow against the minimum over every s-t cut, plus capacity and
  conservation checks; matching against exhaustive search and unit-capacity
  max flow
* the pairing heap against `list.sort` and a sorted-list model

All random inputs come from a fixed-seed generator, so failures reproduce.

## License

MIT
