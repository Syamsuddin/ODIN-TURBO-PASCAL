// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! Turbo Pascal objects and classes, lowered to what the code generator
//! already knows: an object is a record (with a VMT pointer when it has
//! constructors, destructors or virtual methods), a VMT is a read-only
//! global of code pointers, and a method is a routine whose first parameter
//! is `Self`, a pointer to the object.
//!
//! Constructors also take the VMT to store (`nil` for `inherited Init`) and
//! return `Self`, or `nil` after `Fail`. Called with `Self = nil` they
//! allocate the object (size from the VMT), which makes `New(P, Init)` and
//! `New(PType, Init)` ordinary calls. Layout matches FPC `-Mtp`: inherited
//! fields first, the VMT pointer after the fields of the first type in the
//! hierarchy that needs one.
//!
//! A class is a reference to an instance laid out like an object whose VMT
//! pointer is at offset 0, with `System.TObject` as the root. `TFoo.Create`
//! is a constructor call with `Self = nil` and TFoo's VMT; the prologue of
//! a class constructor also zeroes the new instance. Destroying an instance
//! (`Obj.Destroy`, or `Destroy` inside `TObject.Free`) calls the destructor
//! and then frees the memory, sized from the VMT; `inherited Destroy` only
//! calls. Class methods get the class (a VMT address) as `Self`. Slot 0 of a
//! class VMT holds the class name.

use std::collections::HashSet;

use odin_base::{Diagnostic, Span, code};
use odin_ir::*;
use odin_syntax::{Switches, ast};

use crate::expr::{Class, Resolved};
use crate::scope::Sym;
use crate::{Analyzer, Frame, SResult};

/// How a method call passes `Self`.
#[derive(Clone, Debug)]
pub(crate) enum SelfArg {
    /// An object variable, or the instance a class reference points to;
    /// its address is passed.
    Instance(Expr),
    /// A pointer to the object; `nil` makes a constructor allocate.
    Pointer(Expr),
    /// A class reference (VMT address), the `Self` of a class method.
    Vmt(Expr),
}

/// The VMT a constructor call passes.
#[derive(Clone, Debug)]
pub(crate) enum CtorVmt {
    /// The VMT of this object type, which the constructor stores.
    Of(TypeId),
    /// `nil`: `inherited Init` and `TParent.Init` keep the VMT already set.
    Keep,
    /// A class reference known only at run time (`C.Create` with
    /// `C: class of TFoo`); a virtual constructor dispatches through it.
    Value(Expr),
}

/// A method together with the object it is called on.
#[derive(Clone, Debug)]
pub(crate) struct MethodRef {
    pub this: SelfArg,
    /// Static type of `Self` (gives the VMT offset).
    pub object: TypeId,
    pub method: Method,
    /// Every visible overload of the name, `method` first; the arguments
    /// pick one.
    pub candidates: Vec<Method>,
    /// Virtual methods dispatch through the VMT, except for `inherited`
    /// and `TParent.Method` calls.
    pub dispatch: bool,
    pub vmt: CtorVmt,
}

/// A property together with the instance it belongs to.
#[derive(Clone, Debug)]
pub(crate) struct PropRef {
    pub this: SelfArg,
    pub object: TypeId,
    pub prop: Property,
}

/// The object a method body belongs to.
#[derive(Clone, Debug)]
pub(crate) struct ObjectScope {
    pub ty: TypeId,
    pub method: Method,
    /// Constructor: set when it allocated `Self` (so `Fail` frees it).
    pub allocated: Option<Var>,
}

fn align_up(v: u64, a: u64) -> u64 {
    v.div_ceil(a.max(1)) * a.max(1)
}

fn method_kind(k: ast::RoutineKind) -> MethodKind {
    match k {
        ast::RoutineKind::Procedure => MethodKind::Procedure,
        ast::RoutineKind::Function => MethodKind::Function,
        ast::RoutineKind::Constructor => MethodKind::Constructor,
        ast::RoutineKind::Destructor => MethodKind::Destructor,
    }
}

fn visibility(v: ast::Visibility) -> Visibility {
    match v {
        ast::Visibility::Public | ast::Visibility::Published => Visibility::Public,
        ast::Visibility::Protected => Visibility::Protected,
        ast::Visibility::StrictProtected => Visibility::StrictProtected,
        ast::Visibility::Private => Visibility::Private,
        ast::Visibility::StrictPrivate => Visibility::StrictPrivate,
    }
}

/// Hidden parameters before the declared ones: `Self`, and the VMT for
/// constructors.
pub(crate) fn hidden_params(kind: MethodKind) -> usize {
    if kind == MethodKind::Constructor { 2 } else { 1 }
}

/// Directives of a method heading.
struct Flags {
    is_virtual: bool,
    is_override: bool,
    is_abstract: bool,
    reintroduce: bool,
    overload: bool,
}

fn flags(h: &ast::RoutineHeading) -> Flags {
    Flags {
        is_virtual: h.has(|d| matches!(d, ast::DirectiveKind::Virtual(_))),
        is_override: h.has(|d| matches!(d, ast::DirectiveKind::Override)),
        is_abstract: h.has(|d| matches!(d, ast::DirectiveKind::Abstract)),
        reintroduce: h.has(|d| matches!(d, ast::DirectiveKind::Reintroduce)),
        overload: h.has(|d| matches!(d, ast::DirectiveKind::Overload)),
    }
}

