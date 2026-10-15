// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Recursive-descent parser for Turbo Pascal 7. Stops at the first error,
//! reported at the start of the offending token (as TP and FPC do).

use odin_base::{Diagnostic, Span, code};

use crate::ast::*;
use crate::token::{Kw, Switches, Tok, Token};

type PResult<T> = Result<T, Diagnostic>;

/// Parses a whole program or unit from the tokens of [`crate::tokenize`].
pub fn parse_module(tokens: &[Token]) -> PResult<Module> {
    let mut p = Parser::new(tokens);
    p.module()
}

/// Parses a standalone expression (used by the debugger's evaluator).
pub fn parse_expression(tokens: &[Token]) -> PResult<Expr> {
    let mut p = Parser::new(tokens);
    let e = p.expr()?;
    if !p.is(&Tok::Eof) {
        return Err(p.unexpected(code::EXPR_BAD_END));
    }
    Ok(e)
}

const PREC_REL: u8 = 1;
const PREC_ADD: u8 = 2;
const PREC_MUL: u8 = 3;

/// Context words that end a routine heading.
const DIRECTIVES: &[&str] = &[
    "FORWARD",
    "EXTERNAL",
    "ASSEMBLER",
    "FAR",
    "NEAR",
    "INTERRUPT",
    "CDECL",
    "EXPORT",
    "VIRTUAL",
    "STDCALL",
    "REGISTER",
    "PASCAL",
];

#[derive(Clone, Copy, PartialEq, Eq)]
enum DeclCtx {
    /// Unit interface: routine headings without bodies, no labels.
    Interface,
    /// Program, routine or unit implementation: full declarations.
    Block,
}

struct Parser<'t> {
    toks: &'t [Token],
    pos: usize,
}

impl<'t> Parser<'t> {
    fn new(toks: &'t [Token]) -> Self {
        assert!(matches!(toks.last().map(|t| &t.tok), Some(Tok::Eof)), "token stream must end with Eof");
        Parser { toks, pos: 0 }
    }

    // ---- token helpers ---------------------------------------------------

