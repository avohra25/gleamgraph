# gleamgraph

Graph algorithms in pure [Gleam](https://gleam.run), with no dependencies
beyond `gleam_stdlib`. Graphs are immutable values, every algorithm is
deterministic, and the test suite checks each algorithm against a slow,
obviously-correct reference on hundreds of seeded random graphs.

## Status

| Module | What it does |
| --- | --- |
| `gleamgraph/graph` | Immutable directed/undirected weighted multigraph over `Int` nodes |
| `gleamgraph/heap` | Persistent pairing heap (min-priority queue) |
| `gleamgraph/traverse` | BFS (order, layers, hop distances), DFS preorder, reachability, topological sort with cycle witness |
| `gleamgraph/disjoint` | Persistent union-find with union by rank and path compression |
| `gleamgraph/components` | Connected components, Tarjan SCC, condensation DAG, bridges, articulation points |
| `gleamgraph/mst` | Kruskal and Prim minimum spanning forests |
| `gleamgraph/shortest` | Dijkstra, Bellman-Ford with negative-cycle witnesses, DAG shortest paths, Floyd-Warshall, A* |

Max flow and bipartite matching are on the way.

## Quick start

```sh
gleam test   # run the test suite
gleam run    # run a small demo
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

## Negative weights

`shortest.bellman_ford` handles negative edges and, when a negative cycle is
reachable, returns `Error(NegativeCycle(cycle))` with an actual cycle you
can inspect:

```gleam
let g = graph.from_edges(graph.Directed, [#(0, 1, 1), #(1, 2, -1), #(2, 3, -1), #(3, 1, -1)])
shortest.bellman_ford(g, 0)   // Error(NegativeCycle([1, 2, 3]))
```

`floyd_warshall` returns all-pairs distances as a `Dict(#(Int, Int), Int)`
and reports negative cycles the same way. `astar` takes any admissible
heuristic and re-expands nodes when needed, so it stays optimal even when
the heuristic is not consistent.

## License

MIT
