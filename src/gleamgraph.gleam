//// gleamgraph: graph algorithms in pure Gleam.
////
//// The library lives in the `gleamgraph/*` modules. This module is the
//// command-line front end: `gleam run -- <command> <file> [args]`.

import gleam/dict
import gleam/int
import gleam/io
import gleam/list
import gleam/result
import gleam/string
import gleamgraph/components
import gleamgraph/flow
import gleamgraph/graph.{type Graph}
import gleamgraph/matching
import gleamgraph/mst
import gleamgraph/parse
import gleamgraph/shortest
import gleamgraph/traverse

@external(erlang, "gleamgraph_ffi", "arguments")
fn arguments() -> List(String)

@external(erlang, "gleamgraph_ffi", "read_file")
fn read_file(path: String) -> Result(String, String)

@external(erlang, "gleamgraph_ffi", "halt")
fn halt(code: Int) -> Nil

pub fn main() -> Nil {
  case run(arguments(), read_file) {
    Ok(output) -> io.print(output)
    Error(message) -> {
      io.println_error("error: " <> message)
      halt(1)
    }
  }
}

pub const usage =
  "usage: gleamgraph <command> <file> [args]

commands:
  info       FILE          node/edge counts and basic properties
  bfs        FILE S        breadth-first order from S
  dfs        FILE S        depth-first preorder from S
  topo       FILE          topological order, or a cycle
  path       FILE S T      shortest path (Dijkstra, or Bellman-Ford if any weight < 0)
  distances  FILE S        shortest distance from S to every reachable node
  components FILE          connected components (direction ignored)
  scc        FILE          strongly connected components
  bridges    FILE          bridges and articulation points
  mst        FILE          minimum spanning forest
  maxflow    FILE S T      maximum flow and a minimum cut
  matching   FILE          maximum matching of a bipartite graph

FILE is an edge list: an optional `directed`/`undirected` header, then one
`from to [weight]` per line ('#' starts a comment).
"

/// Run a CLI command. `read` loads a file's contents; it is a parameter so
/// the CLI can be tested without touching the filesystem.
pub fn run(
  args: List(String),
  read: fn(String) -> Result(String, String),
) -> Result(String, String) {
  case args {
    [] | ["help"] | ["--help"] | ["-h"] -> Ok(usage)
    [command, path, ..rest] -> {
      use text <- result.try(
        read(path) |> result.map_error(fn(e) { path <> ": " <> e }),
      )
      use g <- result.try(
        parse.parse(text)
        |> result.map_error(fn(e) { path <> ": " <> parse.describe(e) }),
      )
      use ints <- result.try(
        list.try_map(rest, int.parse)
        |> result.replace_error("node arguments must be integers"),
      )
      command_for(command, g, ints)
    }
    [command] -> Error("`" <> command <> "` needs a FILE argument\n\n" <> usage)
  }
}

fn command_for(
  command: String,
  g: Graph,
  args: List(Int),
) -> Result(String, String) {
  case command, args {
    "info", [] -> Ok(info(g))
    "bfs", [s] -> needs(g, [s], fn() { line(traverse.bfs(g, s)) })
    "dfs", [s] -> needs(g, [s], fn() { line(traverse.dfs(g, s)) })
    "topo", [] ->
      case traverse.topological_sort(g) {
        Ok(order) -> Ok(line(order))
        Error(cycle) -> Error("graph has a cycle: " <> cycle_text(cycle))
      }
    "path", [s, t] -> needs_result(g, [s, t], fn() { path(g, s, t) })
    "distances", [s] -> needs_result(g, [s], fn() { distances(g, s) })
    "components", [] -> Ok(groups(components.connected_components(g)))
    "scc", [] -> Ok(groups(components.strongly_connected_components(g)))
    "bridges", [] -> Ok(bridges(g))
    "mst", [] -> Ok(spanning(g))
    "maxflow", [s, t] -> needs_result(g, [s, t], fn() { max_flow(g, s, t) })
    "matching", [] ->
      case matching.maximum_matching(g) {
        Ok(pairs) ->
          Ok(
            "size "
            <> int.to_string(list.length(pairs))
            <> "\n"
            <> string.concat(list.map(pairs, fn(p) { pair_text(p) <> "\n" })),
          )
        Error(Nil) -> Error("graph is not bipartite")
      }
    _, _ ->
      Error(
        "unknown command or wrong arguments: " <> command <> "\n\n" <> usage,
      )
  }
}

fn needs(
  g: Graph,
  nodes: List(Int),
  f: fn() -> String,
) -> Result(String, String) {
  needs_result(g, nodes, fn() { Ok(f()) })
}