impl Analyzer<'_> {
    // ---- class types -------------------------------------------------------------

    /// `TFoo = class ... end` (or a forward `TFoo = class;`) in a type
    /// section: the class type and its instance layout.
    pub(crate) fn class_decl(&mut self, name: &ast::Ident, obj: &ast::ObjectType) -> SResult<()> {
        if !self.frames.is_empty() {
            return self.error(code::LOCAL_OBJECT_TYPE, name.span);
        }
        let key = name.key();
        let forward = self.forward_classes.iter().position(|(_, n, _)| *n == key);
        let class_ty = match forward {
            Some(i) if matches!(self.lookup_local(&key), Some(Sym::Type(t)) if t == self.forward_classes[i].0) => {
                if obj.forward {
                    return self.error_with(code::DUPLICATE_IDENT, name.span, format!(": {}", name.name));
                }
                self.forward_classes.remove(i).0
            }
            _ => {
                let instance = self.types.add(Type::Record { fields: Vec::new(), size: 0, align: 1 });
                self.types.set_name(instance, &name.name);
                let class_ty = self.types.add(Type::Class(instance));
                self.types.set_name(class_ty, &name.name);
                self.declare(name, Sym::Type(class_ty))?;
                class_ty
            }
        };
        if obj.forward {
            self.forward_classes.push((class_ty, key, name.span));
            return Ok(());
        }
        let instance = self.types.instance(class_ty).expect("class type");
        self.object_type(instance, Some(class_ty), name, obj)
    }

    /// Forward class declarations of the type section just analysed must
    /// have been completed in it.
    pub(crate) fn check_forward_classes(&mut self) -> SResult<()> {
        if let Some((_, key, span)) = self.forward_classes.first() {
            return self.error_with(code::UNDEFINED_FORWARD, *span, format!(": class {key}"));
        }
        Ok(())
    }

    /// `class of T` for class type `class_ty`, shared by every use.
    pub(crate) fn class_ref_type(&mut self, class_ty: TypeId) -> TypeId {
        if let Some(t) = self.class_refs.get(&class_ty) {
            return *t;
        }
        let t = self.types.add(Type::ClassRef(class_ty));
        self.class_refs.insert(class_ty, t);
        t
    }

    /// The class a class reference type refers to.
    pub(crate) fn class_of_ref(&self, ty: TypeId) -> Option<TypeId> {
        match self.types.get(ty) {
            Type::ClassRef(c) => Some(*c),
            _ => None,
        }
    }

    /// A class name used as a value: its VMT, typed `class of` it.
    pub(crate) fn class_value(&mut self, class_ty: TypeId, span: Span) -> SResult<Expr> {
        let instance = self.types.instance(class_ty).expect("class type");
        let vmt = self.vmt_address(instance, span)?;
        let ty = self.class_ref_type(class_ty);
        Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(vmt)), ty, span))
    }

    // ---- object types --------------------------------------------------------------

    /// Fills in object type `ty`, already declared under `name` so that its
    /// methods can mention it. For a class, `ty` is the instance layout and
    /// `class` the class type.
    pub(crate) fn object_type(
        &mut self,
        ty: TypeId,
        class: Option<TypeId>,
        name: &ast::Ident,
        obj: &ast::ObjectType,
    ) -> SResult<()> {
        if !self.frames.is_empty() {
            return self.error(code::LOCAL_OBJECT_TYPE, name.span);
        }
        let is_class = class.is_some();
        let parent = match &obj.parent {
            Some(q) => match self.lookup_type(q)? {
                Some(t) if !is_class && self.types.object(t).is_some() && t != ty => Some(t),
                Some(t) if is_class && Some(t) != class && self.types.class_object(t).is_some() => {
                    self.types.instance(t)
                }
                Some(_) if is_class => return self.error(code::CLASS_TYPE_EXPECTED, q.span()),
                Some(_) => return self.error(code::OBJECT_TYPE_EXPECTED, q.span()),
                None => return self.error_with(code::UNKNOWN_IDENT, q.span(), format!(": {}", q.name.name)),
            },
            None if is_class => match self.tobject {
                Some(root) => self.types.instance(root),
                None if self.cur_unit == Some(0) && name.key() == "TOBJECT" => None,
                None => {
                    return self.error_with(code::INTERNAL, name.span, ": RTL tidak lengkap, TObject tidak ada");
                }
            },
            None => None,
        };
        let base = parent.and_then(|p| self.types.object(p).cloned());
        let mut fields = base.as_ref().map(|b| b.fields.clone()).unwrap_or_default();
        let mut field_vis = base.as_ref().map(|b| b.field_vis.clone()).unwrap_or_default();
        let mut methods = base.as_ref().map(|b| b.methods.clone()).unwrap_or_default();
        let mut properties = base.as_ref().map(|b| b.properties.clone()).unwrap_or_default();
        let mut class_vars = base.as_ref().map(|b| b.class_vars.clone()).unwrap_or_default();
        let mut slots = base.as_ref().map_or(0, |b| b.slots);
        let mut vmt_offset = base.as_ref().and_then(|b| b.vmt_offset);
        let mut start = base.as_ref().map_or(0, |b| b.size);
        let mut align = base.as_ref().map_or(1, |b| b.align);
        if is_class && base.is_none() {
            // The root class: the VMT pointer comes first, and the VMT
            // starts with its data slots.
            vmt_offset = Some(0);
            start = 8;
            align = 8;
            slots = CLASS_DATA_SLOTS;
        }

        // Fields and class variables.
        let object_key = name.key();
        let mut seen: HashSet<String> = fields.iter().map(|f| f.name.to_ascii_uppercase()).collect();
        let mut list = Vec::new();
        for m in &obj.members {
            let ast::ObjectMember::Field { decl, vis, class_var } = m else { continue };
            if *class_var && !is_class {
                return self.error_with(code::CLASS_ONLY, decl.span, ": class var");
            }
            let fty = self.resolve_type(&decl.ty)?;
            if fty == ty {
                return self.error(code::ERROR_IN_TYPE, decl.ty.span);
            }
            let vis = visibility(*vis);
            for n in &decl.names {
                if !seen.insert(n.key()) {
                    return self.error_with(code::DUPLICATE_IDENT, n.span, format!(": {}", n.name));
                }
                if *class_var {
                    let symbol = format!("{}.{}.{}", self.unit_prefix(), object_key, n.key());
                    self.globals.push(Global {
                        symbol,
                        name: format!("{}.{}", name.name, n.name),
                        ty: fty,
                        init: None,
                        readonly: false,
                        span: n.span,
                    });
                    let global = self.globals.len() as u32 - 1;
                    class_vars.push(ClassVar { name: n.name.clone(), global, ty: fty, vis, owner: ty });
                    continue;
                }
                list.push((n.name.clone(), fty));
                if vis != Visibility::Public {
                    field_vis.push(FieldVis { name: n.key(), vis, owner: ty });
                }
            }
        }
        let (own, mut end, own_align) = self.types.layout_fields(&list, start);
        fields.extend(own);
        align = align.max(own_align);
        let needs_vmt = obj.members.iter().any(|m| match m {
            ast::ObjectMember::Method { heading, .. } => {
                matches!(heading.kind, ast::RoutineKind::Constructor | ast::RoutineKind::Destructor)
                    || heading.has(|d| matches!(d, ast::DirectiveKind::Virtual(_)))
            }
            _ => false,
        });
        if vmt_offset.is_none() && needs_vmt {
            let off = align_up(end, 8);
            vmt_offset = Some(off);
            end = off + 8;
            align = align.max(8);
        }
        let size = align_up(end, align as u64);
        if size > i32::MAX as u64 {
            return self.error(code::STRUCTURE_TOO_LARGE, name.span);
        }
        let module = self.cur_unit;
        let provisional = |methods: Vec<Method>, properties: Vec<Property>, slots: u32, vmt: Option<u32>| ObjectType {
            parent,
            fields: fields.clone(),
            field_vis: field_vis.clone(),
            methods,
            properties,
            class_vars: class_vars.clone(),
            size,
            align,
            vmt_offset,
            vmt,
            slots,
            module,
            class,
        };
        // The type is complete enough for method signatures that mention it.
        self.types.set(ty, Type::Object(Box::new(provisional(methods.clone(), properties.clone(), slots, None))));

        // Methods.
        let mut own_methods: Vec<(String, usize)> = Vec::new();
        for m in &obj.members {
            let ast::ObjectMember::Method { heading: h, vis } = m else { continue };
            let key = h.name.key();
            if seen.contains(&key) {
                return self.error_with(code::DUPLICATE_IDENT, h.name.span, format!(": {}", h.name.name));
            }
            let kind = method_kind(h.kind);
            let f = flags(h);
            if !is_class && (f.is_override || f.reintroduce || h.class_method) {
                let what = if f.is_override {
                    "override"
                } else if f.reintroduce {
                    "reintroduce"
                } else {
                    "class procedure/function"
                };
                return self.error_with(code::CLASS_ONLY, h.name.span, format!(": {what}"));
            }
            if h.class_method && matches!(kind, MethodKind::Constructor | MethodKind::Destructor) {
                return self.error(code::METHOD_IDENT_EXPECTED, h.name.span);
            }
            if f.is_virtual && kind == MethodKind::Constructor && !is_class {
                return self.error(code::VIRTUAL_CONSTRUCTOR, h.name.span);
            }
            if f.is_abstract && !f.is_virtual && !f.is_override {
                return self.error_with(code::VIRTUAL_EXPECTED, h.name.span, ": method abstract harus virtual");
            }
            if f.is_virtual && f.is_override {
                return self.error_with(code::DUPLICATE_IDENT, h.name.span, ": virtual dan override sekaligus");
            }
            let sig = self.method_signature(ty, class, kind, h.class_method, h)?;
            // Overloads declared together must all say so and differ.
            let earlier: Vec<Method> =
                own_methods.iter().filter(|(k, _)| *k == key).map(|(_, i)| methods[*i].clone()).collect();
            if !earlier.is_empty() {
                let clash = earlier.iter().any(|e| {
                    let esig = self.routine(e.routine).sig.clone();
                    self.same_user_signature(&esig, &sig, hidden_params(e.kind), hidden_params(kind))
                });
                if !f.overload || earlier.iter().any(|e| !e.overload) || clash {
                    return self.error_with(
                        code::DUPLICATE_IDENT,
                        h.name.span,
                        format!(
                            ": {} (method dengan nama sama harus ditandai overload dan berbeda parameter)",
                            h.name.name
                        ),
                    );
                }
            }
            let inherited: Vec<usize> = methods
                .iter()
                .enumerate()
                .filter(|(_, x)| !x.hidden && x.owner != ty && x.name.eq_ignore_ascii_case(&h.name.name))
                .map(|(i, _)| i)
                .collect();
            let matching = |s: &Self, i: usize| {
                let old = &methods[i];
                let old_sig = s.routine(old.routine).sig.clone();
                old.kind == kind
                    && old.class_method == h.class_method
                    && s.same_user_signature(&old_sig, &sig, hidden_params(old.kind), hidden_params(kind))
            };
            // Where the new entry goes: replacing an overridden method, or
            // appended.
            let mut replace = None;
            let slot = if f.is_override {
                let virtuals: Vec<usize> = inherited.iter().copied().filter(|&i| methods[i].slot.is_some()).collect();
                match virtuals.iter().copied().find(|&i| matching(self, i)) {
                    Some(i) => {
                        replace = Some(i);
                        methods[i].slot
                    }
                    None if !virtuals.is_empty() => {
                        return self.error_with(code::HEADER_MISMATCH, h.name.span, format!(": {}", h.name.name));
                    }
                    None => {
                        return self.error_with(
                            code::NO_VIRTUAL_TO_OVERRIDE,
                            h.name.span,
                            format!(": {}", h.name.name),
                        );
                    }
                }
            } else if !is_class && let Some(&i) = inherited.first() {
                // TP objects: redeclaring a virtual method overrides it.
                let old = methods[i].clone();
                if old.slot.is_some() {
                    if !f.is_virtual {
                        return self.error(code::VIRTUAL_EXPECTED, h.name.span);
                    }
                    let old_sig = self.routine(old.routine).sig.clone();
                    if old.kind != kind
                        || !self.same_user_signature(&old_sig, &sig, hidden_params(kind), hidden_params(kind))
                    {
                        return self.error_with(code::HEADER_MISMATCH, h.name.span, format!(": {}", h.name.name));
                    }
                }
                replace = Some(i);
                if old.slot.is_some() {
                    old.slot
                } else if f.is_virtual {
                    slots += 1;
                    Some(slots - 1)
                } else {
                    None
                }
            } else {
                // A class method that is not an override hides what it
                // shares a name with (only the same signature, for an
                // overload).
                let hides: Vec<usize> =
                    inherited.iter().copied().filter(|&i| !f.overload || matching(self, i)).collect();
                if !f.reintroduce && hides.iter().any(|&i| methods[i].slot.is_some()) {
                    self.warnings.push(Diagnostic::warning(
                        code::HIDES_VIRTUAL,
                        h.name.span,
                        format!("{}: {}; pakai override", code::message(code::HIDES_VIRTUAL), h.name.name),
                    ));
                }
                for i in hides {
                    methods[i].hidden = true;
                }
                if f.is_virtual {
                    slots += 1;
                    Some(slots - 1)
                } else {
                    None
                }
            };
            let suffix = if earlier.is_empty() { String::new() } else { format!("${}", earlier.len() + 1) };
            let symbol = format!("{}.{}.{}{}", self.unit_prefix(), object_key, key, suffix);
            let display = match self.cur_unit {
                Some(u) => format!("{}.{}.{}", self.unit_display(u), name.name, h.name.name),
                None => format!("{}.{}", name.name, h.name.name),
            };
            let id = self.new_routine(&symbol, &display, h.span);
            self.set_signature(id, sig);
            if !f.is_abstract {
                self.missing_methods.push((id, h.name.span, self.cur_unit));
            }
            let entry = Method {
                name: h.name.name.clone(),
                routine: id,
                kind,
                slot,
                vis: visibility(*vis),
                owner: ty,
                class_method: h.class_method,
                is_abstract: f.is_abstract,
                overload: f.overload,
                hidden: false,
            };
            let index = match replace {
                Some(i) => {
                    methods[i] = entry;
                    i
                }
                None => {
                    methods.push(entry);
                    methods.len() - 1
                }
            };
            own_methods.push((key, index));
        }
        let own_names: HashSet<String> = own_methods.iter().map(|(k, _)| k.clone()).collect();
        self.types.set(ty, Type::Object(Box::new(provisional(methods.clone(), properties.clone(), slots, None))));

        // Properties, once every accessor is known.
        for m in &obj.members {
            let ast::ObjectMember::Property { decl, vis } = m else { continue };
            let key = decl.name.key();
            if seen.contains(&key) || own_names.contains(&key) {
                return self.error_with(code::DUPLICATE_IDENT, decl.name.span, format!(": {}", decl.name.name));
            }
            seen.insert(key);
            let p = self.property(ty, decl, visibility(*vis))?;
            properties.push(p);
        }
        let vmt = match vmt_offset {
            Some(_) => {
                Some(self.vmt_global(&object_key, &name.name, class, parent, size, &methods, slots, name.span)?)
            }
            None => None,
        };
        self.types.set(ty, Type::Object(Box::new(provisional(methods, properties, slots, vmt))));
        Ok(())
    }

    /// Resolves the accessors of a property declared in object type `ty`.
    fn property(&mut self, ty: TypeId, decl: &ast::PropertyDecl, vis: Visibility) -> SResult<Property> {
        let pty = self.resolve_type(&decl.ty)?;
        let heading = ast::RoutineHeading {
            kind: ast::RoutineKind::Procedure,
            class_method: false,
            owner: None,
            name: decl.name.clone(),
            params: decl.params.clone(),
            result: None,
            directives: Vec::new(),
            span: decl.span,
            switches: self.sw,
        };
        let params = self.signature(&heading)?.params;
        if decl.default && params.is_empty() {
            return self.error_with(code::NOT_SUPPORTED, decl.span, ": default hanya untuk property larik");
        }
        if decl.read.is_none() && decl.write.is_none() {
            return self.error_with(code::PROPERTY_ACCESS, decl.name.span, ": tidak ada read maupun write");
        }
        let read = match &decl.read {
            Some(id) => Some(self.accessor(ty, id, &params, pty, false)?),
            None => None,
        };
        let write = match &decl.write {
            Some(id) => Some(self.accessor(ty, id, &params, pty, true)?),
            None => None,
        };
        Ok(Property {
            name: decl.name.name.clone(),
            ty: pty,
            params,
            read,
            write,
            default: decl.default,
            vis,
            owner: ty,
        })
    }

    /// The field, class variable or method a property reads (`write` false)
    /// or writes through.
    fn accessor(&self, ty: TypeId, id: &ast::Ident, params: &[Param], pty: TypeId, write: bool) -> SResult<Accessor> {
        let o = self.types.object(ty).expect("object type");
        let key = id.key();
        let bad = |detail: String| Err(Diagnostic::error_with(code::PROPERTY_ACCESS, id.span, detail));
        if let Some(f) = o.field(&key) {
            if !params.is_empty() || !self.same_param_type(f.ty, pty) {
                return bad(format!(": field {} tidak cocok dengan property", id.name));
            }
            return Ok(Accessor::Field { offset: f.offset, ty: f.ty });
        }
        if let Some(v) = o.class_var(&key) {
            if !params.is_empty() || !self.same_param_type(v.ty, pty) {
                return bad(format!(": {} tidak cocok dengan property", id.name));
            }
            return Ok(Accessor::ClassVar { global: v.global, ty: v.ty });
        }
        let found = o.methods_named(&key);
        if found.is_empty() {
            return self.error_with(code::UNKNOWN_IDENT, id.span, format!(": {}", id.name));
        }
        for m in found {
            let sig = &self.routine(m.routine).sig;
            let user = &sig.params[hidden_params(m.kind)..];
            let fits = if write {
                m.kind == MethodKind::Procedure
                    && user.len() == params.len() + 1
                    && user[params.len()].mode != ParamMode::Var
                    && self.same_param_type(user[params.len()].ty, pty)
            } else {
                m.kind == MethodKind::Function
                    && user.len() == params.len()
                    && sig.result.is_some_and(|r| self.same_param_type(r, pty))
            };
            let same_index = user.iter().zip(params).all(|(a, b)| a.mode == b.mode && self.same_param_type(a.ty, b.ty));
            if fits && same_index && !m.class_method {
                return Ok(Accessor::Method(Box::new(m)));
            }
        }
        let what = if write { "setter" } else { "getter" };
        bad(format!(": {what} {} tidak cocok dengan tipe atau indeks property", id.name))
    }

    fn method_signature(
        &mut self,
        obj: TypeId,
        class: Option<TypeId>,
        kind: MethodKind,
        class_method: bool,
        h: &ast::RoutineHeading,
    ) -> SResult<Signature> {
        let mut sig = self.signature(h)?;
        if kind == MethodKind::Function && sig.result.is_none() {
            return self.error(code::COLON_EXPECTED, h.span.end_point());
        }
        let self_ty = match class {
            Some(c) if class_method => self.class_ref_type(c),
            Some(c) => c,
            None => self.pointer_to(obj),
        };
        let mut params = vec![Param { name: "Self".into(), mode: ParamMode::Value, ty: self_ty }];
        if kind == MethodKind::Constructor {
            params.push(Param { name: "$vmt".into(), mode: ParamMode::Value, ty: self.types.builtin.pointer });
            sig.result = Some(self_ty);
        }
        params.append(&mut sig.params);
        sig.params = params;
        Ok(sig)
    }

    /// Same declared parameters and result (hidden parameters excluded).
    fn same_user_signature(&self, a: &Signature, b: &Signature, hidden_a: usize, hidden_b: usize) -> bool {
        let ctor = hidden_a == 2 && hidden_b == 2;
        let result = match (a.result, b.result) {
            (Some(x), Some(y)) => x == y || ctor || self.same_class(x, y),
            (None, None) => true,
            _ => false,
        };
        result
            && a.params.len() - hidden_a == b.params.len() - hidden_b
            && a.params
                .iter()
                .skip(hidden_a)
                .zip(b.params.iter().skip(hidden_b))
                .all(|(x, y)| x.mode == y.mode && (self.same_param_type(x.ty, y.ty) || self.same_class(x.ty, y.ty)))
    }

    /// Two class reference types of the same class.
    fn same_class(&self, a: TypeId, b: TypeId) -> bool {
        matches!((self.class_of_ref(a), self.class_of_ref(b)), (Some(x), Some(y)) if x == y)
    }

    /// The VMT of an object type: size, -size, parent VMT, code pointers
    /// (abstract methods report runtime error 211). A class VMT has the
    /// address of its name in slot 0.
    #[allow(clippy::too_many_arguments)]
    fn vmt_global(
        &mut self,
        object_key: &str,
        display: &str,
        class: Option<TypeId>,
        parent: Option<TypeId>,
        size: u64,
        methods: &[Method],
        slots: u32,
        span: Span,
    ) -> SResult<u32> {
        let count = VMT_HEADER as usize / 8 + slots as usize;
        let mut bytes = vec![0u8; count * 8];
        bytes[0..8].copy_from_slice(&(size as i64).to_le_bytes());
        bytes[8..16].copy_from_slice(&(-(size as i64)).to_le_bytes());
        let mut pointers = Vec::new();
        if let Some(pv) = parent.and_then(|p| self.types.object(p)).and_then(|o| o.vmt) {
            pointers.push((16, self.globals[pv as usize].symbol.clone()));
        }
        let mut abstract_symbol = None;
        for m in methods {
            if let Some(slot) = m.slot {
                let symbol = if m.is_abstract {
                    if abstract_symbol.is_none() {
                        let id = self.rtl("ODIN_ABSTRACTERROR", span)?;
                        abstract_symbol = Some(self.routine(id).symbol.clone());
                    }
                    abstract_symbol.clone().unwrap()
                } else {
                    self.routine(m.routine).symbol.clone()
                };
                pointers.push((VMT_HEADER + 8 * slot as u64, symbol));
            }
        }
        if class.is_some() {
            let mut text = vec![display.len().min(255) as u8];
            text.extend(display.bytes().take(255));
            let b = self.types.builtin;
            let name_ty =
                self.types.add(Type::Array { index: b.longint, lo: 0, hi: text.len() as i64 - 1, elem: b.char });
            self.globals.push(Global {
                symbol: format!("{}.{}.$NAME", self.unit_prefix(), object_key),
                name: "$NAME".into(),
                ty: name_ty,
                init: Some(GlobalInit { bytes: text, pointers: Vec::new() }),
                readonly: true,
                span,
            });
            let name_symbol = self.globals.last().unwrap().symbol.clone();
            pointers.push((VMT_HEADER, name_symbol));
        }
        let b = self.types.builtin;
        let ty = self.types.add(Type::Array { index: b.longint, lo: 0, hi: count as i64 - 1, elem: b.int64 });
        self.globals.push(Global {
            symbol: format!("{}.{}.$VMT", self.unit_prefix(), object_key),
            name: "$VMT".into(),
            ty,
            init: Some(GlobalInit { bytes, pointers }),
            readonly: true,
            span,
        });
        Ok(self.globals.len() as u32 - 1)
    }

    /// Address of the VMT of object type `ty`.
    pub(crate) fn vmt_address(&self, ty: TypeId, span: Span) -> SResult<Expr> {
        let ty = self.types.instance(ty).unwrap_or(ty);
        let Some(g) = self.types.object(ty).and_then(|o| o.vmt) else {
            return self.error(code::OBJECT_TYPE_EXPECTED, span);
        };
        let global = &self.globals[g as usize];
        let var = Expr::new(ExprKind::Var(Var::Global(GlobalId(g))), global.ty, span);
        Ok(Expr::new(ExprKind::AddrOf(Box::new(var)), self.types.builtin.pointer, span))
    }

    /// The VMT pointer stored in an object variable.
    pub(crate) fn vmt_of_instance(&self, instance: Expr, span: Span) -> SResult<Expr> {
        let Some(offset) = self.types.object(instance.ty).and_then(|o| o.vmt_offset) else {
            return self.error(code::OBJECT_TYPE_EXPECTED, span);
        };
        Ok(Expr::new(ExprKind::Field { base: Box::new(instance), offset }, self.types.builtin.pointer, span))
    }

    /// The instance a class reference points to (an lvalue).
    pub(crate) fn class_instance(&self, reference: Expr, span: Span) -> Expr {
        let instance = self.types.instance(reference.ty).expect("class type");
        Expr::new(ExprKind::Deref(Box::new(reference)), instance, span)
    }

    /// Methods still waiting for their body; reported at the end of the
    /// unit or program that declares their type.
    pub(crate) fn check_methods_implemented(&self) -> SResult<()> {
        if let Some((id, span, _)) = self.missing_methods.iter().find(|(_, _, m)| *m == self.cur_unit) {
            return self.error_with(code::UNDEFINED_FORWARD, *span, format!(": {}", self.routine(*id).display));
        }
        Ok(())
    }

    // ---- method bodies --------------------------------------------------------------

    /// `procedure TObj.Name(...); begin ... end;`
    pub(crate) fn method_decl(&mut self, r: &ast::Routine, owner: &ast::Ident) -> SResult<()> {
        let h = &r.heading;
        let ty = match self.lookup(&owner.key()) {
            Some(Sym::Type(t)) if self.types.object(t).is_some() => t,
            Some(Sym::Type(t)) if self.types.class_object(t).is_some() => self.types.instance(t).unwrap(),
            Some(_) => return self.error(code::OBJECT_TYPE_EXPECTED, owner.span),
            None => return self.error_with(code::UNKNOWN_IDENT, owner.span, format!(": {}", owner.name)),
        };
        let object = self.types.object(ty).cloned().expect("object type");
        let own: Vec<Method> = object
            .methods
            .iter()
            .filter(|m| m.owner == ty && m.name.eq_ignore_ascii_case(&h.name.name))
            .cloned()
            .collect();
        if own.is_empty() {
            return self.error_with(code::METHOD_IDENT_EXPECTED, h.name.span, format!(": {}", h.name.name));
        }
        let kind = method_kind(h.kind);
        let mismatch = || Diagnostic::error_with(code::HEADER_MISMATCH, h.name.span, format!(": {}", h.name.name));
        let method = if h.params.is_empty() && h.result.is_none() {
            // A heading without parameters names the only method of that
            // name, or the overload without parameters.
            let plain: Vec<&Method> =
                own.iter().filter(|m| self.routine(m.routine).sig.params.len() == hidden_params(m.kind)).collect();
            match (own.len(), plain.first()) {
                (1, _) => own[0].clone(),
                (_, Some(m)) => (*m).clone(),
                _ => return Err(mismatch()),
            }
        } else {
            let sig = self.method_signature(ty, object.class, kind, h.class_method, h)?;
            let found = own.iter().find(|m| {
                let declared = self.routine(m.routine).sig.clone();
                self.same_user_signature(&declared, &sig, hidden_params(m.kind), hidden_params(kind))
            });
            match found {
                Some(m) => m.clone(),
                None => return Err(mismatch()),
            }
        };
        if method.kind != kind || method.class_method != h.class_method {
            return Err(mismatch());
        }
        if method.is_abstract {
            return self.error_with(code::DUPLICATE_IDENT, h.name.span, format!(": {} (abstract)", h.name.name));
        }
        let Some(pos) = self.missing_methods.iter().position(|(id, _, _)| *id == method.routine) else {
            return self.error_with(code::DUPLICATE_IDENT, h.name.span, format!(": {}", h.name.name));
        };
        self.missing_methods.remove(pos);
        match &r.body {
            ast::RoutineBody::Block(block) => self.method_body(&method, ty, h, block),
            ast::RoutineBody::Inline(span) => self.error_with(code::DOS_ONLY, *span, ": inline(...)"),
            _ => self.error_with(code::NOT_SUPPORTED, h.span, ": metode external atau forward"),
        }
    }

    fn method_body(&mut self, method: &Method, ty: TypeId, h: &ast::RoutineHeading, block: &ast::Block) -> SResult<()> {
        let id = method.routine;
        let mut frame = Frame::new(id);
        frame.object = Some(ObjectScope { ty, method: method.clone(), allocated: None });
        self.frames.push(frame);
        let params = self.routine(id).sig.params.clone();
        let hidden = hidden_params(method.kind);
        let spans: Vec<Span> = if h.params.is_empty() {
            vec![h.name.span; params.len()]
        } else {
            h.params.iter().flat_map(|g| g.names.iter().map(|n| n.span)).collect()
        };
        for (i, p) in params.iter().enumerate().skip(hidden) {
            let span = spans.get(i - hidden).copied().unwrap_or(h.name.span);
            let ident = ast::Ident { name: p.name.clone(), span };
            self.declare(&ident, Sym::Var(Var::Local { routine: id, index: i as u32 }, p.ty))?;
        }
        let mut body = Vec::new();
        if method.kind == MethodKind::Constructor {
            body = self.constructor_prologue(id, ty, h.span)?;
        }
        self.decls(&block.decls)?;
        match &block.body {
            ast::Body::Statements(stmts, _) => body.extend(self.stmt_list(stmts)?),
            ast::Body::Asm(a) => return self.error_with(code::NOT_SUPPORTED, a.span, ": metode assembler"),
        }
        self.finish_frame()?;
        self.routine_mut(id).body = RoutineBody::Code(body);
        Ok(())
    }

    /// Allocates `Self` when it is nil (zeroed, for a class), stores the VMT
    /// (unless nil), and makes `Self` the result.
    fn constructor_prologue(&mut self, id: RoutineId, ty: TypeId, span: Span) -> SResult<Vec<Stmt>> {
        let b = self.types.builtin;
        let stmt = |kind| Stmt { kind, span };
        let self_ty = self.routine(id).sig.params[0].ty;
        let this = self.var_expr(Var::Local { routine: id, index: 0 }, self_ty, span);
        let vmt = self.var_expr(Var::Local { routine: id, index: 1 }, b.pointer, span);
        let allocated = self.add_temp(b.boolean);
        if let Some(scope) = self.frames.last_mut().and_then(|f| f.object.as_mut()) {
            scope.allocated = Some(allocated);
        }
        let flag = self.var_expr(allocated, b.boolean, span);
        let nil = Expr::new(ExprKind::Nil, b.nil, span);
        let is = |op, l: &Expr| {
            Expr::new(ExprKind::Binary(BinOp::Cmp(op), Box::new(l.clone()), Box::new(nil.clone())), b.boolean, span)
        };
        let int64_ptr = self.pointer_to(b.int64);
        let size_ptr = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(vmt.clone())), int64_ptr, span);
        let size = Expr::new(ExprKind::Deref(Box::new(size_ptr)), b.int64, span);
        let memory = self.rtl_call("ODIN_GETMEM", vec![size.clone()], span)?;
        let memory = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(memory)), self_ty, span);
        let object = Expr::new(ExprKind::Deref(Box::new(this.clone())), ty, span);
        let mut alloc = vec![
            stmt(StmtKind::Assign { target: this.clone(), value: memory }),
            stmt(StmtKind::Assign { target: flag.clone(), value: Expr::new(ExprKind::Int(1), b.boolean, span) }),
        ];
        if self.types.is_class_instance(ty) {
            let zero = Expr::new(ExprKind::Int(0), b.byte, span);
            let fill = self.rtl_call("ODIN_FILLCHAR", vec![object.clone(), size, zero], span)?;
            alloc.push(stmt(StmtKind::Call(fill)));
        }
        let mut out = vec![
            stmt(StmtKind::Assign { target: flag, value: Expr::new(ExprKind::Int(0), b.boolean, span) }),
            stmt(StmtKind::If { cond: is(Cond::Eq, &this), then: alloc, otherwise: vec![] }),
        ];
        if let Ok(slot) = self.vmt_of_instance(object, span) {
            out.push(stmt(StmtKind::If {
                cond: is(Cond::Ne, &vmt),
                then: vec![stmt(StmtKind::Assign { target: slot, value: vmt })],
                otherwise: vec![],
            }));
        }
        let index = self.routine(id).result_local().expect("constructor result");
        let result = self.var_expr(Var::Local { routine: id, index }, self_ty, span);
        out.push(stmt(StmtKind::Assign { target: result, value: this }));
        Ok(out)
    }

    /// `Fail`: frees `Self` if this constructor allocated it, returns nil.
    pub(crate) fn fail_stmt(&mut self, span: Span) -> SResult<Vec<Stmt>> {
        let b = self.types.builtin;
        let stmt = |kind| Stmt { kind, span };
        let Some(frame) = self.frames.last() else { return self.error(code::FAIL_OUTSIDE_CONSTRUCTOR, span) };
        let Some(ObjectScope { ty, allocated: Some(flag), .. }) = frame.object.clone() else {
            return self.error(code::FAIL_OUTSIDE_CONSTRUCTOR, span);
        };
        let id = frame.routine;
        let self_ty = self.routine(id).sig.params[0].ty;
        let this = self.var_expr(Var::Local { routine: id, index: 0 }, self_ty, span);
        let pointer = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(this)), b.pointer, span);
        let free = if self.types.is_class_instance(ty) {
            self.rtl_call("ODIN_FREEINSTANCE", vec![pointer], span)?
        } else {
            let size = Expr::new(ExprKind::Int(self.types.size(ty) as i64), b.int64, span);
            self.rtl_call("ODIN_FREEMEM", vec![pointer, size], span)?
        };
        let index = self.routine(id).result_local().expect("constructor result");
        let result = self.var_expr(Var::Local { routine: id, index }, self_ty, span);
        Ok(vec![
            stmt(StmtKind::If {
                cond: self.var_expr(flag, b.boolean, span),
                then: vec![stmt(StmtKind::Call(free))],
                otherwise: vec![],
            }),
            stmt(StmtKind::Assign { target: result, value: Expr::new(ExprKind::Nil, b.nil, span) }),
            stmt(StmtKind::Exit),
        ])
    }

    // ---- names inside methods ---------------------------------------------------------

    /// The innermost frame that is a method body.
    pub(crate) fn method_frame(&self) -> Option<(usize, ObjectScope)> {
        self.frames.iter().enumerate().rev().find_map(|(i, f)| f.object.clone().map(|o| (i, o)))
    }

    /// The `Self` parameter of the innermost method, as declared (a pointer
    /// for objects, the class or class reference for classes).
    fn self_param(&self, span: Span) -> Option<Expr> {
        let (i, _) = self.method_frame()?;
        let id = self.frames[i].routine;
        let self_ty = self.routine(id).sig.params[0].ty;
        Some(self.var_expr(Var::Local { routine: id, index: 0 }, self_ty, span))
    }

    /// The instance of the innermost method (not in a class method).
    pub(crate) fn self_expr(&self, span: Span) -> Option<Expr> {
        let (_, scope) = self.method_frame()?;
        if scope.method.class_method {
            return None;
        }
        let p = self.self_param(span)?;
        Some(Expr::new(ExprKind::Deref(Box::new(p)), scope.ty, span))
    }

    /// Whether a member of object type `owner` with visibility `vis` may be
    /// used here.
    fn member_visible(&self, owner: TypeId, vis: Visibility) -> bool {
        let same_unit = || self.types.object(owner).is_some_and(|o| o.module == self.cur_unit);
        let in_methods_of = |descendants: bool| {
            self.method_frame()
                .is_some_and(|(_, s)| if descendants { self.types.is_descendant(s.ty, owner) } else { s.ty == owner })
        };
        match vis {
            Visibility::Public => true,
            Visibility::Private => same_unit(),
            Visibility::StrictPrivate => in_methods_of(false),
            Visibility::Protected => same_unit() || in_methods_of(true),
            Visibility::StrictProtected => in_methods_of(true),
        }
    }

    /// Field, method or property `key` of `instance` (an object variable or
    /// class instance).
    pub(crate) fn object_member(&self, instance: Expr, key: &str, span: Span) -> SResult<Option<Resolved>> {
        let Some(o) = self.types.object(instance.ty) else { return Ok(None) };
        let is_class = o.class.is_some();
        if let Some(f) = o.field(key) {
            if let Some(v) = o.field_visibility(key)
                && !self.member_visible(v.owner, v.vis)
            {
                return Ok(None);
            }
            let (offset, ty) = (f.offset, f.ty);
            return Ok(Some(Resolved::Value(Expr::new(
                ExprKind::Field { base: Box::new(instance), offset },
                ty,
                span,
            ))));
        }
        let candidates: Vec<Method> =
            o.methods_named(key).into_iter().filter(|m| self.member_visible(m.owner, m.vis)).collect();
        if let Some(m) = candidates.first().cloned() {
            let object = instance.ty;
            return Ok(Some(Resolved::Method(Box::new(MethodRef {
                this: SelfArg::Instance(instance),
                object,
                method: m,
                candidates,
                dispatch: true,
                // A constructor called on an existing class instance runs
                // as a method: the VMT stays.
                vmt: if is_class { CtorVmt::Keep } else { CtorVmt::Of(object) },
            }))));
        }
        if let Some(p) = o.property(key) {
            if !self.member_visible(p.owner, p.vis) {
                return Ok(None);
            }
            let object = instance.ty;
            return Ok(Some(Resolved::Property(Box::new(PropRef {
                this: SelfArg::Instance(instance),
                object,
                prop: p.clone(),
            }))));
        }
        if let Some(v) = o.class_var(key) {
            if !self.member_visible(v.owner, v.vis) {
                return Ok(None);
            }
            return Ok(Some(Resolved::Value(self.var_expr(Var::Global(GlobalId(v.global)), v.ty, span))));
        }
        Ok(None)
    }

    /// The visibility that hides member `key` of a class, when it exists
    /// (objects keep TP's "unknown identifier").
    pub(crate) fn hidden_member(&self, ty: TypeId, key: &str) -> Option<&'static str> {
        let o = self.types.class_object(ty)?;
        let vis = if o.field(key).is_some() {
            o.field_visibility(key)?.vis
        } else if let Some(m) = o.methods_named(key).first() {
            m.vis
        } else if let Some(p) = o.property(key) {
            p.vis
        } else {
            o.class_var(key)?.vis
        };
        Some(match vis {
            Visibility::StrictPrivate => "strict private",
            Visibility::Private => "private",
            Visibility::StrictProtected => "strict protected",
            Visibility::Protected => "protected",
            Visibility::Public => return None,
        })
    }

    /// Member `key` of a class used without an instance: `TFoo.Create`,
    /// `TFoo.ClassName`, `C.Create` for a class reference `C`, or a name
    /// inside a class method. `this` is the class reference (`Vmt`), or a
    /// pointer to nothing (`Pointer(nil)`) for a class named statically.
    pub(crate) fn class_member(
        &mut self,
        class_ty: TypeId,
        this: Option<Expr>,
        key: &str,
        span: Span,
    ) -> SResult<Option<Resolved>> {
        let instance = self.types.instance(class_ty).expect("class type");
        let Some(o) = self.types.object(instance).cloned() else { return Ok(None) };
        let candidates: Vec<Method> =
            o.methods_named(key).into_iter().filter(|m| self.member_visible(m.owner, m.vis)).collect();
        if let Some(m) = candidates.first().cloned() {
            let reference = match &this {
                Some(v) => v.clone(),
                None => self.class_value(class_ty, span)?,
            };
            let nil = Expr::new(ExprKind::Nil, self.types.builtin.nil, span);
            let r = match m.kind {
                MethodKind::Constructor => MethodRef {
                    this: SelfArg::Pointer(nil),
                    object: instance,
                    method: m,
                    candidates,
                    dispatch: this.is_some(),
                    vmt: match this {
                        Some(v) => CtorVmt::Value(v),
                        None => CtorVmt::Of(instance),
                    },
                },
                _ if m.class_method => MethodRef {
                    this: SelfArg::Vmt(reference),
                    object: instance,
                    method: m,
                    candidates,
                    dispatch: this.is_some(),
                    vmt: CtorVmt::Keep,
                },
                // TParent.Method inside a method of a descendant: a static
                // call on Self.
                _ => match (self.method_frame(), self.self_expr(span)) {
                    (Some((_, scope)), Some(me)) if self.types.is_descendant(scope.ty, instance) => MethodRef {
                        this: SelfArg::Instance(me),
                        object: instance,
                        method: m,
                        candidates,
                        dispatch: false,
                        vmt: CtorVmt::Keep,
                    },
                    _ if this.is_some() => {
                        return self.error_with(code::CANNOT_ACCESS, span, format!(": {key} perlu instance"));
                    }
                    _ => return Ok(Some(Resolved::MethodName(m.routine, span))),
                },
            };
            return Ok(Some(Resolved::Method(Box::new(r))));
        }
        if let Some(v) = o.class_var(key) {
            if !self.member_visible(v.owner, v.vis) {
                return Ok(None);
            }
            return Ok(Some(Resolved::Value(self.var_expr(Var::Global(GlobalId(v.global)), v.ty, span))));
        }
        if o.field(key).is_some() || o.property(key).is_some() {
            return self.error_with(code::CANNOT_ACCESS, span, format!(": {key} perlu instance"));
        }
        Ok(None)
    }

    /// A name inside a method: `Self`, then the method's (and nested
    /// routines') own declarations, then the object's fields and methods.
    pub(crate) fn self_member(&mut self, key: &str, span: Span) -> SResult<Option<Resolved>> {
        let Some((i, scope)) = self.method_frame() else { return Ok(None) };
        if key == "SELF" {
            let p = self.self_param(span).expect("method frame");
            if self.types.object(scope.ty).is_some_and(|o| o.class.is_some()) {
                return Ok(Some(Resolved::Value(p)));
            }
            return Ok(self.self_expr(span).map(Resolved::Value));
        }
        if self.frames[i..].iter().any(|f| f.scope.contains(key)) {
            return Ok(None);
        }
        if scope.method.class_method {
            let class_ty = self.types.object(scope.ty).and_then(|o| o.class).expect("class method");
            let me = self.self_param(span);
            return self.class_member(class_ty, me, key, span);
        }
        let instance = self.self_expr(span).expect("method frame");
        self.object_member(instance, key, span)
    }

    /// `inherited Name`: the parent's method, called statically on `Self`.
    pub(crate) fn inherited_member(&self, name: &ast::Ident) -> SResult<Resolved> {
        let Some((_, scope)) = self.method_frame() else { return self.error(code::NO_INHERITED, name.span) };
        let Some(parent) = self.types.object(scope.ty).and_then(|o| o.parent) else {
            return self.error(code::NO_INHERITED, name.span);
        };
        let candidates = self.types.object(parent).map(|o| o.methods_named(&name.key())).unwrap_or_default();
        let candidates: Vec<Method> = candidates.into_iter().filter(|m| self.member_visible(m.owner, m.vis)).collect();
        let Some(m) = candidates.first().cloned() else {
            // `inherited Items[I]`: the parent's property.
            if let Some(p) = self.types.object(parent).and_then(|o| o.property(&name.key()))
                && self.member_visible(p.owner, p.vis)
                && let Some(me) = self.self_expr(name.span)
            {
                return Ok(Resolved::Property(Box::new(PropRef {
                    this: SelfArg::Instance(me),
                    object: parent,
                    prop: p.clone(),
                })));
            }
            return self.error_with(code::UNKNOWN_IDENT, name.span, format!(": {}", name.name));
        };
        let this = match self.self_expr(name.span) {
            Some(me) => SelfArg::Instance(me),
            None => SelfArg::Vmt(self.self_param(name.span).expect("method frame")),
        };
        Ok(Resolved::Method(Box::new(MethodRef {
            this,
            object: parent,
            method: m,
            candidates,
            dispatch: false,
            vmt: CtorVmt::Keep,
        })))
    }

    /// A bare `inherited;`: the parent's method of the same name and
    /// parameters, given this method's own arguments. Nothing when the
    /// parent has none (as in Delphi).
    pub(crate) fn inherited_same(&mut self, span: Span) -> SResult<Vec<Stmt>> {
        let Some((i, scope)) = self.method_frame() else { return self.error(code::NO_INHERITED, span) };
        let routine = self.frames[i].routine;
        let Some(parent) = self.types.object(scope.ty).and_then(|o| o.parent) else { return Ok(Vec::new()) };
        let sig = self.routine(routine).sig.clone();
        let hidden = hidden_params(scope.method.kind);
        let candidates = self.types.object(parent).map(|o| o.methods_named(&scope.method.name)).unwrap_or_default();
        let found = candidates.into_iter().find(|m| {
            let other = self.routine(m.routine).sig.clone();
            m.kind == scope.method.kind
                && m.class_method == scope.method.class_method
                && self.member_visible(m.owner, m.vis)
                && self.same_user_signature(&other, &sig, hidden_params(m.kind), hidden)
        });
        let Some(m) = found else { return Ok(Vec::new()) };
        if m.is_abstract {
            return Ok(Vec::new());
        }
        let values: Vec<Expr> = (hidden..sig.params.len())
            .map(|k| self.var_expr(Var::Local { routine, index: k as u32 }, sig.params[k].ty, span))
            .collect();
        let this = match self.self_expr(span) {
            Some(me) => SelfArg::Instance(me),
            None => SelfArg::Vmt(self.self_param(span).expect("method frame")),
        };
        let r = MethodRef {
            this,
            object: parent,
            method: m.clone(),
            candidates: vec![m],
            dispatch: false,
            vmt: CtorVmt::Keep,
        };
        let call = self.method_call_values(r, values, span, true)?;
        Ok(vec![Stmt { kind: StmtKind::Call(call), span }])
    }

    /// `TObj.Method`: inside a method of `TObj` or a descendant, a static
    /// call on `Self`; elsewhere only its address can be taken.
    pub(crate) fn qualified_method(&self, ty: TypeId, field: &ast::Ident, span: Span) -> SResult<Resolved> {
        let candidates = self.types.object(ty).map(|o| o.methods_named(&field.key())).unwrap_or_default();
        let Some(m) = candidates.first().cloned() else {
            return self.error_with(code::UNKNOWN_IDENT, field.span, format!(": {}", field.name));
        };
        match (self.method_frame(), self.self_expr(span)) {
            (Some((_, scope)), Some(this)) if self.types.is_descendant(scope.ty, ty) => {
                Ok(Resolved::Method(Box::new(MethodRef {
                    this: SelfArg::Instance(this),
                    object: ty,
                    method: m,
                    candidates,
                    dispatch: false,
                    vmt: CtorVmt::Keep,
                })))
            }
            _ => Ok(Resolved::MethodName(m.routine, span)),
        }
    }

    /// The function result of the method being analysed, when `key` is its
    /// name (`Area := 3.14` inside `TCircle.Area`).
    pub(crate) fn method_result(&self, key: &str, span: Span) -> Option<Expr> {
        let (i, scope) = self.method_frame()?;
        if !scope.method.name.eq_ignore_ascii_case(key) || self.frames[i + 1..].iter().any(|f| f.scope.contains(key)) {
            return None;
        }
        let id = self.frames[i].routine;
        let index = self.routine(id).result_local()?;
        let ty = self.routine(id).locals[index as usize].ty;
        if scope.method.kind != MethodKind::Function {
            return None;
        }
        Some(self.var_expr(Var::Local { routine: id, index }, ty, span))
    }

    // ---- overloads --------------------------------------------------------------------

    /// The type an argument would have, for choosing an overload; `None`
    /// when it cannot be told on its own (routine names, `[]`, failures).
    fn probe_type(&mut self, a: &ast::Expr) -> Option<TypeId> {
        if matches!(a.kind, ast::ExprKind::Set(_)) {
            return None;
        }
        if matches!(a.kind, ast::ExprKind::Name(_) | ast::ExprKind::Field { .. })
            && matches!(self.resolve(a), Ok(Resolved::Routine(..)) | Ok(Resolved::MethodName(..)))
        {
            return None;
        }
        let warnings = self.warnings.len();
        let ty = self.expr(a).ok().map(|e| e.ty);
        self.warnings.truncate(warnings);
        ty
    }

    /// How well an argument of type `arg` fits parameter `p`; `None` when
    /// it does not.
    fn fit(&self, arg: Option<TypeId>, p: &Param) -> Option<u32> {
        let Some(a) = arg else { return Some(50) };
        if p.ty == self.types.builtin.untyped {
            return Some(30);
        }
        if a == p.ty {
            return Some(100);
        }
        let (ac, pc) = (self.class(a), self.class(p.ty));
        if p.mode == ParamMode::Var {
            let same_ordinal = self.types.is_ordinal(a)
                && self.types.base(a) == self.types.base(p.ty)
                && self.types.size(a) == self.types.size(p.ty);
            return match (ac, pc) {
                _ if same_ordinal => Some(95),
                (Class::Str, Class::Str) => Some(90),
                _ if self.types.object(p.ty).is_some() && self.types.is_descendant(a, p.ty) => Some(90),
                _ => None,
            };
        }
        let int_size = |t: TypeId| self.types.size(self.types.base(t)).max(1);
        // (argument, parameter)
        Some(match (ac, pc) {
            (Class::Int, Class::Int) => {
                let (s, d) = (int_size(a), int_size(p.ty));
                if s == d && self.types.int_kind(a).signed == self.types.int_kind(p.ty).signed {
                    95
                } else if d >= s {
                    90 - 2 * d.trailing_zeros().saturating_sub(s.trailing_zeros())
                } else {
                    60
                }
            }
            (Class::Int, Class::Real) => 40,
            (Class::Real, Class::Real) => 85,
            (Class::Char, Class::Char) | (Class::Bool, Class::Bool) => 95,
            (Class::Enum(x), Class::Enum(y)) if x == y => 95,
            (Class::Str, Class::Str) => 90,
            (Class::Char, Class::Str) => 40,
            (Class::Nil, Class::Ptr | Class::Proc | Class::Obj | Class::Meta) => 80,
            (Class::Ptr, Class::Ptr) => match (self.types.get(p.ty), self.types.get(a)) {
                (Type::Pointer(None), _) | (_, Type::Pointer(None)) => 70,
                (Type::Pointer(Some(x)), Type::Pointer(Some(y))) if x == y => 95,
                (Type::Pointer(Some(x)), Type::Pointer(Some(y)))
                    if self.types.object(*x).is_some() && self.types.is_descendant(*y, *x) =>
                {
                    85
                }
                _ => return None,
            },
            (Class::Obj | Class::Meta, Class::Ptr) if p.ty == self.types.builtin.pointer => 60,
            (Class::Str, Class::Ptr) if p.ty == self.types.builtin.pchar => 40,
            (Class::Obj, Class::Obj) if self.types.is_descendant(a, p.ty) => 90 - self.class_distance(a, p.ty),
            (Class::Meta, Class::Meta) => {
                let (Some(x), Some(y)) = (self.class_of_ref(a), self.class_of_ref(p.ty)) else { return None };
                if !self.types.is_descendant(x, y) {
                    return None;
                }
                90 - self.class_distance(x, y)
            }
            (Class::Set, Class::Set) => 80,
            (Class::Proc, Class::Proc) if self.types.get(a) == self.types.get(p.ty) => 95,
            _ if self.types.get(a) == self.types.get(p.ty) => 95,
            _ => return None,
        })
    }

    /// Generations between a class and one of its ancestors.
    fn class_distance(&self, from: TypeId, to: TypeId) -> u32 {
        let target = self.types.instance(to).unwrap_or(to);
        let mut cur = self.types.instance(from).or(Some(from));
        let mut n = 0;
        while let Some(t) = cur {
            if t == target {
                return n.min(40);
            }
            n += 1;
            cur = self.types.object(t).and_then(|o| o.parent);
        }
        40
    }

    /// Picks the overload of `m` that fits `args` best.
    fn select_overload(&mut self, mut m: MethodRef, args: &[ast::Arg], span: Span) -> SResult<MethodRef> {
        if m.candidates.len() <= 1 {
            return Ok(m);
        }
        let types: Vec<Option<TypeId>> = args.iter().map(|a| self.probe_type(&a.value)).collect();
        let mut best: Option<(u32, Method)> = None;
        let mut tie = false;
        for c in &m.candidates {
            let sig = &self.routine(c.routine).sig;
            let user = &sig.params[hidden_params(c.kind)..];
            if user.len() != args.len() {
                continue;
            }
            let mut total = 0;
            let mut ok = true;
            for (p, t) in user.iter().zip(&types) {
                match self.fit(*t, p) {
                    Some(s) => total += s,
                    None => {
                        ok = false;
                        break;
                    }
                }
            }
            if !ok {
                continue;
            }
            match &best {
                Some((score, _)) if total < *score => {}
                Some((score, _)) if total == *score => tie = true,
                _ => {
                    best = Some((total, c.clone()));
                    tie = false;
                }
            }
        }
        match best {
            None => self.error_with(code::NO_MATCHING_OVERLOAD, span, format!(": {}", m.method.name)),
            Some(_) if tie => self.error_with(code::AMBIGUOUS_OVERLOAD, span, format!(": {}", m.method.name)),
            Some((_, c)) => {
                m.method = c;
                Ok(m)
            }
        }
    }

    // ---- calls ------------------------------------------------------------------------

    /// The call itself. A constructor call has the type of its `Self` (nil
    /// after `Fail`).
    pub(crate) fn method_call(
        &mut self,
        m: MethodRef,
        args: &[ast::Arg],
        span: Span,
        statement: bool,
    ) -> SResult<Expr> {
        let m = self.select_overload(m, args, span)?;
        let sig = self.routine(m.method.routine).sig.clone();
        let hidden = hidden_params(m.method.kind);
        let declared = Signature { params: sig.params[hidden..].to_vec(), result: sig.result };
        let values = self.arguments(&declared, args, span)?;
        self.method_call_values(m, values, span, statement)
    }

    /// A method call with its declared arguments already analysed.
    pub(crate) fn method_call_values(
        &mut self,
        m: MethodRef,
        user_args: Vec<Expr>,
        span: Span,
        statement: bool,
    ) -> SResult<Expr> {
        let b = self.types.builtin;
        let rid = m.method.routine;
        let sig = self.routine(rid).sig.clone();
        let self_ty = sig.params[0].ty;
        let this = match m.this {
            SelfArg::Instance(x) if m.method.class_method => {
                if !x.is_lvalue() {
                    return self.error(code::VAR_IDENT_EXPECTED, x.span);
                }
                let vmt = self.vmt_of_instance(x, span)?;
                Expr::new(ExprKind::Convert(Conv::Bits, Box::new(vmt)), self_ty, span)
            }
            SelfArg::Instance(x) => {
                if !x.is_lvalue() {
                    return self.error(code::VAR_IDENT_EXPECTED, x.span);
                }
                Expr::new(ExprKind::AddrOf(Box::new(x)), self_ty, span)
            }
            SelfArg::Pointer(p) => Expr::new(ExprKind::Convert(Conv::Bits, Box::new(p)), self_ty, span),
            SelfArg::Vmt(v) => Expr::new(ExprKind::Convert(Conv::Bits, Box::new(v)), self_ty, span),
        };
        let mut values = vec![this];
        let mut runtime_vmt = false;
        // A class constructor gives an instance of the class it creates,
        // not of the class that declared it.
        let created = match &m.vmt {
            _ if m.method.kind != MethodKind::Constructor => None,
            CtorVmt::Value(v) => self.class_of_ref(v.ty),
            _ => self.types.object(m.object).and_then(|o| o.class),
        };
        if m.method.kind == MethodKind::Constructor {
            values.push(match m.vmt {
                CtorVmt::Of(t) => self.vmt_address(t, span)?,
                CtorVmt::Keep => Expr::new(ExprKind::Nil, b.pointer, span),
                CtorVmt::Value(v) => {
                    runtime_vmt = true;
                    Expr::new(ExprKind::Convert(Conv::Bits, Box::new(v)), b.pointer, span)
                }
            });
        }
        values.extend(user_args);
        let callee = match m.method.slot {
            Some(slot) if m.dispatch && m.method.class_method => Callee::VirtualClass { routine: rid, arg: 0, slot },
            Some(slot) if m.dispatch && m.method.kind == MethodKind::Constructor => {
                if runtime_vmt {
                    Callee::VirtualClass { routine: rid, arg: 1, slot }
                } else {
                    Callee::Routine(rid)
                }
            }
            Some(slot) if m.dispatch => {
                let vmt_offset = self.types.object(m.object).and_then(|o| o.vmt_offset).expect("virtual needs a VMT");
                Callee::Virtual { routine: rid, vmt_offset, slot, check: self.sw.get(Switches::RANGE) }
            }
            _ if m.method.is_abstract => {
                return self.error_with(code::ABSTRACT_CALL, span, format!(": {}", m.method.name));
            }
            _ => Callee::Routine(rid),
        };
        let ty = match sig.result {
            Some(_) if created.is_some() => created.unwrap(),
            Some(t) => t,
            None if statement => b.untyped,
            None => return self.error_with(code::NO_VALUE, span, format!(": {}", self.routine(rid).display)),
        };
        Ok(Expr::new(ExprKind::Call { callee, args: values }, ty, span))
    }

    /// A method call used as a value: an object constructor gives TRUE
    /// unless it failed; a class constructor gives the new instance.
    pub(crate) fn method_value(&mut self, m: MethodRef, args: &[ast::Arg], span: Span) -> SResult<Expr> {
        let ctor = m.method.kind == MethodKind::Constructor && !self.types.is_class_instance(m.object);
        let call = self.method_call(m, args, span, false)?;
        if !ctor {
            return Ok(call);
        }
        let b = self.types.builtin;
        let nil = Expr::new(ExprKind::Nil, b.nil, span);
        Ok(Expr::new(ExprKind::Binary(BinOp::Cmp(Cond::Ne), Box::new(call), Box::new(nil)), b.boolean, span))
    }

    /// A method call statement. Destroying a class instance (any destructor
    /// call but `inherited`) also frees its memory.
    pub(crate) fn method_stmt(&mut self, m: MethodRef, args: &[ast::Arg], span: Span) -> SResult<Vec<Stmt>> {
        let destroy = m.method.kind == MethodKind::Destructor && m.dispatch && self.types.is_class_instance(m.object);
        if !destroy {
            let call = self.method_call(m, args, span, true)?;
            return Ok(vec![Stmt { kind: StmtKind::Call(call), span }]);
        }
        let SelfArg::Instance(instance) = m.this.clone() else {
            let call = self.method_call(m, args, span, true)?;
            return Ok(vec![Stmt { kind: StmtKind::Call(call), span }]);
        };
        // The instance's address, kept in a temporary unless it is a plain
        // variable (it is needed twice).
        let class_ty = self.types.object(m.object).and_then(|o| o.class).expect("class");
        let mut out = Vec::new();
        let reference = match instance.kind {
            ExprKind::Deref(p) if matches!(p.kind, ExprKind::Var(_)) => *p,
            _ => {
                let temp = self.add_temp(class_ty);
                let target = self.var_expr(temp, class_ty, span);
                let value = Expr::new(ExprKind::AddrOf(Box::new(instance)), class_ty, span);
                out.push(Stmt { kind: StmtKind::Assign { target: target.clone(), value }, span });
                target
            }
        };
        let this = self.class_instance(reference.clone(), span);
        let call = self.method_call(MethodRef { this: SelfArg::Instance(this), ..m }, args, span, true)?;
        out.push(Stmt { kind: StmtKind::Call(call), span });
        let pointer = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(reference)), self.types.builtin.pointer, span);
        let free = self.rtl_call("ODIN_FREEINSTANCE", vec![pointer], span)?;
        out.push(Stmt { kind: StmtKind::Call(free), span });
        Ok(vec![Stmt { kind: StmtKind::Block(out), span }])
    }

    /// `Ctor(args)` (or a bare name) as the second argument of New/Dispose:
    /// the method of `object` it names, and its arguments.
    pub(crate) fn extended_method<'e>(
        &self,
        object: TypeId,
        e: &'e ast::Expr,
        want: MethodKind,
    ) -> SResult<(Method, Vec<Method>, &'e [ast::Arg])> {
        let (name, args): (&ast::Ident, &[ast::Arg]) = match &e.kind {
            ast::ExprKind::Name(n) => (n, &[]),
            ast::ExprKind::Call { callee, args } => match &callee.kind {
                ast::ExprKind::Name(n) => (n, args),
                _ => return self.error(code::METHOD_IDENT_EXPECTED, callee.span),
            },
            _ => return self.error(code::METHOD_IDENT_EXPECTED, e.span),
        };
        let found = self.types.object(object).map(|o| o.methods_named(&name.key())).unwrap_or_default();
        match found.first() {
            Some(m) if m.kind == want => Ok((m.clone(), found.clone(), args)),
            _ if want == MethodKind::Constructor => self.error(code::CONSTRUCTOR_EXPECTED, name.span),
            _ => self.error(code::DESTRUCTOR_EXPECTED, name.span),
        }
    }

    /// `New(P, Init(...))` / `New(PType, Init(...))`: the constructor
    /// called with `Self = nil` allocates the object.
    pub(crate) fn new_object(&mut self, pointer_ty: TypeId, ctor: &ast::Expr, span: Span) -> SResult<Expr> {
        let Type::Pointer(Some(object)) = self.types.get(pointer_ty).clone() else {
            return self.error(code::POINTER_VAR_EXPECTED, span);
        };
        if self.types.object(object).is_none() {
            return self.error(code::OBJECT_TYPE_EXPECTED, span);
        }
        let (method, candidates, args) = self.extended_method(object, ctor, MethodKind::Constructor)?;
        let nil = Expr::new(ExprKind::Nil, self.types.builtin.nil, span);
        let m = MethodRef {
            this: SelfArg::Pointer(nil),
            object,
            method,
            candidates,
            dispatch: false,
            vmt: CtorVmt::Of(object),
        };
        let call = self.method_call(m, args, span, false)?;
        Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(call)), pointer_ty, span))
    }

    /// `Dispose(P, Done(...))`: the destructor (virtual when declared so),
    /// then the memory.
    pub(crate) fn dispose_object(&mut self, p: Expr, dtor: &ast::Expr, span: Span) -> SResult<Vec<Stmt>> {
        let b = self.types.builtin;
        let Type::Pointer(Some(object)) = self.types.get(p.ty).clone() else {
            return self.error(code::POINTER_VAR_EXPECTED, span);
        };
        if self.types.object(object).is_none() {
            return self.error(code::OBJECT_TYPE_EXPECTED, span);
        }
        let (method, candidates, args) = self.extended_method(object, dtor, MethodKind::Destructor)?;
        let instance = Expr::new(ExprKind::Deref(Box::new(p.clone())), object, span);
        let m = MethodRef {
            this: SelfArg::Instance(instance),
            object,
            method,
            candidates,
            dispatch: true,
            vmt: CtorVmt::Keep,
        };
        let call = self.method_call(m, args, span, true)?;
        let size = Expr::new(ExprKind::Int(self.types.size(object) as i64), b.int64, span);
        let pointer = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(p)), b.pointer, span);
        let free = self.rtl_call("ODIN_FREEMEM", vec![pointer, size], span)?;
        Ok(vec![Stmt { kind: StmtKind::Call(call), span }, Stmt { kind: StmtKind::Call(free), span }])
    }

    // ---- properties -------------------------------------------------------------------

    /// Reads property `p`; `index` holds the indices of an array property.
    pub(crate) fn property_read(&mut self, p: PropRef, index: &[ast::Arg], span: Span) -> SResult<Expr> {
        if index.len() != p.prop.params.len() {
            return self.error_with(
                code::WRONG_ARG_COUNT,
                span,
                format!(": property {} memerlukan {} indeks", p.prop.name, p.prop.params.len()),
            );
        }
        match p.prop.read.clone() {
            None => {
                self.error_with(code::PROPERTY_ACCESS, span, format!(": property {} tidak bisa dibaca", p.prop.name))
            }
            Some(Accessor::Field { offset, ty }) => {
                let SelfArg::Instance(x) = p.this else { unreachable!("property of an instance") };
                Ok(Expr::new(ExprKind::Field { base: Box::new(x), offset }, ty, span))
            }
            Some(Accessor::ClassVar { global, ty }) => Ok(self.var_expr(Var::Global(GlobalId(global)), ty, span)),
            Some(Accessor::Method(m)) => {
                let r = MethodRef {
                    this: p.this,
                    object: p.object,
                    method: (*m).clone(),
                    candidates: vec![*m],
                    dispatch: true,
                    vmt: CtorVmt::Keep,
                };
                let mut call = self.method_call(r, index, span, false)?;
                call.ty = p.prop.ty;
                Ok(call)
            }
        }
    }

    /// `Obj.Prop := value` (or `Obj.Items[I] := value`).
    pub(crate) fn property_write(
        &mut self,
        p: PropRef,
        index: &[ast::Arg],
        value: &ast::Expr,
        span: Span,
    ) -> SResult<Vec<Stmt>> {
        if index.len() != p.prop.params.len() {
            return self.error_with(
                code::WRONG_ARG_COUNT,
                span,
                format!(": property {} memerlukan {} indeks", p.prop.name, p.prop.params.len()),
            );
        }
        let assign = |s: &mut Self, target: Expr| -> SResult<Vec<Stmt>> {
            let v = s.expr_expect(value, Some(target.ty))?;
            let v = s.coerce(v, target.ty, value.span)?;
            Ok(vec![Stmt { kind: StmtKind::Assign { target, value: v }, span }])
        };
        match p.prop.write.clone() {
            None => {
                self.error_with(code::PROPERTY_ACCESS, span, format!(": property {} hanya bisa dibaca", p.prop.name))
            }
            Some(Accessor::Field { offset, ty }) => {
                let SelfArg::Instance(x) = p.this else { unreachable!("property of an instance") };
                assign(self, Expr::new(ExprKind::Field { base: Box::new(x), offset }, ty, span))
            }
            Some(Accessor::ClassVar { global, ty }) => {
                assign(self, self.var_expr(Var::Global(GlobalId(global)), ty, span))
            }
            Some(Accessor::Method(m)) => {
                let mut args = index.to_vec();
                args.push(ast::Arg { value: value.clone(), width: None, decimals: None });
                let r = MethodRef {
                    this: p.this,
                    object: p.object,
                    method: (*m).clone(),
                    candidates: vec![*m],
                    dispatch: true,
                    vmt: CtorVmt::Keep,
                };
                let call = self.method_call(r, &args, span, true)?;
                Ok(vec![Stmt { kind: StmtKind::Call(call), span }])
            }
        }
    }

    /// The default array property of a class instance or object, if any.
    pub(crate) fn default_property(&self, base: &Expr, span: Span) -> Option<PropRef> {
        let (instance, object) = match self.types.get(base.ty) {
            Type::Class(i) => (self.class_instance(base.clone(), span), *i),
            Type::Object(_) if base.is_lvalue() => (base.clone(), base.ty),
            _ => return None,
        };
        let p = self.types.object(object)?.default_property()?.clone();
        if !self.member_visible(p.owner, p.vis) {
            return None;
        }
        Some(PropRef { this: SelfArg::Instance(instance), object, prop: p })
    }

    // ---- is / as ----------------------------------------------------------------------

    /// `Obj is TFoo` and `Obj as TFoo`: run-time class tests against a class
    /// type or class reference on the right.
    pub(crate) fn class_test(&mut self, op: ast::BinOp, l: Expr, r: Expr, span: Span) -> SResult<Expr> {
        let b = self.types.builtin;
        let left_class = match self.types.get(l.ty) {
            Type::Class(_) => l.ty,
            Type::Nil => r.ty,
            _ => return self.error_with(code::OPERAND_TYPES, l.span, ": operand kiri harus instance class"),
        };
        let Some(right_class) = self.class_of_ref(r.ty) else {
            return self.error_with(code::CLASS_TYPE_EXPECTED, r.span, "");
        };
        if left_class != r.ty
            && !self.types.is_descendant(right_class, left_class)
            && !self.types.is_descendant(left_class, right_class)
        {
            return self.error_with(
                code::TYPE_MISMATCH,
                span,
                format!(": {} dan {}", self.types.display(left_class), self.types.display(right_class)),
            );
        }
        let object = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(l)), b.pointer, span);
        let vmt = Expr::new(ExprKind::Convert(Conv::Bits, Box::new(r)), b.pointer, span);
        if op == ast::BinOp::Is {
            return self.rtl_call("ODIN_IS", vec![object, vmt], span);
        }
        let checked = self.rtl_call("ODIN_AS", vec![object, vmt], span)?;
        Ok(Expr::new(ExprKind::Convert(Conv::Bits, Box::new(checked)), right_class, span))
    }
}
