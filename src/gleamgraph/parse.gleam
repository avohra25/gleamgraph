//// A small plain-text edge-list format.
////
//// ```text
//// # comments start with '#'
//// undirected        # optional header: `directed` (default) or `undirected`
//// 1 2 7             # edge 1 -> 2 with weight 7
//// 2 3               # weight defaults to 1
//// 9                 # a lone number declares an isolated node
//// ```

import gleam/int
import gleam/list
import gleam/set
import gleam/string
import gleamgraph/graph.{type Graph}

pub type ParseError {
  ParseError(line: Int, message: String)
}

pub fn describe(error: ParseError) -> String {
  "line " <> int.to_string(error.line) <> ": " <> error.message
}

pub fn parse(text: String) -> Result(Graph, ParseError) {
  let lines =
    text
    |> string.split("\n")
    |> list.index_map(fn(line, i) { #(i + 1, clean(line)) })
    |> list.filter(fn(p) { p.1 != [] })
  let #(kind, body) = case lines {
    [#(_, ["undirected"]), ..rest] -> #(graph.Undirected, rest)
    [#(_, ["directed"]), ..rest] -> #(graph.Directed, rest)
    _ -> #(graph.Directed, lines)
  }
  list.try_fold(body, graph.new(kind), fn(g, p) {
    let #(number, words) = p
    case list.try_map(words, int.parse) {
      Error(Nil) ->
        Error(ParseError(
          number,
          "expected integers, got `" <> string.join(words, " ") <> "`",
        ))
      Ok([node]) -> Ok(graph.add_node(g, node))
      Ok([from, to]) -> Ok(graph.add_edge(g, from, to, 1))
      Ok([from, to, weight]) -> Ok(graph.add_edge(g, from, to, weight))
      Ok(_) -> Error(ParseError(number, "expected `from to [weight]`"))
    }
  })
}

fn clean(line: String) -> List(String) {
  let content = case string.split_once(line, "#") {
    Ok(#(before, _)) -> before
    Error(Nil) -> line
  }
  content
  |> string.replace("\t", " ")
  |> string.split(" ")
  |> list.filter(fn(w) { w != "" })
}

/// Render a graph in the same format; `parse(format(g))` rebuilds an
/// equivalent graph (same kind, nodes and edges in the same order).
pub fn format(g: Graph) -> String {
  let header = case graph.kind(g) {
    graph.Directed -> "directed"
    graph.Undirected -> "undirected"
  }
  let edges = graph.edges(g)
  let touched = set.from_list(list.flat_map(edges, fn(e) { [e.from, e.to] }))
  let isolated =
    graph.nodes(g)
    |> list.filter(fn(v) { !set.contains(touched, v) })
    |> list.map(int.to_string)
  let edge_lines =
    list.map(edges, fn(e) {
      int.to_string(e.from)
      <> " "
      <> int.to_string(e.to)
      <> " "
      <> int.to_string(e.weight)
    })
  [header, ..list.append(edge_lines, isolated)]
  |> string.join("\n")
  |> string.append("\n")
}
