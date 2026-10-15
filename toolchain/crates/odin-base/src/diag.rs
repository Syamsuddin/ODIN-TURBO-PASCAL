// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Diagnostics with Turbo Pascal 7 error numbers and Indonesian messages.
//!
//! Numbers below 900 follow the TP7 compiler error list, so programmers who
//! know TP recognize them. 900-999 are Odin-specific errors, 1000 and up are
//! warnings and hints. The message texts are written for Odin.

use crate::json::JsonWriter;
use crate::source::{SourceMap, Span};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Severity {
    Hint,
    Note,
    Warning,
    Error,
    Fatal,
}

impl Severity {
    /// Lowercase name used in JSON output.
    pub fn as_str(self) -> &'static str {
        match self {
            Severity::Hint => "hint",
            Severity::Note => "note",
            Severity::Warning => "warning",
            Severity::Error => "error",
            Severity::Fatal => "fatal",
        }
    }

    /// Capitalized name used in text output (same words as FPC, which the
    /// IDE's fallback parser also understands).
    pub fn title(self) -> &'static str {
        match self {
            Severity::Hint => "Hint",
            Severity::Note => "Note",
            Severity::Warning => "Warning",
            Severity::Error => "Error",
            Severity::Fatal => "Fatal",
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Diagnostic {
    pub severity: Severity,
    pub code: u16,
    pub span: Span,
    pub message: String,
}

impl Diagnostic {
    pub fn new(severity: Severity, code: u16, span: Span, message: impl Into<String>) -> Self {
        Diagnostic { severity, code, span, message: message.into() }
    }

    /// An error whose text is the standard message for `code`.
    pub fn error(code: u16, span: Span) -> Self {
        Self::new(Severity::Error, code, span, code::message(code))
    }

    /// An error with the standard message for `code` followed by `detail`.
    pub fn error_with(code: u16, span: Span, detail: impl AsRef<str>) -> Self {
        Self::new(Severity::Error, code, span, format!("{}{}", code::message(code), detail.as_ref()))
    }

    pub fn warning(code: u16, span: Span, message: impl Into<String>) -> Self {
        Self::new(Severity::Warning, code, span, message)
    }

    pub fn hint(code: u16, span: Span, message: impl Into<String>) -> Self {
        Self::new(Severity::Hint, code, span, message)
    }

    /// `FILE(line,col) Error 85: message`, the shape FPC also prints.
    pub fn render(&self, map: &SourceMap) -> String {
        let loc = map.location(self.span);
        format!(
            "{}({},{}) {} {}: {}",
            loc.path.display(),
            loc.line,
            loc.column,
            self.severity.title(),
            self.code,
            self.message
        )
    }

    /// One JSON object, as written by `odinpc --diag-format json`.
    pub fn to_json(&self, map: &SourceMap) -> String {
        let loc = map.location(self.span);
        let mut w = JsonWriter::object();
        w.field_str("type", "diagnostic");
        w.field_str("severity", self.severity.as_str());
        w.field_num("code", self.code as i64);
        w.field_str("file", &loc.path.to_string_lossy());
        w.field_num("line", loc.line as i64);
        w.field_num("column", loc.column as i64);
        w.field_num("end_line", loc.end_line as i64);
        w.field_num("end_column", loc.end_column as i64);
        w.field_str("message", &self.message);
        w.finish()
    }
}

/// Error numbers and their standard Indonesian texts.
pub mod code {
    pub const IDENT_EXPECTED: u16 = 2;
    pub const UNKNOWN_IDENT: u16 = 3;
    pub const DUPLICATE_IDENT: u16 = 4;
    pub const SYNTAX_ERROR: u16 = 5;
    pub const BAD_REAL: u16 = 6;
    pub const BAD_INTEGER: u16 = 7;
    pub const STRING_EXCEEDS_LINE: u16 = 8;
    pub const UNEXPECTED_EOF: u16 = 10;
    pub const TYPE_IDENT_EXPECTED: u16 = 12;
    pub const FILE_NOT_FOUND: u16 = 15;
    pub const BAD_DIRECTIVE: u16 = 17;
    pub const UNDEFINED_POINTER_TYPE: u16 = 19;
    pub const VAR_IDENT_EXPECTED: u16 = 20;
    pub const ERROR_IN_TYPE: u16 = 21;
    pub const STRUCTURE_TOO_LARGE: u16 = 22;
    pub const SET_BASE_RANGE: u16 = 23;
    pub const BAD_STRING_LENGTH: u16 = 25;
    pub const TYPE_MISMATCH: u16 = 26;
    pub const BAD_SUBRANGE_BASE: u16 = 27;
    pub const LOWER_GREATER_UPPER: u16 = 28;
    pub const ORDINAL_TYPE_EXPECTED: u16 = 29;
    pub const INTEGER_CONST_EXPECTED: u16 = 30;
    pub const CONST_EXPECTED: u16 = 31;
    pub const INT_OR_REAL_CONST_EXPECTED: u16 = 32;
    pub const POINTER_TYPE_IDENT_EXPECTED: u16 = 33;
    pub const BAD_RESULT_TYPE: u16 = 34;
    pub const LABEL_IDENT_EXPECTED: u16 = 35;
    pub const BEGIN_EXPECTED: u16 = 36;
    pub const END_EXPECTED: u16 = 37;
    pub const INTEGER_EXPR_EXPECTED: u16 = 38;
    pub const ORDINAL_EXPR_EXPECTED: u16 = 39;
    pub const BOOLEAN_EXPR_EXPECTED: u16 = 40;
    pub const OPERAND_TYPES: u16 = 41;
    pub const ERROR_IN_EXPR: u16 = 42;
    pub const ILLEGAL_ASSIGNMENT: u16 = 43;
    pub const FIELD_IDENT_EXPECTED: u16 = 44;
    pub const UNDEFINED_EXTERNAL: u16 = 46;
    pub const DO_EXPECTED: u16 = 50;
    pub const OF_EXPECTED: u16 = 54;
    pub const INTERFACE_EXPECTED: u16 = 55;
    pub const THEN_EXPECTED: u16 = 57;
    pub const TO_DOWNTO_EXPECTED: u16 = 58;
    pub const UNDEFINED_FORWARD: u16 = 59;
    pub const BAD_TYPECAST: u16 = 61;
    pub const DIVISION_BY_ZERO: u16 = 62;
    pub const BAD_FILE_TYPE: u16 = 63;
    pub const CANNOT_READ_WRITE: u16 = 64;
    pub const POINTER_VAR_EXPECTED: u16 = 65;
    pub const STRING_VAR_EXPECTED: u16 = 66;
    pub const STRING_EXPR_EXPECTED: u16 = 67;
    pub const CIRCULAR_UNIT: u16 = 68;
    pub const UNIT_NAME_MISMATCH: u16 = 69;
    pub const IMPLEMENTATION_EXPECTED: u16 = 73;
    pub const CASE_CONST_TYPE: u16 = 74;
    pub const RECORD_VAR_EXPECTED: u16 = 75;
    pub const CONST_OUT_OF_RANGE: u16 = 76;
    pub const FILE_VAR_EXPECTED: u16 = 77;
    pub const POINTER_EXPR_EXPECTED: u16 = 78;
    pub const INT_OR_REAL_EXPR_EXPECTED: u16 = 79;
    pub const LABEL_NOT_IN_BLOCK: u16 = 80;
    pub const LABEL_ALREADY_DEFINED: u16 = 81;
    pub const UNDEFINED_LABEL: u16 = 82;
    pub const BAD_AT_ARGUMENT: u16 = 83;
    pub const UNIT_EXPECTED: u16 = 84;
    pub const SEMICOLON_EXPECTED: u16 = 85;
    pub const COLON_EXPECTED: u16 = 86;
    pub const COMMA_EXPECTED: u16 = 87;
    pub const LPAREN_EXPECTED: u16 = 88;
    pub const RPAREN_EXPECTED: u16 = 89;
    pub const EQUAL_EXPECTED: u16 = 90;
    pub const ASSIGN_EXPECTED: u16 = 91;
    pub const LBRACKET_EXPECTED: u16 = 92;
    pub const RBRACKET_EXPECTED: u16 = 93;
    pub const PERIOD_EXPECTED: u16 = 94;
    pub const DOTDOT_EXPECTED: u16 = 95;
    pub const BAD_FOR_VAR: u16 = 97;
    pub const INTEGER_VAR_EXPECTED: u16 = 98;
    pub const FILE_PROC_NOT_ALLOWED: u16 = 99;
    pub const STRING_LENGTH_MISMATCH: u16 = 100;
    pub const STRING_CONST_EXPECTED: u16 = 102;
    pub const INT_OR_REAL_VAR_EXPECTED: u16 = 103;
    pub const ORDINAL_VAR_EXPECTED: u16 = 104;
    pub const CHAR_EXPR_EXPECTED: u16 = 106;
    pub const ARITH_OVERFLOW: u16 = 108;
    pub const NO_ENCLOSING_LOOP: u16 = 109;
    pub const CASE_CONST_RANGE: u16 = 112;
    pub const ERROR_IN_STATEMENT: u16 = 113;
    pub const INCLUDE_NOT_ALLOWED: u16 = 118;
    pub const NO_INHERITED: u16 = 119;
    pub const BAD_QUALIFIER: u16 = 121;
    pub const BAD_VAR_REFERENCE: u16 = 122;
    pub const FILE_MUST_BE_VAR: u16 = 126;
    pub const MISPLACED_CONDITIONAL: u16 = 128;
    pub const ENDIF_MISSING: u16 = 129;
    pub const HEADER_MISMATCH: u16 = 131;
    pub const CANNOT_EVALUATE: u16 = 133;
    pub const EXPR_BAD_END: u16 = 134;
    pub const BAD_FORMAT_SPECIFIER: u16 = 135;
    pub const BAD_INDIRECT: u16 = 136;
    pub const STRUCTURED_NOT_ALLOWED: u16 = 137;
    pub const CANNOT_ACCESS: u16 = 139;
    pub const BAD_FLOAT_OP: u16 = 140;
    pub const POINTER_OR_PROC_VAR_EXPECTED: u16 = 142;
    pub const BAD_PROC_REFERENCE: u16 = 143;
    pub const OBJECT_TYPE_EXPECTED: u16 = 147;
    pub const LOCAL_OBJECT_TYPE: u16 = 148;
    pub const VIRTUAL_EXPECTED: u16 = 149;
    pub const METHOD_IDENT_EXPECTED: u16 = 150;
    pub const VIRTUAL_CONSTRUCTOR: u16 = 151;
    pub const CONSTRUCTOR_EXPECTED: u16 = 152;
    pub const DESTRUCTOR_EXPECTED: u16 = 153;
    pub const FAIL_OUTSIDE_CONSTRUCTOR: u16 = 154;
    pub const CODEGEN_ERROR: u16 = 161;
    pub const PROC_IDENT_EXPECTED: u16 = 166;

    // Odin-specific errors.
    pub const NOT_SUPPORTED: u16 = 900;
    pub const DOS_ONLY: u16 = 901;
    pub const WRONG_ARG_COUNT: u16 = 902;
    pub const NO_VALUE: u16 = 903;
    pub const INTERNAL: u16 = 999;

    // Warnings and hints.
    pub const UNKNOWN_DIRECTIVE: u16 = 1000;
    pub const UNUSED_VARIABLE: u16 = 1001;
    pub const UNINITIALIZED: u16 = 1002;
    pub const IGNORED_DIRECTIVE: u16 = 1003;

    /// Standard text for an error number.
    pub fn message(code: u16) -> &'static str {
        match code {
            IDENT_EXPECTED => "Identifier diharapkan",
            UNKNOWN_IDENT => "Identifier tidak dikenal",
            DUPLICATE_IDENT => "Identifier ganda",
            SYNTAX_ERROR => "Kesalahan sintaks",
            BAD_REAL => "Konstanta real tidak valid",
            BAD_INTEGER => "Konstanta integer tidak valid",
            STRING_EXCEEDS_LINE => "Konstanta string melewati akhir baris",
            UNEXPECTED_EOF => "Akhir berkas tidak terduga",
            TYPE_IDENT_EXPECTED => "Identifier tipe diharapkan",
            FILE_NOT_FOUND => "Berkas tidak ditemukan",
            BAD_DIRECTIVE => "Direktif compiler tidak valid",
            UNDEFINED_POINTER_TYPE => "Tipe dalam definisi pointer tidak terdefinisi",
            VAR_IDENT_EXPECTED => "Identifier variabel diharapkan",
            ERROR_IN_TYPE => "Kesalahan dalam tipe",
            STRUCTURE_TOO_LARGE => "Struktur terlalu besar",
            SET_BASE_RANGE => "Tipe dasar set di luar jangkauan",
            BAD_STRING_LENGTH => "Panjang string tidak valid",
            TYPE_MISMATCH => "Tipe tidak cocok",
            BAD_SUBRANGE_BASE => "Tipe dasar subrange tidak valid",
            LOWER_GREATER_UPPER => "Batas bawah lebih besar dari batas atas",
            ORDINAL_TYPE_EXPECTED => "Tipe ordinal diharapkan",
            INTEGER_CONST_EXPECTED => "Konstanta integer diharapkan",
            CONST_EXPECTED => "Konstanta diharapkan",
            INT_OR_REAL_CONST_EXPECTED => "Konstanta integer atau real diharapkan",
            POINTER_TYPE_IDENT_EXPECTED => "Identifier tipe pointer diharapkan",
            BAD_RESULT_TYPE => "Tipe hasil fungsi tidak valid",
            LABEL_IDENT_EXPECTED => "Identifier label diharapkan",
            BEGIN_EXPECTED => "BEGIN diharapkan",
            END_EXPECTED => "END diharapkan",
            INTEGER_EXPR_EXPECTED => "Ekspresi integer diharapkan",
            ORDINAL_EXPR_EXPECTED => "Ekspresi ordinal diharapkan",
            BOOLEAN_EXPR_EXPECTED => "Ekspresi boolean diharapkan",
            OPERAND_TYPES => "Tipe operand tidak cocok dengan operator",
            ERROR_IN_EXPR => "Kesalahan dalam ekspresi",
            ILLEGAL_ASSIGNMENT => "Penugasan tidak sah",
            FIELD_IDENT_EXPECTED => "Identifier field diharapkan",
            UNDEFINED_EXTERNAL => "External tidak terdefinisi",
            DO_EXPECTED => "DO diharapkan",
            OF_EXPECTED => "OF diharapkan",
            INTERFACE_EXPECTED => "INTERFACE diharapkan",
            THEN_EXPECTED => "THEN diharapkan",
            TO_DOWNTO_EXPECTED => "TO atau DOWNTO diharapkan",
            UNDEFINED_FORWARD => "Deklarasi forward tidak pernah didefinisikan",
            BAD_TYPECAST => "Typecast tidak valid",
            DIVISION_BY_ZERO => "Pembagian dengan nol",
            BAD_FILE_TYPE => "Tipe berkas tidak valid",
            CANNOT_READ_WRITE => "Variabel bertipe ini tidak bisa dibaca atau ditulis",
            POINTER_VAR_EXPECTED => "Variabel pointer diharapkan",
            STRING_VAR_EXPECTED => "Variabel string diharapkan",
            STRING_EXPR_EXPECTED => "Ekspresi string diharapkan",
            CIRCULAR_UNIT => "Referensi unit melingkar",
            UNIT_NAME_MISMATCH => "Nama unit tidak cocok dengan nama berkas",
            IMPLEMENTATION_EXPECTED => "IMPLEMENTATION diharapkan",
            CASE_CONST_TYPE => "Tipe konstanta tidak cocok dengan ekspresi CASE",
            RECORD_VAR_EXPECTED => "Variabel record atau object diharapkan",
            CONST_OUT_OF_RANGE => "Konstanta di luar jangkauan",
            FILE_VAR_EXPECTED => "Variabel berkas diharapkan",
            POINTER_EXPR_EXPECTED => "Ekspresi pointer diharapkan",
            INT_OR_REAL_EXPR_EXPECTED => "Ekspresi integer atau real diharapkan",
            LABEL_NOT_IN_BLOCK => "Label tidak berada di blok ini",
            LABEL_ALREADY_DEFINED => "Label sudah didefinisikan",
            UNDEFINED_LABEL => "Label dideklarasikan tetapi tidak ditempatkan",
            BAD_AT_ARGUMENT => "Argumen @ tidak valid",
            UNIT_EXPECTED => "UNIT diharapkan",
            SEMICOLON_EXPECTED => "\";\" diharapkan",
            COLON_EXPECTED => "\":\" diharapkan",
            COMMA_EXPECTED => "\",\" diharapkan",
            LPAREN_EXPECTED => "\"(\" diharapkan",
            RPAREN_EXPECTED => "\")\" diharapkan",
            EQUAL_EXPECTED => "\"=\" diharapkan",
            ASSIGN_EXPECTED => "\":=\" diharapkan",
            LBRACKET_EXPECTED => "\"[\" diharapkan",
            RBRACKET_EXPECTED => "\"]\" diharapkan",
            PERIOD_EXPECTED => "\".\" diharapkan",
            DOTDOT_EXPECTED => "\"..\" diharapkan",
            BAD_FOR_VAR => "Variabel kontrol FOR tidak valid",
            INTEGER_VAR_EXPECTED => "Variabel integer diharapkan",
            FILE_PROC_NOT_ALLOWED => "Tipe berkas dan prosedural tidak diizinkan di sini",
            STRING_LENGTH_MISMATCH => "Panjang string tidak cocok",
            STRING_CONST_EXPECTED => "Konstanta string diharapkan",
            INT_OR_REAL_VAR_EXPECTED => "Variabel integer atau real diharapkan",
            ORDINAL_VAR_EXPECTED => "Variabel ordinal diharapkan",
            CHAR_EXPR_EXPECTED => "Ekspresi karakter diharapkan",
            ARITH_OVERFLOW => "Overflow dalam operasi aritmetika",
            NO_ENCLOSING_LOOP => "Tidak berada di dalam FOR, WHILE, atau REPEAT",
            CASE_CONST_RANGE => "Konstanta CASE di luar jangkauan",
            ERROR_IN_STATEMENT => "Kesalahan dalam statement",
            INCLUDE_NOT_ALLOWED => "Berkas include tidak diizinkan di sini",
            NO_INHERITED => "Tidak ada method warisan yang bisa diakses di sini",
            BAD_QUALIFIER => "Qualifier tidak valid",
            BAD_VAR_REFERENCE => "Referensi variabel tidak valid",
            FILE_MUST_BE_VAR => "Parameter berkas harus berupa parameter var",
            MISPLACED_CONDITIONAL => "Direktif kondisional salah tempat",
            ENDIF_MISSING => "Direktif {$ENDIF} tidak ditemukan",
            HEADER_MISMATCH => "Header tidak cocok dengan deklarasi sebelumnya",
            CANNOT_EVALUATE => "Ekspresi ini tidak bisa dievaluasi saat kompilasi",
            EXPR_BAD_END => "Ekspresi diakhiri dengan tidak benar",
            BAD_FORMAT_SPECIFIER => "Format penulisan tidak valid",
            BAD_INDIRECT => "Referensi tak langsung tidak valid",
            STRUCTURED_NOT_ALLOWED => "Variabel terstruktur tidak diizinkan di sini",
            CANNOT_ACCESS => "Simbol ini tidak bisa diakses",
            BAD_FLOAT_OP => "Operasi floating point tidak valid",
            POINTER_OR_PROC_VAR_EXPECTED => "Variabel pointer atau prosedural diharapkan",
            BAD_PROC_REFERENCE => "Referensi prosedur atau fungsi tidak valid",
            OBJECT_TYPE_EXPECTED => "Tipe object diharapkan",
            LOCAL_OBJECT_TYPE => "Tipe object lokal tidak diizinkan",
            VIRTUAL_EXPECTED => "VIRTUAL diharapkan",
            METHOD_IDENT_EXPECTED => "Identifier method diharapkan",
            VIRTUAL_CONSTRUCTOR => "Constructor tidak boleh virtual",
            CONSTRUCTOR_EXPECTED => "Identifier constructor diharapkan",
            DESTRUCTOR_EXPECTED => "Identifier destructor diharapkan",
            FAIL_OUTSIDE_CONSTRUCTOR => "Fail hanya boleh dipakai di dalam constructor",
            CODEGEN_ERROR => "Kesalahan pembangkitan kode",
            PROC_IDENT_EXPECTED => "Identifier prosedur atau fungsi diharapkan",
            NOT_SUPPORTED => "Belum didukung oleh compiler Odin",
            DOS_ONLY => "Fitur DOS ini tidak tersedia di sistem 64-bit",
            WRONG_ARG_COUNT => "Jumlah parameter tidak cocok",
            NO_VALUE => "Prosedur tidak menghasilkan nilai",
            INTERNAL => "Kesalahan internal compiler",
            UNKNOWN_DIRECTIVE => "Direktif tidak dikenal, diabaikan",
            UNUSED_VARIABLE => "Variabel tidak pernah dipakai",
            UNINITIALIZED => "Variabel mungkin belum diberi nilai",
            IGNORED_DIRECTIVE => "Direktif tidak berpengaruh di Odin, diabaikan",
            _ => "Kesalahan",
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::source::SourceMap;

    #[test]
    fn render_and_json() {
        let mut map = SourceMap::new();
        let id = map.add("/tmp/X.PAS", b"program x\nbegin\nend.".to_vec());
        let d = Diagnostic::error_with(code::SEMICOLON_EXPECTED, Span::new(id, 10, 15), ", tetapi ditemukan BEGIN");
        assert_eq!(d.render(&map), "/tmp/X.PAS(2,1) Error 85: \";\" diharapkan, tetapi ditemukan BEGIN");
        assert_eq!(
            d.to_json(&map),
            r#"{"type":"diagnostic","severity":"error","code":85,"file":"/tmp/X.PAS","line":2,"column":1,"end_line":2,"end_column":6,"message":"\";\" diharapkan, tetapi ditemukan BEGIN"}"#
        );
    }
}
