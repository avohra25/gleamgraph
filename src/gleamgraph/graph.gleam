//// An immutable, weighted multigraph over integer node ids.
////
//// Graphs are either `Directed` or `Undirected`. Every edge carries an
//// integer weight (use `1` when you only care about structure). Parallel
//// edges and self-loops are allowed. Adjacency is kept in insertion order,
//// which makes every traversal in this library deterministic.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/set.{type Set}

pub type Kind {
  Directed
  Undirected
}

/// An edge as it was added to the graph.
pub type Edge {
  Edge(from: Int, to: Int, weight: Int)
}

pub opaque type Graph {
  Graph(
    kind: Kind,
    nodes: Set(Int),
    // Adjacency lists are stored newest-first and reversed on read.
    out: Dict(Int, List(#(Int, Int))),
    // All edges, newest-first.
    edges: List(Edge),
    edge_count: Int,
  )
}

/// An empty graph of the given kind.
pub fn new(kind: Kind) -> Graph {
  Graph(kind:, nodes: set.new(), out: dict.new(), edges: [], edge_count: 0)
}

pub fn directed() -> Graph {
  new(Directed)
}

pub fn undirected() -> Graph {
  new(Undirected)
}

pub fn kind(graph: Graph) -> Kind {
  graph.kind
}

pub fn is_directed(graph: Graph) -> Bool {
  graph.kind == Directed
}

/// Add an isolated node. Adding an existing node is a no-op.
pub fn add_node(graph: Graph, node: Int) -> Graph {
  Graph(..graph, nodes: set.insert(graph.nodes, node))
}

/// Add many nodes at once.
pub fn add_nodes(graph: Graph, nodes: List(Int)) -> Graph {
  list.fold(nodes, graph, add_node)
}

/// Add a weighted edge, creating its endpoints if needed. In an undirected
/// graph the edge is traversable in both directions (a self-loop appears
/// once in its node's adjacency list).
pub fn add_edge(graph: Graph, from: Int, to: Int, weight: Int) -> Graph {
  let nodes = graph.nodes |> set.insert(from) |> set.insert(to)
  let out = push(graph.out, from, #(to, weight))
  let out = case graph.kind, from == to {
    Undirected, False -> push(out, to, #(from, weight))
    _, _ -> out
  }
  Graph(
    ..graph,
    nodes:,
    out:,
    edges: [Edge(from, to, weight), ..graph.edges],
    edge_count: graph.edge_count + 1,
  )
}

fn push(
  out: Dict(Int, List(#(Int, Int))),
  key: Int,
  item: #(Int, Int),
) -> Dict(Int, List(#(Int, Int))) {
  case dict.get(out, key) {
    Ok(items) -> dict.insert(out, key, [item, ..items])
    Error(Nil) -> dict.insert(out, key, [item])
  }
}

/// Build a graph from `#(from, to, weight)` triples.
pub fn from_edges(kind: Kind, edges: List(#(Int, Int, Int))) -> Graph {
  list.fold(edges, new(kind), fn(g, e) { add_edge(g, e.0, e.1, e.2) })
}

/// Build a graph from unweighted `#(from, to)` pairs (every weight is 1).
pub fn from_pairs(kind: Kind, pairs: List(#(Int, Int))) -> Graph {
  list.fold(pairs, new(kind), fn(g, e) { add_edge(g, e.0, e.1, 1) })
}

/// All nodes in ascending order.
pub fn nodes(graph: Graph) -> List(Int) {
  graph.nodes |> set.to_list |> list.sort(int.compare)
}

pub fn node_count(graph: Graph) -> Int {
  set.size(graph.nodes)
}

pub fn edge_count(graph: Graph) -> Int {
  graph.edge_count
}

pub fn has_node(graph: Graph, node: Int) -> Bool {
  set.contains(graph.nodes, node)
}

/// True if `to` is adjacent from `from` (either direction when undirected).
pub fn has_edge(graph: Graph, from: Int, to: Int) -> Bool {
  list.any(neighbors(graph, from), fn(n) { n.0 == to })
}

/// Outgoing `#(neighbor, weight)` pairs in insertion order.
pub fn neighbors(graph: Graph, node: Int) -> List(#(Int, Int)) {
  case dict.get(graph.out, node) {
    Ok(items) -> list.reverse(items)
    Error(Nil) -> []
  }
}

/// Just the neighbor ids, in insertion order (duplicates for parallel edges).
pub fn successors(graph: Graph, node: Int) -> List(Int) {
  list.map(neighbors(graph, node), fn(n) { n.0 })
}

pub fn out_degree(graph: Graph, node: Int) -> Int {
  case dict.get(graph.out, node) {
    Ok(items) -> list.length(items)
    Error(Nil) -> 0
  }
}

/// Every edge exactly once, in insertion order.
pub fn edges(graph: Graph) -> List(Edge) {
  list.reverse(graph.edges)
}

/// Every traversable arc: each directed edge once, each undirected
/// (non-loop) edge in both directions.
pub fn arcs(graph: Graph) -> List(Edge) {
  case graph.kind {
    Directed -> edges(graph)
    Undirected ->
      list.flat_map(edges(graph), fn(e) {
        case e.from == e.to {
          True -> [e]
          False -> [e, Edge(e.to, e.from, e.weight)]
        }
      })
  }
}

/// Sum of all edge weights.
pub fn total_weight(graph: Graph) -> Int {
  list.fold(graph.edges, 0, fn(acc, e) { acc + e.weight })
}

/// Reverse every edge. Undirected graphs are returned unchanged.
pub fn reverse(graph: Graph) -> Graph {
  case graph.kind {
    Undirected -> graph
    Directed ->
      list.fold(edges(graph), add_nodes(directed(), nodes(graph)), fn(g, e) {
        add_edge(g, e.to, e.from, e.weight)
      })
  }
}

/// Forget directions: every directed edge becomes an undirected one.
pub fn to_undirected(graph: Graph) -> Graph {
  list.fold(edges(graph), add_nodes(undirected(), nodes(graph)), fn(g, e) {
    add_edge(g, e.from, e.to, e.weight)
  })
}

/// The subgraph induced by `keep`: those nodes and the edges between them.
pub fn induced(graph: Graph, keep: List(Int)) -> Graph {
  let wanted = set.from_list(keep)
  let base = new(graph.kind) |> add_nodes(list.filter(keep, has_node(graph, _)))
  list.fold(edges(graph), base, fn(g, e) {
    case set.contains(wanted, e.from) && set.contains(wanted, e.to) {
      True -> add_edge(g, e.from, e.to, e.weight)
      False -> g
    }
  })
}

/// Apply `f` to every edge weight.
pub fn map_weights(graph: Graph, f: fn(Edge) -> Int) -> Graph {
  list.fold(edges(graph), add_nodes(new(graph.kind), nodes(graph)), fn(g, e) {
    add_edge(g, e.from, e.to, f(e))
  })
}
