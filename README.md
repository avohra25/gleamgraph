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
| `gleamgraph/shortest` | Dijkstra with path reconstruction |

More algorithms (negative weights, connectivity, spanning trees, flows) are
on the way.

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

## License

MIT
