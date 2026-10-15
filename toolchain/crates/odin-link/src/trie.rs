// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! The dyld export trie: a prefix tree over exported symbol names whose
//! terminal nodes hold each symbol's offset from the Mach-O header.

use std::collections::BTreeMap;

use crate::leb::{uleb128, uleb128_len};

/// Encodes `exports` (name, offset from the image base) as an export trie
/// of regular, non-weak symbols, padded to 8 bytes.
pub(crate) fn export_trie(exports: &[(&str, u64)]) -> Vec<u8> {
    let sorted: BTreeMap<&[u8], u64> = exports.iter().map(|&(name, offset)| (name.as_bytes(), offset)).collect();
    let entries: Vec<(&[u8], u64)> = sorted.into_iter().collect();
    let mut nodes = Vec::new();
    build(&mut nodes, &entries, 0);

    // A node's size depends on the ULEB128 width of its children's offsets,
    // so iterate until the offsets stop changing. Sizes only grow, so this
    // converges in a few rounds.
    let mut offsets = vec![0u64; nodes.len()];
    loop {
        let mut next = Vec::with_capacity(nodes.len());
        let mut at = 0u64;
        for node in &nodes {
            next.push(at);
            at += node_size(node, &offsets) as u64;
        }
        if next == offsets {
            break;
        }
        offsets = next;
    }

    let mut out = Vec::new();
    for node in &nodes {
        match node.terminal {
            Some(offset) => {
                uleb128(&mut out, (1 + uleb128_len(offset)) as u64);
                uleb128(&mut out, 0); // EXPORT_SYMBOL_FLAGS_KIND_REGULAR
                uleb128(&mut out, offset);
            }
            None => out.push(0),
        }
        out.push(node.edges.len() as u8);
        for (label, child) in &node.edges {
            out.extend_from_slice(label);
            out.push(0);
            uleb128(&mut out, offsets[*child]);
        }
    }
    out.resize(out.len().next_multiple_of(8), 0);
    out
}

struct Node<'a> {
    terminal: Option<u64>,
    edges: Vec<(&'a [u8], usize)>,
}

/// Adds the node for the common prefix `entries[..][..depth]` and its
/// subtree; returns its index. `entries` is sorted and shares that prefix.
fn build<'a>(nodes: &mut Vec<Node<'a>>, entries: &[(&'a [u8], u64)], depth: usize) -> usize {
    let id = nodes.len();
    nodes.push(Node { terminal: None, edges: Vec::new() });
    let mut rest = entries;
    if let Some((&(name, offset), tail)) = rest.split_first()
        && name.len() == depth
    {
        nodes[id].terminal = Some(offset);
        rest = tail;
    }
    while let Some(&(first, _)) = rest.first() {
        let byte = first[depth];
        let count = rest.iter().take_while(|(name, _)| name[depth] == byte).count();
        let (group, tail) = rest.split_at(count);
        // In a sorted group the common prefix of all names is the common
        // prefix of the first and the last.
        let last = group[count - 1].0;
        let mut end = depth + 1;
        while end < first.len() && end < last.len() && first[end] == last[end] {
            end += 1;
        }
        let child = build(nodes, group, end);
        nodes[id].edges.push((&first[depth..end], child));
        rest = tail;
    }
    id
}

fn node_size(node: &Node, offsets: &[u64]) -> usize {
    let terminal = match node.terminal {
        Some(offset) => {
            let info = 1 + uleb128_len(offset);
            uleb128_len(info as u64) + info
        }
        None => 1,
    };
    let edges: usize = node.edges.iter().map(|(label, child)| label.len() + 1 + uleb128_len(offsets[*child])).sum();
    terminal + 1 + edges
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Walks the trie the way dyld does and returns every exported symbol.
    fn decode(trie: &[u8]) -> Vec<(String, u64)> {
        fn uleb(data: &[u8], at: &mut usize) -> u64 {
            let mut value = 0;
            let mut shift = 0;
            loop {
                let byte = data[*at];
                *at += 1;
                value |= u64::from(byte & 0x7f) << shift;
                shift += 7;
                if byte & 0x80 == 0 {
                    return value;
                }
            }
        }
        fn walk(trie: &[u8], node: usize, prefix: &mut Vec<u8>, out: &mut Vec<(String, u64)>) {
            let mut at = node;
            let info = uleb(trie, &mut at) as usize;
            let children = at + info;
            if info > 0 {
                assert_eq!(uleb(trie, &mut at), 0, "flags");
                out.push((String::from_utf8(prefix.clone()).unwrap(), uleb(trie, &mut at)));
                assert_eq!(at, children, "terminal size");
            }
            at = children;
            let count = trie[at];
            at += 1;
            for _ in 0..count {
                let len = prefix.len();
                while trie[at] != 0 {
                    prefix.push(trie[at]);
                    at += 1;
                }
                at += 1;
                let child = uleb(trie, &mut at) as usize;
                walk(trie, child, prefix, out);
                prefix.truncate(len);
            }
        }
        let mut out = Vec::new();
        walk(trie, 0, &mut Vec::new(), &mut out);
        out
    }

    fn roundtrip(exports: &[(&str, u64)]) {
        let trie = export_trie(exports);
        assert_eq!(trie.len() % 8, 0);
        let mut expected: Vec<(String, u64)> = exports.iter().map(|&(n, o)| (n.to_string(), o)).collect();
        expected.sort();
        assert_eq!(decode(&trie), expected);
    }

    #[test]
    fn executable_exports() {
        let trie = export_trie(&[("__mh_execute_header", 0), ("_main", 0x3a8)]);
        // Root: no terminal, one edge "_" to the node that splits the two names.
        assert_eq!(&trie[..5], &[0, 1, b'_', 0, 5]);
        roundtrip(&[("__mh_execute_header", 0), ("_main", 0x3a8)]);
    }

    #[test]
    fn prefixes_and_large_offsets() {
        roundtrip(&[("_a", 1)]);
        roundtrip(&[("_ab", 1), ("_abc", 2), ("_abd", 3), ("_b", 1 << 40)]);
        let names: Vec<String> = (0..300).map(|i| format!("_SYSTEM_{i:03}_{}", "x".repeat(i % 7))).collect();
        let exports: Vec<(&str, u64)> = names.iter().enumerate().map(|(i, n)| (n.as_str(), i as u64 * 977)).collect();
        roundtrip(&exports);
    }

    #[test]
    fn empty() {
        assert_eq!(export_trie(&[]), [0, 0, 0, 0, 0, 0, 0, 0]);
    }
}