fn needs_result(
  g: Graph,
  nodes: List(Int),
  f: fn() -> Result(String, String),
) -> Result(String, String) {
  case list.find(nodes, fn(n) { !graph.has_node(g, n) }) {
    Ok(n) -> Error("node " <> int.to_string(n) <> " is not in the graph")
    Error(Nil) -> f()
  }
}

fn info(g: Graph) -> String {
  let kind = case graph.is_directed(g) {
    True -> "directed"
    False -> "undirected"
  }
  let yes_no = fn(b) {
    case b {
      True -> "yes"
      False -> "no"
    }
  }
  [
    "kind        " <> kind,
    "nodes       " <> int.to_string(graph.node_count(g)),
    "edges       " <> int.to_string(graph.edge_count(g)),
    "weight      " <> int.to_string(graph.total_weight(g)),
    "components  " <> int.to_string(components.component_count(g)),
    "scc         "
      <> int.to_string(list.length(components.strongly_connected_components(g))),
    "acyclic     " <> yes_no(graph.is_directed(g) && traverse.is_acyclic(g)),
    "bipartite   " <> yes_no(matching.is_bipartite(g)),
  ]
  |> string.join("\n")
  |> string.append("\n")
}

fn path(g: Graph, s: Int, t: Int) -> Result(String, String) {
  use paths <- result.try(solve(g, s))
  case shortest.distance(paths, t), shortest.path(paths, t) {
    Ok(d), Ok(p) -> Ok("distance " <> int.to_string(d) <> "\n" <> line(p))
    _, _ -> Ok("unreachable\n")
  }
}

fn distances(g: Graph, s: Int) -> Result(String, String) {
  use paths <- result.try(solve(g, s))
  Ok(
    dict.to_list(paths.dist)
    |> list.sort(fn(a, b) { int.compare(a.0, b.0) })
    |> list.map(fn(p) {
      int.to_string(p.0) <> " " <> int.to_string(p.1) <> "\n"
    })
    |> string.concat,
  )
}

fn solve(g: Graph, s: Int) -> Result(shortest.Paths, String) {
  let negative = list.any(graph.edges(g), fn(e) { e.weight < 0 })
  let result = case negative {
    True -> shortest.bellman_ford(g, s)
    False -> shortest.dijkstra(g, s)
  }
  result.map_error(result, fn(e) {
    case e {
      shortest.NegativeCycle(cycle) -> "negative cycle: " <> cycle_text(cycle)
      shortest.UnknownNode(n) ->
        "node " <> int.to_string(n) <> " is not in the graph"
      shortest.NegativeEdge(..) | shortest.NotAcyclic(..) -> "unexpected error"
    }
  })
}

fn bridges(g: Graph) -> String {
  "bridges "
  <> string.join(list.map(components.bridges(g), pair_text), ", ")
  <> "\n"
  <> "articulation points "
  <> string.join(
    list.map(components.articulation_points(g), int.to_string),
    " ",
  )
  <> "\n"
}

fn spanning(g: Graph) -> String {
  let forest = mst.kruskal(g)
  "weight "
  <> int.to_string(forest.weight)
  <> "\n"
  <> string.concat(
    list.map(forest.edges, fn(e) {
      int.to_string(e.from)
      <> " "
      <> int.to_string(e.to)
      <> " "
      <> int.to_string(e.weight)
      <> "\n"
    }),
  )
}

fn max_flow(g: Graph, s: Int, t: Int) -> Result(String, String) {
  case flow.max_flow(g, s, t) {
    Ok(f) ->
      Ok(
        "value "
        <> int.to_string(f.value)
        <> "\n"
        <> "source side "
        <> line(f.source_side)
        <> "cut "
        <> string.join(list.map(f.cut, pair_text), ", ")
        <> "\n",
      )
    Error(flow.SourceIsSink) -> Error("source and sink must differ")
    Error(flow.NegativeCapacity(..)) -> Error("capacities must be non-negative")
    Error(flow.UnknownNode(n)) ->
      Error("node " <> int.to_string(n) <> " is not in the graph")
  }
}

fn groups(gs: List(List(Int))) -> String {
  string.concat(list.map(gs, line))
}

fn line(nodes: List(Int)) -> String {
  string.join(list.map(nodes, int.to_string), " ") <> "\n"
}

fn pair_text(p: #(Int, Int)) -> String {
  int.to_string(p.0) <> "-" <> int.to_string(p.1)
}

fn cycle_text(cycle: List(Int)) -> String {
  let assert [first, ..] = cycle
  string.join(list.map(list.append(cycle, [first]), int.to_string), " -> ")
}
