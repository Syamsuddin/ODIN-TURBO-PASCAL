// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Source files, byte spans and line/column lookup.
//!
//! The compiler works on raw bytes: Turbo Pascal strings are byte strings,
//! so a literal keeps exactly the bytes of the source file (UTF-8 or CP437).
//! Columns are counted in characters when the line is valid UTF-8, matching
//! what the IDE editor shows, and in bytes otherwise.

use std::io;
use std::path::{Path, PathBuf};

/// Index of a file in a [`SourceMap`].
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct FileId(pub u32);

/// A byte range `start..end` in one file.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub struct Span {
    pub file: FileId,
    pub start: u32,
    pub end: u32,
}

impl Span {
    pub fn new(file: FileId, start: u32, end: u32) -> Self {
        Span { file, start, end }
    }

    /// The smallest span covering `self` and `other`. Spans from different
    /// files (an include boundary) keep `self`.
    pub fn to(self, other: Span) -> Span {
        if self.file != other.file {
            return self;
        }
        Span { file: self.file, start: self.start.min(other.start), end: self.end.max(other.end) }
    }

    /// An empty span at the end of `self`.
    pub fn end_point(self) -> Span {
        Span { file: self.file, start: self.end, end: self.end }
    }
}

/// One loaded source file.
pub struct SourceFile {
    pub path: PathBuf,
    pub bytes: Vec<u8>,
    line_starts: Vec<u32>,
}

impl SourceFile {
    fn new(path: PathBuf, mut bytes: Vec<u8>) -> Self {
        // The IDE decodes UTF-8 with BOM as "utf-8-sig", so its columns never
        // include the BOM; drop it here to keep positions identical.
        if bytes.starts_with(&[0xef, 0xbb, 0xbf]) {
            bytes.drain(..3);
        }
        let mut line_starts = vec![0];
        let mut i = 0;
        while i < bytes.len() {
            match bytes[i] {
                b'\n' => line_starts.push(i as u32 + 1),
                b'\r' if bytes.get(i + 1) != Some(&b'\n') => line_starts.push(i as u32 + 1),
                _ => {}
            }
            i += 1;
        }
        SourceFile { path, bytes, line_starts }
    }

    /// 1-based line and column of a byte offset.
    pub fn line_col(&self, offset: u32) -> (u32, u32) {
        let offset = offset.min(self.bytes.len() as u32);
        let line = match self.line_starts.binary_search(&offset) {
            Ok(i) => i,
            Err(i) => i - 1,
        };
        let start = self.line_starts[line] as usize;
        let prefix = &self.bytes[start..offset as usize];
        let column = match std::str::from_utf8(prefix) {
            Ok(text) => text.chars().count(),
            Err(_) => prefix.len(),
        };
        (line as u32 + 1, column as u32 + 1)
    }

    /// Text of a 1-based line without its line terminator.
    pub fn line_text(&self, line: u32) -> &[u8] {
        let index = (line.max(1) - 1) as usize;
        let Some(&start) = self.line_starts.get(index) else { return &[] };
        let end = self.line_starts.get(index + 1).map(|&e| e as usize).unwrap_or(self.bytes.len());
        let mut text = &self.bytes[start as usize..end];
        while let [rest @ .., b'\n' | b'\r'] = text {
            text = rest;
        }
        text
    }

    /// Number of lines, not counting the empty "line" after a final line
    /// terminator (positions there still resolve, as FPC reports them).
    pub fn line_count(&self) -> u32 {
        let ends_with_newline = matches!(self.bytes.last(), Some(b'\n' | b'\r'));
        self.line_starts.len() as u32 - ends_with_newline as u32
    }
}

/// A resolved position, ready for display or JSON.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Location {
    pub path: PathBuf,
    pub line: u32,
    pub column: u32,
    pub end_line: u32,
    pub end_column: u32,
}

/// All files of one compilation.
#[derive(Default)]
pub struct SourceMap {
    files: Vec<SourceFile>,
}

impl SourceMap {
    pub fn new() -> Self {
        Self::default()
    }

    /// Adds a file from memory. The path is only used for display and for
    /// resolving relative includes.
    pub fn add(&mut self, path: impl Into<PathBuf>, bytes: Vec<u8>) -> FileId {
        self.files.push(SourceFile::new(path.into(), bytes));
        FileId(self.files.len() as u32 - 1)
    }

    /// Loads a file from disk; a file already loaded under the same
    /// canonical path is returned again.
    pub fn load(&mut self, path: &Path) -> io::Result<FileId> {
        let canonical = canonical(path)?;
        if let Some(id) = self.find(&canonical) {
            return Ok(id);
        }
        let bytes = std::fs::read(&canonical)?;
        Ok(self.add(canonical, bytes))
    }

    pub fn find(&self, path: &Path) -> Option<FileId> {
        self.files.iter().position(|f| f.path == path).map(|i| FileId(i as u32))
    }

    pub fn file(&self, id: FileId) -> &SourceFile {
        &self.files[id.0 as usize]
    }

    pub fn location(&self, span: Span) -> Location {
        let file = self.file(span.file);
        let (line, column) = file.line_col(span.start);
        let (end_line, end_column) = file.line_col(span.end);
        Location { path: file.path.clone(), line, column, end_line, end_column }
    }

    pub fn len(&self) -> usize {
        self.files.len()
    }

    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lines_and_columns() {
        let mut map = SourceMap::new();
        let id = map.add("a.pas", b"ab\r\ncd\ref\n\xc3\xa9x".to_vec());
        let file = map.file(id);
        assert_eq!(file.line_col(0), (1, 1));
        assert_eq!(file.line_col(1), (1, 2));
        assert_eq!(file.line_col(4), (2, 1));
        assert_eq!(file.line_col(7), (3, 1));
        // 'x' follows a two-byte UTF-8 character: column 2, not 3.
        assert_eq!(file.line_col(12), (4, 2));
        assert_eq!(file.line_text(1), b"ab");
        assert_eq!(file.line_text(2), b"cd");
        assert_eq!(file.line_count(), 4);
        let e = map.add("e.pas", b"a\nb\n".to_vec());
        assert_eq!(map.file(e).line_count(), 2);
    }

    #[test]
    fn bom_is_dropped() {
        let mut map = SourceMap::new();
        let id = map.add("b.pas", b"\xef\xbb\xbfbegin".to_vec());
        assert_eq!(map.file(id).bytes, b"begin");
        assert_eq!(map.location(Span::new(id, 0, 5)).column, 1);
    }

    #[test]
    fn cp437_line_counts_bytes() {
        let mut map = SourceMap::new();
        let id = map.add("c.pas", b"\x82\x82x".to_vec());
        assert_eq!(map.file(id).line_col(2), (1, 3));
    }
}

/// [`Path::canonicalize`], but on Windows without the verbatim `\\?\` prefix
/// it adds (`\\?\C:\x` becomes `C:\x`, `\\?\UNC\host\share` becomes
/// `\\host\share`), so the paths in diagnostics and debug info are the ones
/// the IDE and the user write.
pub fn canonical(path: &Path) -> io::Result<PathBuf> {
    let full = path.canonicalize()?;
    if cfg!(windows) {
        let text = full.to_string_lossy();
        if let Some(rest) = text.strip_prefix(r"\\?\UNC\") {
            return Ok(PathBuf::from(format!(r"\\{rest}")));
        }
        if let Some(rest) = text.strip_prefix(r"\\?\")
            && rest.as_bytes().get(1) == Some(&b':')
        {
            return Ok(PathBuf::from(rest));
        }
    }
    Ok(full)
}
