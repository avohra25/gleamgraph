import gleam/int
import gleam/list
import gleamgraph/heap
import testkit

pub fn empty_heap_test() {
  let h = heap.new()
  assert heap.is_empty(h)
  assert heap.pop(h) == Error(Nil)
  assert heap.peek(h) == Error(Nil)
  assert heap.size(h) == 0
}

pub fn heap_sort_matches_list_sort_test() {
  testkit.repeat(50, testkit.seed(7), fn(rng) {
    let #(n, rng) = testkit.next(rng, 200)
    let #(keys, rng) =
      testkit.repeat(n, #([], rng), fn(state) {
        let #(acc, rng) = state
        let #(k, rng) = testkit.between(rng, -50, 50)
        #([k, ..acc], rng)
      })
    let h = heap.from_list(list.map(keys, fn(k) { #(k, k) }))
    assert heap.size(h) == n
    assert list.map(heap.to_sorted_list(h), fn(p) { p.0 })
      == list.sort(keys, int.compare)
    rng
  })
}

pub fn merge_test() {
  let a = heap.from_list([#(5, "e"), #(1, "a")])
  let b = heap.from_list([#(3, "c"), #(4, "d"), #(2, "b")])
  let merged = heap.merge(a, b)
  assert heap.peek(merged) == Ok(#(1, "a"))
  assert list.map(heap.to_sorted_list(merged), fn(p) { p.1 })
    == ["a", "b", "c", "d", "e"]
}

pub fn interleaved_operations_test() {
  // Mix inserts and pops and compare against a sorted-list model.
  let #(_, h, model) =
    testkit.repeat(2000, #(testkit.seed(99), heap.new(), []), fn(state) {
      let #(rng, h, model) = state
      let #(op, rng) = testkit.next(rng, 3)
      case op, heap.pop(h) {
        0, Ok(#(k, _, rest)) -> {
          let assert [smallest, ..others] = model
          assert k == smallest
          #(rng, rest, others)
        }
        _, _ -> {
          let #(k, rng) = testkit.next(rng, 1000)
          #(rng, heap.insert(h, k, Nil), list.sort([k, ..model], int.compare))
        }
      }
    })
  assert heap.size(h) == list.length(model)
}