    fn token(&self) -> &'t Token {
        &self.toks[self.pos.min(self.toks.len() - 1)]
    }

    fn peek(&self) -> &'t Tok {
        &self.token().tok
    }

    fn peek_at(&self, k: usize) -> &'t Tok {
        &self.toks[(self.pos + k).min(self.toks.len() - 1)].tok
    }

    fn span(&self) -> Span {
        self.token().span
    }

    fn switches(&self) -> Switches {
        self.token().switches
    }

    fn prev_span(&self) -> Span {
        if self.pos == 0 { self.toks[0].span } else { self.toks[self.pos - 1].span }
    }

    fn bump(&mut self) -> &'t Token {
        let t = self.token();
        if self.pos < self.toks.len() - 1 {
            self.pos += 1;
        }
        t
    }

    fn is(&self, t: &Tok) -> bool {
        self.peek() == t
    }

    fn is_kw(&self, kw: Kw) -> bool {
        matches!(self.peek(), Tok::Keyword(k) if *k == kw)
    }

    fn eat(&mut self, t: &Tok) -> bool {
        if self.is(t) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn eat_kw(&mut self, kw: Kw) -> bool {
        if self.is_kw(kw) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn unexpected(&self, code: u16) -> Diagnostic {
        if self.is(&Tok::Eof) {
            // Like TP: running out of source is always "unexpected end of file".
            return Diagnostic::error(code::UNEXPECTED_EOF, self.span());
        }
        Diagnostic::error_with(code, self.span(), format!(", tetapi ditemukan {}", self.peek().describe()))
    }

    fn expect(&mut self, t: &Tok, code: u16) -> PResult<Span> {
        if self.is(t) { Ok(self.bump().span) } else { Err(self.unexpected(code)) }
    }

    fn expect_kw(&mut self, kw: Kw, code: u16) -> PResult<Span> {
        if self.is_kw(kw) { Ok(self.bump().span) } else { Err(self.unexpected(code)) }
    }

    fn is_word(&self, word: &str) -> bool {
        matches!(self.peek(), Tok::Ident(n) if n.eq_ignore_ascii_case(word))
    }

    fn ident(&mut self) -> PResult<Ident> {
        match self.peek() {
            Tok::Ident(name) => {
                let span = self.bump().span;
                Ok(Ident { name: name.clone(), span })
            }
            _ => Err(self.unexpected(code::IDENT_EXPECTED)),
        }
    }

    fn ident_list(&mut self) -> PResult<Vec<Ident>> {
        let mut names = vec![self.ident()?];
        while self.eat(&Tok::Comma) {
            names.push(self.ident()?);
        }
        Ok(names)
    }

    fn qual_ident(&mut self) -> PResult<QualIdent> {
        let first = self.ident()?;
        if self.is(&Tok::Dot) && matches!(self.peek_at(1), Tok::Ident(_)) {
            self.bump();
            let name = self.ident()?;
            return Ok(QualIdent { unit: Some(first), name });
        }
        Ok(QualIdent { unit: None, name: first })
    }

    // ---- modules ---------------------------------------------------------

    fn module(&mut self) -> PResult<Module> {
        if self.is_kw(Kw::Unit) {
            return self.unit().map(Module::Unit);
        }
        if self.is_kw(Kw::Library) {
            return Err(Diagnostic::error_with(code::NOT_SUPPORTED, self.span(), ": library (DLL)"));
        }
        self.program().map(Module::Program)
    }

    fn program(&mut self) -> PResult<Program> {
        let start = self.span();
        let mut name = None;
        let mut params = Vec::new();
        if self.eat_kw(Kw::Program) {
            name = Some(self.ident()?);
            if self.eat(&Tok::LParen) {
                params = self.ident_list()?;
                self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
            }
            self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
        }
        let uses = self.uses()?;
        let block = self.block(true)?;
        self.expect(&Tok::Dot, code::PERIOD_EXPECTED)?;
        Ok(Program { name, params, uses, block, span: start.to(self.prev_span()) })
    }

    fn uses(&mut self) -> PResult<Vec<Ident>> {
        if !self.eat_kw(Kw::Uses) {
            return Ok(Vec::new());
        }
        let names = self.ident_list()?;
        self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
        Ok(names)
    }

    fn unit(&mut self) -> PResult<Unit> {
        let start = self.expect_kw(Kw::Unit, code::UNIT_EXPECTED)?;
        let name = self.ident()?;
        self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
        self.expect_kw(Kw::Interface, code::INTERFACE_EXPECTED)?;
        let interface_uses = self.uses()?;
        let interface = self.decls(DeclCtx::Interface)?;
        self.expect_kw(Kw::Implementation, code::IMPLEMENTATION_EXPECTED)?;
        let implementation_uses = self.uses()?;
        let implementation = self.decls(DeclCtx::Block)?;
        let init = if self.is_kw(Kw::Begin) {
            Some(self.compound()?.0)
        } else {
            self.expect_kw(Kw::End, code::END_EXPECTED)?;
            None
        };
        self.expect(&Tok::Dot, code::PERIOD_EXPECTED)?;
        Ok(Unit {
            name,
            interface_uses,
            interface,
            implementation_uses,
            implementation,
            init,
            span: start.to(self.prev_span()),
        })
    }

    // ---- declarations ----------------------------------------------------

    fn block(&mut self, top_level: bool) -> PResult<Block> {
        let decls = self.decls(DeclCtx::Block)?;
        let body = if self.is_kw(Kw::Begin) {
            let (stmts, span) = self.compound()?;
            Body::Statements(stmts, span)
        } else if self.is_kw(Kw::Asm) && !top_level {
            Body::Asm(self.asm_block()?)
        } else {
            return Err(self.unexpected(code::BEGIN_EXPECTED));
        };
        Ok(Block { decls, body })
    }

    fn decls(&mut self, ctx: DeclCtx) -> PResult<Vec<Decl>> {
        let mut decls = Vec::new();
        loop {
            match self.peek() {
                Tok::Keyword(Kw::Label) if ctx == DeclCtx::Block => decls.push(self.labels()?),
                Tok::Keyword(Kw::Const) => decls.push(self.consts()?),
                Tok::Keyword(Kw::Type) => decls.push(self.types()?),
                Tok::Keyword(Kw::Var) => decls.push(self.vars()?),
                Tok::Keyword(Kw::Procedure | Kw::Function | Kw::Constructor | Kw::Destructor) => {
                    decls.push(Decl::Routine(Box::new(self.routine(ctx)?)));
                }
                Tok::Keyword(Kw::Exports) => {
                    return Err(Diagnostic::error_with(code::NOT_SUPPORTED, self.span(), ": exports"));
                }
                _ => return Ok(decls),
            }
        }
    }

    fn label(&mut self) -> PResult<Label> {
        match self.peek() {
            Tok::Int(n) if *n <= 9999 => {
                let span = self.bump().span;
                Ok(Label::Number(*n as u32, span))
            }
            Tok::Ident(_) => Ok(Label::Name(self.ident()?)),
            _ => Err(self.unexpected(code::LABEL_IDENT_EXPECTED)),
        }
    }

    fn labels(&mut self) -> PResult<Decl> {
        self.bump();
        let mut labels = vec![self.label()?];
        while self.eat(&Tok::Comma) {
            labels.push(self.label()?);
        }
        self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
        Ok(Decl::Labels(labels))
    }

    fn consts(&mut self) -> PResult<Decl> {
        self.bump();
        let mut items = Vec::new();
        loop {
            let name = self.ident()?;
            let ty = if self.eat(&Tok::Colon) { Some(self.type_expr()?) } else { None };
            self.expect(&Tok::Eq, code::EQUAL_EXPECTED)?;
            let value = if ty.is_some() { self.const_init()? } else { ConstInit::Expr(self.expr()?) };
            self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
            items.push(ConstDecl { span: name.span.to(self.prev_span()), name, ty, value });
            if !matches!(self.peek(), Tok::Ident(_)) {
                return Ok(Decl::Consts(items));
            }
        }
    }

    /// Initializer of a typed constant: an expression, `(a, b)` or
    /// `(Field: v; ...)`.
    fn const_init(&mut self) -> PResult<ConstInit> {
        if !self.is(&Tok::LParen) {
            return Ok(ConstInit::Expr(self.expr()?));
        }
        let start = self.span();
        // Record initializer: "(" ident ":" ...
        if matches!(self.peek_at(1), Tok::Ident(_)) && self.peek_at(2) == &Tok::Colon {
            self.bump();
            let mut fields = Vec::new();
            loop {
                let name = self.ident()?;
                self.expect(&Tok::Colon, code::COLON_EXPECTED)?;
                fields.push((name, self.const_init()?));
                if self.eat(&Tok::Semi) && !self.is(&Tok::RParen) {
                    continue;
                }
                break;
            }
            self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
            return Ok(ConstInit::Record(fields, start.to(self.prev_span())));
        }
        self.bump();
        let mut items = vec![self.const_init()?];
        while self.eat(&Tok::Comma) {
            items.push(self.const_init()?);
        }
        self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
        let span = start.to(self.prev_span());
        // "(5)" followed by an operator was a parenthesized expression.
        if items.len() == 1
            && let ConstInit::Expr(_) = &items[0]
            && binop(self.peek()).is_some()
        {
            let ConstInit::Expr(inner) = items.pop().unwrap() else { unreachable!() };
            let lhs = self.postfix(Expr { kind: inner.kind, span })?;
            return Ok(ConstInit::Expr(self.binary_rhs(lhs, PREC_REL)?));
        }
        // A one-element list stays a list; semantic analysis also accepts
        // it for a scalar typed constant written as "(5)".
        Ok(ConstInit::List(items, span))
    }

    fn types(&mut self) -> PResult<Decl> {
        self.bump();
        let mut items = Vec::new();
        loop {
            let name = self.ident()?;
            self.expect(&Tok::Eq, code::EQUAL_EXPECTED)?;
            let ty = self.type_expr()?;
            self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
            items.push(TypeDecl { span: name.span.to(self.prev_span()), name, ty });
            if !matches!(self.peek(), Tok::Ident(_)) {
                return Ok(Decl::Types(items));
            }
        }
    }

    fn vars(&mut self) -> PResult<Decl> {
        self.bump();
        let mut items = Vec::new();
        loop {
            let names = self.ident_list()?;
            self.expect(&Tok::Colon, code::COLON_EXPECTED)?;
            let ty = self.type_expr()?;
            let absolute = if self.is_word("ABSOLUTE") {
                self.bump();
                if matches!(self.peek(), Tok::Int(_)) && self.peek_at(1) == &Tok::Colon {
                    let seg = self.simple_expr()?;
                    self.bump();
                    let ofs = self.simple_expr()?;
                    let span = seg.span.to(ofs.span);
                    Some(Absolute::Address(seg, ofs, span))
                } else {
                    Some(Absolute::Var(self.expr()?))
                }
            } else {
                None
            };
            self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
            items.push(VarDecl { span: names[0].span.to(self.prev_span()), names, ty, absolute });
            if !matches!(self.peek(), Tok::Ident(_)) {
                return Ok(Decl::Vars(items));
            }
        }
    }

    // ---- routines --------------------------------------------------------

    fn routine_kind(&mut self) -> PResult<RoutineKind> {
        let kind = match self.peek() {
            Tok::Keyword(Kw::Procedure) => RoutineKind::Procedure,
            Tok::Keyword(Kw::Function) => RoutineKind::Function,
            Tok::Keyword(Kw::Constructor) => RoutineKind::Constructor,
            Tok::Keyword(Kw::Destructor) => RoutineKind::Destructor,
            _ => return Err(self.unexpected(code::PROC_IDENT_EXPECTED)),
        };
        self.bump();
        Ok(kind)
    }

    /// `procedure Name(params): Result;` followed by directives.
    fn heading(&mut self) -> PResult<RoutineHeading> {
        let start = self.span();
        let switches = self.switches();
        let kind = self.routine_kind()?;
        let mut name = self.ident()?;
        let mut owner = None;
        if self.eat(&Tok::Dot) {
            owner = Some(name);
            name = self.ident()?;
        }
        let params = if self.is(&Tok::LParen) { self.params()? } else { Vec::new() };
        let result =
            if kind == RoutineKind::Function && self.eat(&Tok::Colon) { Some(self.type_expr()?) } else { None };
        self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
        let directives = self.directives()?;
        Ok(RoutineHeading { kind, owner, name, params, result, directives, span: start.to(self.prev_span()), switches })
    }

    fn directives(&mut self) -> PResult<Vec<Directive>> {
        let mut out = Vec::new();
        loop {
            let Tok::Ident(word) = self.peek() else { return Ok(out) };
            let upper = word.to_ascii_uppercase();
            if !DIRECTIVES.contains(&upper.as_str()) {
                return Ok(out);
            }
            // A field named like a directive ("Near: Integer") is not one.
            if matches!(self.peek_at(1), Tok::Colon | Tok::Comma) {
                return Ok(out);
            }
            let start = self.bump().span;
            let kind = match upper.as_str() {
                "FORWARD" => DirectiveKind::Forward,
                "EXTERNAL" => {
                    // Library and name are parsed by `routine`, which needs
                    // them; here only the marker is recorded.
                    out.push(Directive { kind: DirectiveKind::External, span: start });
                    return Ok(out);
                }
                "ASSEMBLER" => DirectiveKind::Assembler,
                "FAR" => DirectiveKind::Far,
                "NEAR" => DirectiveKind::Near,
                "INTERRUPT" => DirectiveKind::Interrupt,
                "CDECL" => DirectiveKind::Cdecl,
                "EXPORT" => DirectiveKind::Export,
                "VIRTUAL" => {
                    let index = if self.is(&Tok::Semi) { None } else { Some(self.expr()?) };
                    DirectiveKind::Virtual(index)
                }
                other => DirectiveKind::Other(other.to_string()),
            };
            self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
            out.push(Directive { kind, span: start });
        }
    }

    fn routine(&mut self, ctx: DeclCtx) -> PResult<Routine> {
        let start = self.span();
        let heading = self.heading()?;
        let external = heading.has(|d| matches!(d, DirectiveKind::External));
        let body = if external {
            let mut library = None;
            let mut name = None;
            if !self.is(&Tok::Semi) && !self.is_word("NAME") && !self.is_word("INDEX") {
                library = Some(self.expr()?);
            }
            if self.is_word("NAME") {
                self.bump();
                name = Some(self.expr()?);
            }
            if self.is_word("INDEX") {
                self.bump();
                self.expr()?;
            }
            self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
            RoutineBody::External { library, name }
        } else if self.is_kw(Kw::Inline) {
            let s = self.bump().span;
            self.skip_parens()?;
            self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
            RoutineBody::Inline(s.to(self.prev_span()))
        } else if ctx == DeclCtx::Interface || heading.has(|d| matches!(d, DirectiveKind::Forward)) {
            RoutineBody::Declaration
        } else {
            let block = self.block(false)?;
            self.expect(&Tok::Semi, code::SEMICOLON_EXPECTED)?;
            RoutineBody::Block(block)
        };
        Ok(Routine { heading, body, span: start.to(self.prev_span()) })
    }

    /// Skips a parenthesized token sequence (used for `inline(...)`).
    fn skip_parens(&mut self) -> PResult<()> {
        self.expect(&Tok::LParen, code::LPAREN_EXPECTED)?;
        let mut depth = 1;
        while depth > 0 {
            match self.peek() {
                Tok::LParen => depth += 1,
                Tok::RParen => depth -= 1,
                Tok::Eof => return Err(self.unexpected(code::RPAREN_EXPECTED)),
                _ => {}
            }
            self.bump();
        }
        Ok(())
    }

    fn params(&mut self) -> PResult<Vec<ParamGroup>> {
        self.expect(&Tok::LParen, code::LPAREN_EXPECTED)?;
        let mut groups = Vec::new();
        loop {
            let start = self.span();
            let mode = if self.eat_kw(Kw::Var) {
                ParamMode::Var
            } else if self.eat_kw(Kw::Const) {
                ParamMode::Const
            } else {
                ParamMode::Value
            };
            let names = self.ident_list()?;
            let ty = if self.eat(&Tok::Colon) { Some(self.type_expr()?) } else { None };
            groups.push(ParamGroup { mode, names, ty, span: start.to(self.prev_span()) });
            if self.eat(&Tok::Semi) {
                continue;
            }
            self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
            return Ok(groups);
        }
    }

    // ---- types -----------------------------------------------------------

    fn type_expr(&mut self) -> PResult<TypeExpr> {
        let start = self.span();
        let kind = match self.peek() {
            Tok::Caret => {
                self.bump();
                let target = if self.is_kw(Kw::String) {
                    let s = self.bump().span;
                    TypeExpr { kind: TypeKind::String(None), span: s }
                } else {
                    let q = self.qual_ident()?;
                    TypeExpr { span: q.span(), kind: TypeKind::Named(q) }
                };
                TypeKind::Pointer(Box::new(target))
            }
            Tok::CaretChar(c) => {
                // "^T" lexed as a control character: a pointer to type T.
                let span = self.bump().span;
                let name_span = Span::new(span.file, span.start + 1, span.end);
                let name = Ident { name: ((*c ^ 0x40) as char).to_string(), span: name_span };
                let target = TypeExpr { kind: TypeKind::Named(QualIdent { unit: None, name }), span: name_span };
                TypeKind::Pointer(Box::new(target))
            }
            Tok::Keyword(Kw::Packed) => {
                self.bump();
                match self.type_expr()?.kind {
                    TypeKind::Array { index, elem, .. } => TypeKind::Array { packed: true, index, elem },
                    TypeKind::Record { fields, .. } => TypeKind::Record { packed: true, fields },
                    TypeKind::Set { base, .. } => TypeKind::Set { packed: true, base },
                    other @ TypeKind::File(_) => other,
                    _ => return Err(Diagnostic::error(code::ERROR_IN_TYPE, start)),
                }
            }
            Tok::Keyword(Kw::Array) => {
                self.bump();
                if self.eat_kw(Kw::Of) {
                    TypeKind::OpenArray(Box::new(self.type_expr()?))
                } else {
                    self.expect(&Tok::LBracket, code::LBRACKET_EXPECTED)?;
                    let mut index = vec![self.type_expr()?];
                    while self.eat(&Tok::Comma) {
                        index.push(self.type_expr()?);
                    }
                    self.expect(&Tok::RBracket, code::RBRACKET_EXPECTED)?;
                    self.expect_kw(Kw::Of, code::OF_EXPECTED)?;
                    TypeKind::Array { packed: false, index, elem: Box::new(self.type_expr()?) }
                }
            }
            Tok::Keyword(Kw::Record) => {
                self.bump();
                let fields = self.field_list()?;
                self.expect_kw(Kw::End, code::END_EXPECTED)?;
                TypeKind::Record { packed: false, fields }
            }
            Tok::Keyword(Kw::Object) => TypeKind::Object(Box::new(self.object_type()?)),
            Tok::Keyword(Kw::Set) => {
                self.bump();
                self.expect_kw(Kw::Of, code::OF_EXPECTED)?;
                TypeKind::Set { packed: false, base: Box::new(self.type_expr()?) }
            }
            Tok::Keyword(Kw::File) => {
                self.bump();
                if self.eat_kw(Kw::Of) {
                    TypeKind::File(Some(Box::new(self.type_expr()?)))
                } else {
                    TypeKind::File(None)
                }
            }
            Tok::Keyword(Kw::String) => {
                self.bump();
                if self.eat(&Tok::LBracket) {
                    let len = self.expr()?;
                    self.expect(&Tok::RBracket, code::RBRACKET_EXPECTED)?;
                    TypeKind::String(Some(Box::new(len)))
                } else {
                    TypeKind::String(None)
                }
            }
            Tok::Keyword(Kw::Procedure | Kw::Function) => {
                let function = self.is_kw(Kw::Function);
                self.bump();
                let params = if self.is(&Tok::LParen) { self.params()? } else { Vec::new() };
                let result = if function {
                    self.expect(&Tok::Colon, code::COLON_EXPECTED)?;
                    Some(Box::new(self.type_expr()?))
                } else {
                    None
                };
                TypeKind::Procedural { function, params, result }
            }
            Tok::LParen => {
                self.bump();
                let names = self.ident_list()?;
                self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
                TypeKind::Enum(names)
            }
            _ => {
                // A type name or a subrange of constants.
                let lo = self.simple_expr()?;
                if self.eat(&Tok::DotDot) {
                    let hi = self.simple_expr()?;
                    TypeKind::Subrange(Box::new(lo), Box::new(hi))
                } else {
                    match lo.kind {
                        ExprKind::Name(name) => TypeKind::Named(QualIdent { unit: None, name }),
                        ExprKind::Field { base, field } if matches!(base.kind, ExprKind::Name(_)) => {
                            let ExprKind::Name(unit) = base.kind else { unreachable!() };
                            TypeKind::Named(QualIdent { unit: Some(unit), name: field })
                        }
                        _ => return Err(Diagnostic::error_with(code::TYPE_IDENT_EXPECTED, lo.span, "")),
                    }
                }
            }
        };
        Ok(TypeExpr { kind, span: start.to(self.prev_span()) })
    }

    fn field_list(&mut self) -> PResult<FieldList> {
        let mut fields = Vec::new();
        while matches!(self.peek(), Tok::Ident(_)) {
            let names = self.ident_list()?;
            self.expect(&Tok::Colon, code::COLON_EXPECTED)?;
            let ty = self.type_expr()?;
            fields.push(FieldDecl { span: names[0].span.to(self.prev_span()), names, ty });
            if !self.eat(&Tok::Semi) {
                break;
            }
        }
        let variant = if self.is_kw(Kw::Case) { Some(Box::new(self.variant_part()?)) } else { None };
        Ok(FieldList { fields, variant })
    }

    fn variant_part(&mut self) -> PResult<VariantPart> {
        let start = self.bump().span;
        let (tag, tag_type) = if matches!(self.peek(), Tok::Ident(_)) && self.peek_at(1) == &Tok::Colon {
            let tag = self.ident()?;
            self.bump();
            (Some(tag), self.qual_ident()?)
        } else {
            (None, self.qual_ident()?)
        };
        self.expect_kw(Kw::Of, code::OF_EXPECTED)?;
        let mut cases = Vec::new();
        while !self.is_kw(Kw::End) && !self.is(&Tok::RParen) {
            let case_start = self.span();
            let labels = self.case_labels()?;
            self.expect(&Tok::Colon, code::COLON_EXPECTED)?;
            self.expect(&Tok::LParen, code::LPAREN_EXPECTED)?;
            let fields = self.field_list()?;
            self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
            cases.push(VariantCase { labels, fields, span: case_start.to(self.prev_span()) });
            if !self.eat(&Tok::Semi) {
                break;
            }
        }
        Ok(VariantPart { tag, tag_type, cases, span: start.to(self.prev_span()) })
    }

    fn object_type(&mut self) -> PResult<ObjectType> {
        self.bump();
        let parent = if self.eat(&Tok::LParen) {
            let q = self.qual_ident()?;
            self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
            Some(q)
        } else {
            None
        };
        let mut members = Vec::new();
        let mut private = false;
        loop {
            match self.peek() {
                Tok::Keyword(Kw::End) => {
                    self.bump();
                    return Ok(ObjectType { parent, members });
                }
                Tok::Keyword(Kw::Procedure | Kw::Function | Kw::Constructor | Kw::Destructor) => {
                    let heading = self.heading()?;
                    members.push(ObjectMember::Method { heading, private });
                }
                Tok::Ident(w)
                    if (w.eq_ignore_ascii_case("PRIVATE") || w.eq_ignore_ascii_case("PUBLIC"))
                        && !matches!(self.peek_at(1), Tok::Colon | Tok::Comma) =>
                {
                    private = w.eq_ignore_ascii_case("PRIVATE");
                    self.bump();
                }
                Tok::Ident(_) => {
                    let names = self.ident_list()?;
                    self.expect(&Tok::Colon, code::COLON_EXPECTED)?;
                    let ty = self.type_expr()?;
                    let decl = FieldDecl { span: names[0].span.to(self.prev_span()), names, ty };
                    members.push(ObjectMember::Field { decl, private });
                    if !self.eat(&Tok::Semi) && !self.is_kw(Kw::End) {
                        return Err(self.unexpected(code::SEMICOLON_EXPECTED));
                    }
                }
                _ => return Err(self.unexpected(code::END_EXPECTED)),
            }
        }
    }

    // ---- statements ------------------------------------------------------

    fn compound(&mut self) -> PResult<(Vec<Stmt>, Span)> {
        let start = self.expect_kw(Kw::Begin, code::BEGIN_EXPECTED)?;
        let stmts = self.stmt_list(|t| matches!(t, Tok::Keyword(Kw::End)))?;
        self.expect_kw(Kw::End, code::END_EXPECTED)?;
        Ok((stmts, start.to(self.prev_span())))
    }

    /// Statements separated by `;` up to a terminator (not consumed).
    fn stmt_list(&mut self, terminator: impl Fn(&Tok) -> bool) -> PResult<Vec<Stmt>> {
        let mut stmts = Vec::new();
        loop {
            stmts.push(self.statement()?);
            if self.eat(&Tok::Semi) {
                continue;
            }
            if terminator(self.peek()) {
                return Ok(stmts);
            }
            if self.is(&Tok::Eof) {
                return Err(self.unexpected(code::END_EXPECTED));
            }
            return Err(self.unexpected(code::SEMICOLON_EXPECTED));
        }
    }

    fn statement(&mut self) -> PResult<Stmt> {
        let start = self.span();
        let switches = self.switches();
        let kind = match self.peek() {
            Tok::Int(_) | Tok::Ident(_) if self.peek_at(1) == &Tok::Colon => {
                let label = self.label()?;
                self.bump();
                let inner = self.statement()?;
                StmtKind::Labeled(label, Box::new(inner))
            }
            Tok::Keyword(Kw::Begin) => StmtKind::Compound(self.compound()?.0),
            Tok::Keyword(Kw::If) => {
                self.bump();
                let cond = self.expr()?;
                self.expect_kw(Kw::Then, code::THEN_EXPECTED)?;
                let then = Box::new(self.statement()?);
                let otherwise = if self.eat_kw(Kw::Else) { Some(Box::new(self.statement()?)) } else { None };
                StmtKind::If { cond, then, otherwise }
            }
            Tok::Keyword(Kw::Case) => self.case_stmt()?,
            Tok::Keyword(Kw::While) => {
                self.bump();
                let cond = self.expr()?;
                self.expect_kw(Kw::Do, code::DO_EXPECTED)?;
                StmtKind::While { cond, body: Box::new(self.statement()?) }
            }
            Tok::Keyword(Kw::Repeat) => {
                self.bump();
                let body = self.stmt_list(|t| matches!(t, Tok::Keyword(Kw::Until)))?;
                self.expect_kw(Kw::Until, code::SYNTAX_ERROR)?;
                StmtKind::Repeat { body, cond: self.expr()? }
            }
            Tok::Keyword(Kw::For) => {
                self.bump();
                let var = self.ident()?;
                self.expect(&Tok::Assign, code::ASSIGN_EXPECTED)?;
                let from = self.expr()?;
                let down = if self.eat_kw(Kw::To) {
                    false
                } else if self.eat_kw(Kw::Downto) {
                    true
                } else {
                    return Err(self.unexpected(code::TO_DOWNTO_EXPECTED));
                };
                let to = self.expr()?;
                self.expect_kw(Kw::Do, code::DO_EXPECTED)?;
                StmtKind::For { var, from, to, down, body: Box::new(self.statement()?) }
            }
            Tok::Keyword(Kw::With) => {
                self.bump();
                let mut records = vec![self.expr()?];
                while self.eat(&Tok::Comma) {
                    records.push(self.expr()?);
                }
                self.expect_kw(Kw::Do, code::DO_EXPECTED)?;
                StmtKind::With { records, body: Box::new(self.statement()?) }
            }
            Tok::Keyword(Kw::Goto) => {
                self.bump();
                StmtKind::Goto(self.label()?)
            }
            Tok::Keyword(Kw::Asm) => StmtKind::Asm(self.asm_block()?),
            Tok::Keyword(Kw::Inline) => {
                return Err(Diagnostic::error_with(
                    code::DOS_ONLY,
                    self.span(),
                    ": inline(...) berisi kode mesin 16-bit",
                ));
            }
            Tok::Semi | Tok::Keyword(Kw::End | Kw::Else | Kw::Until) => {
                let span = Span::new(start.file, start.start, start.start);
                return Ok(Stmt { kind: StmtKind::Empty, span, switches });
            }
            Tok::Ident(_) | Tok::Keyword(Kw::Inherited) | Tok::LParen | Tok::At => {
                let target = self.factor()?;
                if self.eat(&Tok::Assign) {
                    StmtKind::Assign { target, value: self.expr()? }
                } else {
                    StmtKind::Call(target)
                }
            }
            _ => return Err(self.unexpected(code::ERROR_IN_STATEMENT)),
        };
        Ok(Stmt { kind, span: start.to(self.prev_span()), switches })
    }

    fn case_labels(&mut self) -> PResult<Vec<CaseLabel>> {
        let mut labels = Vec::new();
        loop {
            let lo = self.expr()?;
            let hi = if self.eat(&Tok::DotDot) { Some(self.expr()?) } else { None };
            labels.push(CaseLabel { lo, hi });
            if !self.eat(&Tok::Comma) {
                return Ok(labels);
            }
        }
    }

    fn case_stmt(&mut self) -> PResult<StmtKind> {
        self.bump();
        let expr = self.expr()?;
        self.expect_kw(Kw::Of, code::OF_EXPECTED)?;
        let mut arms = Vec::new();
        let mut otherwise = None;
        loop {
            if self.is_kw(Kw::End) {
                break;
            }
            // FPC also accepts "otherwise"; a case label named Otherwise
            // would be followed by ":".
            let otherwise_word = self.is_word("OTHERWISE") && self.peek_at(1) != &Tok::Colon;
            if self.eat_kw(Kw::Else) || otherwise_word {
                if otherwise_word {
                    self.bump();
                }
                otherwise = Some(self.stmt_list(|t| matches!(t, Tok::Keyword(Kw::End)))?);
                break;
            }
            let start = self.span();
            let labels = self.case_labels()?;
            self.expect(&Tok::Colon, code::COLON_EXPECTED)?;
            let body = self.statement()?;
            arms.push(CaseArm { labels, body, span: start.to(self.prev_span()) });
            if !self.eat(&Tok::Semi) && !self.is_kw(Kw::End) && !self.is_kw(Kw::Else) {
                return Err(self.unexpected(code::SEMICOLON_EXPECTED));
            }
        }
        self.expect_kw(Kw::End, code::END_EXPECTED)?;
        Ok(StmtKind::Case { expr, arms, otherwise })
    }

    fn asm_block(&mut self) -> PResult<AsmBlock> {
        let start = self.expect_kw(Kw::Asm, code::SYNTAX_ERROR)?;
        let text = match self.peek() {
            Tok::AsmText(t) => {
                self.bump();
                t.clone()
            }
            _ => String::new(),
        };
        self.expect_kw(Kw::End, code::END_EXPECTED)?;
        Ok(AsmBlock { text, span: start.to(self.prev_span()) })
    }

    // ---- expressions -----------------------------------------------------

    fn expr(&mut self) -> PResult<Expr> {
        let lhs = self.prefix()?;
        self.binary_rhs(lhs, PREC_REL)
    }

    /// An expression without relational operators (subrange bounds).
    fn simple_expr(&mut self) -> PResult<Expr> {
        let lhs = self.prefix()?;
        self.binary_rhs(lhs, PREC_ADD)
    }

    /// A factor, possibly signed. Like FPC, a sign binds to the factor:
    /// `-1 and 3` is `(-1) and 3`.
    fn prefix(&mut self) -> PResult<Expr> {
        let op = match self.peek() {
            Tok::Minus => UnOp::Neg,
            Tok::Plus => UnOp::Pos,
            _ => return self.factor(),
        };
        let start = self.bump().span;
        let operand = self.prefix()?;
        Ok(Expr { span: start.to(operand.span), kind: ExprKind::Unary(op, Box::new(operand)) })
    }

    fn binary_rhs(&mut self, mut lhs: Expr, min: u8) -> PResult<Expr> {
        while let Some((op, prec)) = binop(self.peek()) {
            if prec < min {
                break;
            }
            self.bump();
            let rhs = self.prefix()?;
            let rhs = self.binary_rhs(rhs, prec + 1)?;
            lhs = Expr { span: lhs.span.to(rhs.span), kind: ExprKind::Binary(op, Box::new(lhs), Box::new(rhs)) };
        }
        Ok(lhs)
    }

    fn factor(&mut self) -> PResult<Expr> {
        let start = self.span();
        let kind = match self.peek() {
            Tok::Int(v) => {
                self.bump();
                ExprKind::Int(*v)
            }
            Tok::Real(v) => {
                self.bump();
                ExprKind::Real(*v)
            }
            Tok::Str(_) | Tok::CaretChar(_) => {
                let mut bytes = Vec::new();
                loop {
                    match self.peek() {
                        Tok::Str(b) => bytes.extend_from_slice(b),
                        Tok::CaretChar(c) => bytes.push(*c),
                        _ => break,
                    }
                    self.bump();
                }
                ExprKind::Str(bytes)
            }
            Tok::Keyword(Kw::Nil) => {
                self.bump();
                ExprKind::Nil
            }
            Tok::Keyword(Kw::Not) => {
                self.bump();
                let operand = self.factor()?;
                return Ok(Expr { span: start.to(operand.span), kind: ExprKind::Unary(UnOp::Not, Box::new(operand)) });
            }
            Tok::At => {
                self.bump();
                let operand = self.factor()?;
                return Ok(Expr {
                    span: start.to(operand.span),
                    kind: ExprKind::Unary(UnOp::AddrOf, Box::new(operand)),
                });
            }
            Tok::LParen => {
                self.bump();
                let inner = self.expr()?;
                self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
                let e = Expr { kind: inner.kind, span: start.to(self.prev_span()) };
                return self.postfix(e);
            }
            Tok::LBracket => {
                self.bump();
                let mut items = Vec::new();
                if !self.is(&Tok::RBracket) {
                    loop {
                        let lo = self.expr()?;
                        let hi = if self.eat(&Tok::DotDot) { Some(self.expr()?) } else { None };
                        items.push(SetItem { lo, hi });
                        if !self.eat(&Tok::Comma) {
                            break;
                        }
                    }
                }
                self.expect(&Tok::RBracket, code::RBRACKET_EXPECTED)?;
                ExprKind::Set(items)
            }
            Tok::Ident(_) => {
                let name = self.ident()?;
                let e = Expr { span: name.span, kind: ExprKind::Name(name) };
                return self.postfix(e);
            }
            Tok::Keyword(Kw::Inherited) => {
                self.bump();
                let name = self.ident()?;
                let e = Expr { span: start.to(name.span), kind: ExprKind::Inherited(name) };
                return self.postfix(e);
            }
            Tok::Keyword(Kw::String) => {
                self.bump();
                let e = Expr { span: start, kind: ExprKind::StringType };
                return self.postfix(e);
            }
            _ => return Err(self.unexpected(code::ERROR_IN_EXPR)),
        };
        Ok(Expr { kind, span: start.to(self.prev_span()) })
    }

    fn postfix(&mut self, mut e: Expr) -> PResult<Expr> {
        loop {
            match self.peek() {
                Tok::LParen => {
                    self.bump();
                    let mut args = Vec::new();
                    if !self.is(&Tok::RParen) {
                        loop {
                            let value = self.expr()?;
                            let width = if self.eat(&Tok::Colon) { Some(self.expr()?) } else { None };
                            let decimals =
                                if width.is_some() && self.eat(&Tok::Colon) { Some(self.expr()?) } else { None };
                            args.push(Arg { value, width, decimals });
                            if !self.eat(&Tok::Comma) {
                                break;
                            }
                        }
                    }
                    self.expect(&Tok::RParen, code::RPAREN_EXPECTED)?;
                    e = Expr { span: e.span.to(self.prev_span()), kind: ExprKind::Call { callee: Box::new(e), args } };
                }
                Tok::LBracket => {
                    self.bump();
                    let mut indices = vec![self.expr()?];
                    while self.eat(&Tok::Comma) {
                        indices.push(self.expr()?);
                    }
                    self.expect(&Tok::RBracket, code::RBRACKET_EXPECTED)?;
                    e = Expr {
                        span: e.span.to(self.prev_span()),
                        kind: ExprKind::Index { base: Box::new(e), indices },
                    };
                }
                Tok::Dot => {
                    self.bump();
                    let field = match self.peek() {
                        Tok::Ident(_) => self.ident()?,
                        _ => return Err(self.unexpected(code::FIELD_IDENT_EXPECTED)),
                    };
                    e = Expr { span: e.span.to(field.span), kind: ExprKind::Field { base: Box::new(e), field } };
                }
                Tok::Caret => {
                    let s = self.bump().span;
                    e = Expr { span: e.span.to(s), kind: ExprKind::Deref(Box::new(e)) };
                }
                _ => return Ok(e),
            }
        }
    }
}

fn binop(t: &Tok) -> Option<(BinOp, u8)> {
    Some(match t {
        Tok::Eq => (BinOp::Eq, PREC_REL),
        Tok::Ne => (BinOp::Ne, PREC_REL),
        Tok::Lt => (BinOp::Lt, PREC_REL),
        Tok::Le => (BinOp::Le, PREC_REL),
        Tok::Gt => (BinOp::Gt, PREC_REL),
        Tok::Ge => (BinOp::Ge, PREC_REL),
        Tok::Keyword(Kw::In) => (BinOp::In, PREC_REL),
        Tok::Plus => (BinOp::Add, PREC_ADD),
        Tok::Minus => (BinOp::Sub, PREC_ADD),
        Tok::Keyword(Kw::Or) => (BinOp::Or, PREC_ADD),
        Tok::Keyword(Kw::Xor) => (BinOp::Xor, PREC_ADD),
        Tok::Star => (BinOp::Mul, PREC_MUL),
        Tok::Slash => (BinOp::RealDiv, PREC_MUL),
        Tok::Keyword(Kw::Div) => (BinOp::Div, PREC_MUL),
        Tok::Keyword(Kw::Mod) => (BinOp::Mod, PREC_MUL),
        Tok::Keyword(Kw::And) => (BinOp::And, PREC_MUL),
        Tok::Keyword(Kw::Shl) => (BinOp::Shl, PREC_MUL),
        Tok::Keyword(Kw::Shr) => (BinOp::Shr, PREC_MUL),
        _ => return None,
    })
}
