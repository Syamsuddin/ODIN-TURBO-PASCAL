// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 Syams Ideris
//! `odinpc debug --exe EXE [--odbg FILE] --ide-fds R,W [--cwd DIR] -- ARGS...`
//!
//! Runs a `--debug` build in the current terminal (the IDE's user screen),
//! reads JSON-line commands from fd R and writes JSON-line events to fd W.
//! The program connects back over a Unix socket; breakpoints and pause
//! requests go through a shared file the program maps.

use std::collections::{HashMap, VecDeque};
use std::fs::File;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::fd::FromRawFd;
use std::os::unix::fs::FileExt;
use std::os::unix::net::{UnixListener, UnixStream};
use std::os::unix::process::ExitStatusExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::{Duration, Instant};

use odin_base::json::{self, Value};
use odin_debuginfo::DebugInfo;

use crate::eval::{EResult, Evaluator, Frame, Memory};

// Frames from the program (rtl/system/debug.inc).
const HELLO: u8 = 1;
const STOP: u8 = 2;
const RTERR: u8 = 3;
const EXIT: u8 = 4;
const DATA: u8 = 5;
const ACK: u8 = 6;
// Frames to the program.
const RESUME: u8 = 1;
const READ: u8 = 2;
const WRITE: u8 = 3;
// Resume modes.
const RUN: u8 = 0;
const INTO: u8 = 1;
const OVER: u8 = 2;
const OUT: u8 = 3;
/// Bytes per READ/WRITE frame.
const CHUNK: usize = 4096;
/// Entries of the program's shadow stack (`ODIN_DBG_STACK`).
const STACK_SIZE: u32 = 4096;

unsafe extern "C" {
    fn signal(sig: i32, handler: usize) -> usize;
    fn fcntl(fd: i32, cmd: i32, ...) -> i32;
}

enum Event {
    Ide(Value),
    IdeClosed,
    Frame(u8, Vec<u8>),
    ProgramClosed,
}

/// The program's memory, reached through READ/WRITE frames while it is
/// stopped. IDE commands that arrive meanwhile wait in `pending`.
struct Link<'s> {
    stream: &'s mut UnixStream,
    rx: &'s Receiver<Event>,
    pending: &'s mut VecDeque<Value>,
    ide_closed: &'s mut bool,
}

impl Link<'_> {
    fn send(&mut self, kind: u8, payload: &[u8]) -> EResult<()> {
        let mut frame = vec![kind];
        frame.extend((payload.len() as u32).to_le_bytes());
        frame.extend(payload);
        self.stream.write_all(&frame).map_err(|_| "Program sudah berhenti".to_string())
    }

    fn wait(&mut self, kind: u8) -> EResult<Vec<u8>> {
        loop {
            match self.rx.recv() {
                Ok(Event::Frame(k, payload)) if k == kind => return Ok(payload),
                Ok(Event::Frame(..)) => {}
                Ok(Event::Ide(v)) => self.pending.push_back(v),
                Ok(Event::IdeClosed) => *self.ide_closed = true,
                Ok(Event::ProgramClosed) | Err(_) => return Err("Program sudah berhenti".into()),
            }
        }
    }
}

impl Memory for Link<'_> {
    fn read(&mut self, addr: u64, len: usize) -> EResult<Vec<u8>> {
        let mut out = Vec::with_capacity(len);
        while out.len() < len {
            let n = (len - out.len()).min(CHUNK);
            let mut p = (addr + out.len() as u64).to_le_bytes().to_vec();
            p.extend((n as u32).to_le_bytes());
            self.send(READ, &p)?;
            let data = self.wait(DATA)?;
            if data.first() != Some(&0) || data.len() != n + 1 {
                return Err(format!("Memori di ${:X} tidak bisa dibaca", addr + out.len() as u64));
            }
            out.extend(&data[1..]);
        }
        Ok(out)
    }

    fn write(&mut self, addr: u64, bytes: &[u8]) -> EResult<()> {
        for (i, part) in bytes.chunks(CHUNK).enumerate() {
            let at = addr + (i * CHUNK) as u64;
            let mut p = at.to_le_bytes().to_vec();
            p.extend(part);
            self.send(WRITE, &p)?;
            if self.wait(ACK)?.first() != Some(&0) {
                return Err(format!("Memori di ${at:X} tidak bisa ditulis"));
            }
        }
        Ok(())
    }
}

#[derive(Clone, Copy)]
struct Stop {
    line: u32,
    depth: u32,
}

/// Where a step started: a step that lands on the same line at the same
/// depth keeps going, so one source line is one step.
struct StepOrigin {
    mode: u8,
    target: u32,
    line: (u32, u32),
    depth: u32,
}

struct FrameRow {
    routine: u32,
    fp: u64,
    line: u32,
}

struct Session {
    info: DebugInfo,
    slide: i64,
    stack: u64,
    stream: UnixStream,
    rx: Receiver<Event>,
    pending: VecDeque<Value>,
    ide_closed: bool,
    out: File,
    shm: File,
    child: Child,
    /// `(file, line)` -> line ids.
    ids: HashMap<(u32, u32), Vec<u32>>,
    flags: Vec<u8>,
    /// Breakpoint lines per file (after moving to lines with code).
    breakpoints: HashMap<u32, Vec<u32>>,
    /// Ids set only for Go to cursor.
    temporary: Vec<u32>,
    stop: Option<Stop>,
    step: Option<StepOrigin>,
    frames: Option<Vec<FrameRow>>,
    exit_code: Option<i32>,
}

fn obj(pairs: Vec<(&str, Value)>) -> Value {
    Value::Object(pairs.into_iter().map(|(k, v)| (k.to_string(), v)).collect())
}

fn text(s: &str) -> Value {
    Value::Str(s.to_string())
}

fn int(n: i64) -> Value {
    Value::Int(n)
}

fn same_file(a: &str, b: &str) -> bool {
    let canon = |p: &str| std::fs::canonicalize(p).unwrap_or_else(|_| PathBuf::from(p));
    a == b || canon(a) == canon(b)
}

impl Session {
    fn emit(&mut self, event: &str, mut fields: Vec<(&str, Value)>) {
        fields.push(("event", text(event)));
        let line = obj(fields).to_json() + "\n";
        let _ = self.out.write_all(line.as_bytes());
        let _ = self.out.flush();
    }

    fn link(&mut self) -> Link<'_> {
        Link { stream: &mut self.stream, rx: &self.rx, pending: &mut self.pending, ide_closed: &mut self.ide_closed }
    }

    fn resume(&mut self, mode: u8, target: u32) {
        let mut p = vec![mode];
        p.extend(target.to_le_bytes());
        let _ = self.link().send(RESUME, &p);
        self.stop = None;
        self.frames = None;
    }

    fn file_index(&self, path: &str) -> Option<u32> {
        self.info.files.iter().position(|f| same_file(f, path)).map(|i| i as u32)
    }

    fn set_flag(&mut self, id: u32, on: bool) {
        let v = on as u8;
        if self.flags[id as usize] != v {
            self.flags[id as usize] = v;
            let _ = self.shm.write_at(&[v], 16 + id as u64);
        }
    }

    /// The first line at or after `line` with a statement, if any.
    fn code_line(&self, file: u32, line: u32) -> Option<u32> {
        self.ids.keys().filter(|&&(f, l)| f == file && l >= line).map(|&(_, l)| l).min()
    }

    fn set_breakpoints(&mut self, request: i64, path: &str, lines: &[u32]) {
        let file = self.file_index(path);
        let (mut verified, mut moved, mut rejected) = (Vec::new(), Vec::new(), Vec::new());
        if let Some(f) = file {
            for line in self.breakpoints.remove(&f).unwrap_or_default() {
                for id in self.ids[&(f, line)].clone() {
                    self.set_flag(id, false);
                }
            }
            let mut set = Vec::new();
            for &line in lines {
                match self.code_line(f, line) {
                    Some(l) => {
                        if l != line {
                            moved.push(Value::Array(vec![int(line as i64), int(l as i64)]));
                        }
                        verified.push(int(l as i64));
                        set.push(l);
                        for id in self.ids[&(f, l)].clone() {
                            self.set_flag(id, true);
                        }
                    }
                    None => rejected.push(int(line as i64)),
                }
            }
            self.breakpoints.insert(f, set);
        } else {
            rejected.extend(lines.iter().map(|&l| int(l as i64)));
        }
        self.emit(
            "breakpoints",
            vec![
                ("id", int(request)),
                ("file", text(path)),
                ("verified", Value::Array(verified)),
                ("moved", Value::Array(moved)),
                ("rejected", Value::Array(rejected)),
            ],
        );
    }

    fn is_breakpoint(&self, id: u32) -> bool {
        let (f, l) = self.info.lines[id as usize];
        self.breakpoints.get(&f).is_some_and(|ls| ls.contains(&l))
    }

    fn run_to(&mut self, path: &str, line: u32) -> bool {
        let Some(f) = self.file_index(path) else { return false };
        let Some(l) = self.code_line(f, line) else { return false };
        for id in self.ids[&(f, l)].clone() {
            if self.flags[id as usize] == 0 {
                self.set_flag(id, true);
                self.temporary.push(id);
            }
        }
        self.resume(RUN, 0);
        true
    }

    fn on_stop(&mut self, payload: &[u8]) {
        let id = u32::from_le_bytes(payload[0..4].try_into().unwrap());
        let depth = u32::from_le_bytes(payload[4..8].try_into().unwrap());
        let reason = payload[8];
        for t in std::mem::take(&mut self.temporary) {
            if !self.is_breakpoint(t) {
                self.set_flag(t, false);
            }
        }
        let line = self.info.lines.get(id as usize).copied().unwrap_or((0, 0));
        if reason == 3
            && let Some(origin) = &self.step
            && origin.line == line
            && origin.depth == depth
        {
            let (mode, target) = (origin.mode, origin.target);
            self.resume(mode, target);
            return;
        }
        self.step = None;
        self.stop = Some(Stop { line: id, depth });
        self.frames = None;
        let reason = match reason {
            1 => "pause",
            2 => "breakpoint",
            3 => "step",
            _ => "entry",
        };
        let path = self.info.files.get(line.0 as usize).cloned().unwrap_or_default();
        self.emit(
            "stopped",
            vec![
                ("reason", text(reason)),
                ("file", text(&path)),
                ("line", int(line.1 as i64)),
                ("depth", int(depth as i64)),
            ],
        );
    }

    fn step(&mut self, mode: u8) {
        let Some(stop) = self.stop else {
            self.resume(INTO, 0);
            return;
        };
        let line = self.info.lines[stop.line as usize];
        let target = stop.depth;
        self.step = Some(StepOrigin { mode, target, line, depth: stop.depth });
        self.resume(mode, target);
    }

    /// The call stack, innermost first, read from the program's shadow stack.
    fn frames(&mut self) -> EResult<()> {
        if self.frames.is_some() {
            return Ok(());
        }
        let Some(stop) = self.stop else { return Err("Program sedang berjalan".into()) };
        let n = stop.depth.min(STACK_SIZE - 1);
        let stack = self.stack;
        let bytes = if n > 0 { self.link().read(stack + 16, n as usize * 16)? } else { Vec::new() };
        let entry = |k: u32| -> (u32, u32, u64) {
            let b = &bytes[(k as usize - 1) * 16..k as usize * 16];
            (
                u32::from_le_bytes(b[0..4].try_into().unwrap()),
                u32::from_le_bytes(b[4..8].try_into().unwrap()),
                u64::from_le_bytes(b[8..16].try_into().unwrap()),
            )
        };
        let mut rows = Vec::new();
        for k in (1..=n).rev() {
            let (_, routine, fp) = entry(k);
            let line = if k == stop.depth { stop.line } else { entry(k + 1).0 };
            rows.push(FrameRow { routine, fp, line });
        }
        self.frames = Some(rows);
        Ok(())
    }

    fn frame(&mut self, index: usize) -> EResult<Option<Frame>> {
        self.frames()?;
        let rows = self.frames.as_ref().unwrap();
        Ok(rows.get(index).map(|r| Frame { routine: r.routine, fp: r.fp }))
    }

    fn with_evaluator<T>(&mut self, frame: usize, f: impl FnOnce(&mut Evaluator<Link>) -> EResult<T>) -> EResult<T> {
        let frame = self.frame(frame)?;
        let info = std::mem::take(&mut self.info);
        let slide = self.slide;
        let result = {
            let mut link = self.link();
            let mut e = Evaluator { info: &info, slide, frame, mem: &mut link };
            f(&mut e)
        };
        self.info = info;
        result
    }

    fn stack_rows(&mut self) -> EResult<Value> {
        self.frames()?;
        let count = self.frames.as_ref().unwrap().len();
        let mut out = Vec::new();
        for i in 0..count {
            let (routine, line) = {
                let r = &self.frames.as_ref().unwrap()[i];
                (r.routine, r.line)
            };
            let params = self.with_evaluator(i, |e| e.locals()).unwrap_or_default();
            let info = &self.info.routines[routine as usize];
            // Declared parameters only: not Self, not the constructor's VMT.
            let declared: Vec<&str> = info
                .locals
                .iter()
                .filter(|l| l.kind == odin_debuginfo::LocalKind::Param && l.name != "Self" && !l.name.starts_with('$'))
                .map(|l| l.name.as_str())
                .collect();
            let args: Vec<String> =
                params.iter().filter(|(n, _, _)| declared.contains(&n.as_str())).map(|(_, v, _)| v.clone()).collect();
            let name = if args.is_empty() { info.name.clone() } else { format!("{}({})", info.name, args.join(", ")) };
            let (f, l) = self.info.lines.get(line as usize).copied().unwrap_or((info.file, info.line));
            out.push(obj(vec![
                ("name", text(&name)),
                ("file", text(self.info.files.get(f as usize).map(String::as_str).unwrap_or(""))),
                ("line", int(l as i64)),
            ]));
        }
        Ok(Value::Array(out))
    }

    fn answer(&mut self, id: i64, result: EResult<Vec<(&str, Value)>>) {
        let mut fields = vec![("id", int(id))];
        match result {
            Ok(values) => {
                fields.push(("ok", Value::Bool(true)));
                fields.extend(values);
            }
            Err(message) => {
                fields.push(("ok", Value::Bool(false)));
                fields.push(("error", text(&message)));
            }
        }
        self.emit("result", fields);
    }

    fn command(&mut self, cmd: &Value) {
        let name = cmd.get("command").and_then(Value::as_str).unwrap_or("");
        let id = cmd.get("id").and_then(Value::as_i64).unwrap_or(0);
        let frame = cmd.get("frame").and_then(Value::as_i64).unwrap_or(0).max(0) as usize;
        let s = |key: &str| cmd.get(key).and_then(Value::as_str).unwrap_or("").to_string();
        let running = self.stop.is_none();
        match name {
            "start" => match s("mode").as_str() {
                "into" | "over" => self.resume(INTO, 0),
                "run_to" => {
                    let line = cmd.get("line").and_then(Value::as_i64).unwrap_or(0) as u32;
                    if !self.run_to(&s("file"), line) {
                        self.resume(RUN, 0);
                    }
                }
                _ => self.resume(RUN, 0),
            },
            "continue" if !running => self.resume(RUN, 0),
            "step_into" if !running => self.step(INTO),
            "step_over" if !running => self.step(OVER),
            "step_out" if !running => self.step(OUT),
            "run_to" if !running => {
                let line = cmd.get("line").and_then(Value::as_i64).unwrap_or(0) as u32;
                if !self.run_to(&s("file"), line) {
                    self.emit("error", vec![("message", text("Baris itu tidak berisi kode"))]);
                }
            }
            "pause" => {
                let _ = self.shm.write_at(&[1], 1);
            }
            "set_breakpoints" => {
                let lines: Vec<u32> = cmd
                    .get("lines")
                    .and_then(Value::as_array)
                    .map(|a| a.iter().filter_map(Value::as_i64).map(|n| n as u32).collect())
                    .unwrap_or_default();
                self.set_breakpoints(id, &s("file"), &lines);
            }
            "evaluate" => {
                let expr = s("expr");
                let r = self
                    .with_evaluator(frame, |e| e.evaluate(&expr))
                    .map(|(v, t)| vec![("value", text(&v)), ("type", text(&t))]);
                self.answer(id, r);
            }
            "modify" => {
                let (expr, value) = (s("expr"), s("value"));
                let r = self
                    .with_evaluator(frame, |e| e.modify(&expr, &value))
                    .map(|(v, t)| vec![("value", text(&v)), ("type", text(&t))]);
                self.answer(id, r);
            }
            "locals" => {
                let r = self.with_evaluator(frame, |e| e.locals()).map(|rows| {
                    let rows = rows
                        .into_iter()
                        .map(|(n, v, t)| obj(vec![("name", text(&n)), ("value", text(&v)), ("type", text(&t))]))
                        .collect();
                    vec![("locals", Value::Array(rows))]
                });
                self.answer(id, r);
            }
            "stack" => {
                let r = self.stack_rows().map(|frames| vec![("frames", frames)]);
                self.answer(id, r);
            }
            "terminate" => {
                let _ = self.child.kill();
            }
            "continue" | "step_into" | "step_over" | "step_out" | "run_to" => {}
            other => self.emit("error", vec![("message", text(&format!("Perintah tidak dikenal: {other}")))]),
        }
    }

    fn on_runtime_error(&mut self, payload: &[u8]) {
        let code = u32::from_le_bytes(payload[0..4].try_into().unwrap());
        let addr = u64::from_le_bytes(payload[4..12].try_into().unwrap());
        let id = u32::from_le_bytes(payload[12..16].try_into().unwrap());
        let link_addr = (addr as i64).wrapping_sub(self.slide) as u64;
        let (f, l) = match self.info.lines.get(id as usize) {
            Some(&p) if self.stop.is_none() => p,
            _ => self.info.line_at(link_addr).unwrap_or((0, 0)),
        };
        let path = self.info.files.get(f as usize).cloned().unwrap_or_default();
        self.emit(
            "runtime_error",
            vec![
                ("code", int(code as i64)),
                ("address", text(&format!("${addr:016X}"))),
                ("file", text(&path)),
                ("line", int(l as i64)),
            ],
        );
    }

    fn finish(&mut self) {
        let status = self.child.wait().ok();
        let code = self
            .exit_code
            .or_else(|| status.and_then(|s| s.code()))
            .or_else(|| status.and_then(|s| s.signal()).map(|s| 128 + s))
            .unwrap_or(-1);
        self.emit("exited", vec![("code", int(code as i64))]);
    }

    fn run(&mut self) {
        loop {
            if let Some(cmd) = self.pending.pop_front() {
                self.command(&cmd);
                continue;
            }
            if self.ide_closed {
                let _ = self.child.kill();
            }
            match self.rx.recv() {
                Ok(Event::Ide(cmd)) => self.command(&cmd),
                Ok(Event::IdeClosed) => {
                    self.ide_closed = true;
                    let _ = self.child.kill();
                }
                Ok(Event::Frame(STOP, p)) if p.len() >= 9 => self.on_stop(&p),
                Ok(Event::Frame(RTERR, p)) if p.len() >= 16 => self.on_runtime_error(&p),
                Ok(Event::Frame(EXIT, p)) if p.len() >= 4 => {
                    self.exit_code = Some(i32::from_le_bytes(p[0..4].try_into().unwrap()));
                }
                Ok(Event::Frame(..)) => {}
                Ok(Event::ProgramClosed) | Err(_) => {
                    self.finish();
                    return;
                }
            }
        }
    }
}

struct Args {
    exe: PathBuf,
    odbg: Option<PathBuf>,
    fds: (i32, i32),
    cwd: Option<PathBuf>,
    program: Vec<String>,
}

fn parse_args(args: &[String]) -> Result<Args, String> {
    let mut it = args.iter();
    let (mut exe, mut odbg, mut fds, mut cwd) = (None, None, None, None);
    let mut program = Vec::new();
    while let Some(a) = it.next() {
        let mut value = || it.next().cloned().ok_or_else(|| format!("{a} memerlukan nilai"));
        match a.as_str() {
            "--exe" => exe = Some(PathBuf::from(value()?)),
            "--odbg" => odbg = Some(PathBuf::from(value()?)),
            "--cwd" => cwd = Some(PathBuf::from(value()?)),
            "--ide-fds" => {
                let v = value()?;
                let (r, w) = v.split_once(',').ok_or("--ide-fds R,W")?;
                fds = Some((r.parse().map_err(|_| "--ide-fds R,W")?, w.parse().map_err(|_| "--ide-fds R,W")?));
            }
            "--" => {
                program.extend(it.by_ref().cloned());
            }
            other => return Err(format!("opsi tidak dikenal: {other}")),
        }
    }
    Ok(Args {
        exe: exe.ok_or("--exe EXE diharapkan")?,
        odbg,
        fds: fds.ok_or("--ide-fds R,W diharapkan")?,
        cwd,
        program,
    })
}

fn reader_thread(mut stream: UnixStream, tx: Sender<Event>) {
    std::thread::spawn(move || {
        loop {
            let mut head = [0u8; 5];
            if stream.read_exact(&mut head).is_err() {
                break;
            }
            let len = u32::from_le_bytes(head[1..5].try_into().unwrap()) as usize;
            let mut payload = vec![0u8; len];
            if stream.read_exact(&mut payload).is_err() {
                break;
            }
            if tx.send(Event::Frame(head[0], payload)).is_err() {
                return;
            }
        }
        let _ = tx.send(Event::ProgramClosed);
    });
}

fn ide_thread(input: File, tx: Sender<Event>) {
    std::thread::spawn(move || {
        for line in BufReader::new(input).lines() {
            let Ok(line) = line else { break };
            if line.trim().is_empty() {
                continue;
            }
            if let Ok(v) = json::parse(&line)
                && tx.send(Event::Ide(v)).is_err()
            {
                return;
            }
        }
        let _ = tx.send(Event::IdeClosed);
    });
}

fn emit_raw(out: &mut File, event: &str, message: &str) {
    let line = obj(vec![("event", text(event)), ("message", text(message))]).to_json() + "\n";
    let _ = out.write_all(line.as_bytes());
}

/// Entry point of `odinpc debug`; returns the process exit code.
pub fn main(args: &[String]) -> i32 {
    let args = match parse_args(args) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("odinpc debug: {e}");
            return 2;
        }
    };
    // SAFETY: the IDE passed these descriptors to us (pass_fds); nothing
    // else owns them. The child must not inherit them, or the IDE would
    // never see end of file after we exit.
    let (input, mut out) = unsafe {
        fcntl(args.fds.0, 2, 1);
        fcntl(args.fds.1, 2, 1);
        (File::from_raw_fd(args.fds.0), File::from_raw_fd(args.fds.1))
    };
    match start(args, input, &mut out) {
        Ok(()) => 0,
        Err(message) => {
            emit_raw(&mut out, "error", &message);
            emit_raw(&mut out, "exited", "");
            1
        }
    }
}

fn start(args: Args, input: File, out: &mut File) -> Result<(), String> {
    let odbg = args.odbg.clone().unwrap_or_else(|| {
        let mut name = args.exe.file_name().map(|n| n.to_os_string()).unwrap_or_default();
        name.push(".odbg");
        args.exe.with_file_name(name)
    });
    let source = std::fs::read_to_string(&odbg).map_err(|e| format!("{}: {e}", odbg.display()))?;
    let info = DebugInfo::from_json(&source)?;
    if info.anchor == 0 || info.lines.is_empty() {
        return Err("Program dikompilasi tanpa info debug. Jalankan Debug > Start debugging untuk build ulang.".into());
    }
    let dir = std::env::temp_dir().join(format!("odin-debug-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    let result = session(args, info, &dir, input, out);
    let _ = std::fs::remove_dir_all(&dir);
    result
}

fn session(args: Args, info: DebugInfo, dir: &Path, input: File, out: &mut File) -> Result<(), String> {
    let socket = dir.join("s");
    let shm_path = dir.join("shm");
    let shm = File::options()
        .read(true)
        .write(true)
        .create(true)
        .truncate(true)
        .open(&shm_path)
        .map_err(|e| e.to_string())?;
    shm.set_len(16 + info.lines.len() as u64).map_err(|e| e.to_string())?;
    let listener = UnixListener::bind(&socket).map_err(|e| format!("{}: {e}", socket.display()))?;
    listener.set_nonblocking(true).map_err(|e| e.to_string())?;
    // Ctrl-C in the user screen is for the program (it pauses), not for us.
    // SAFETY: plain libc call; SIG_IGN needs no handler code.
    unsafe {
        signal(2, 1);
    }
    let mut command = Command::new(&args.exe);
    command.args(&args.program).env("ODIN_DEBUG_SOCKET", &socket).env("ODIN_DEBUG_SHM", &shm_path);
    if let Some(cwd) = &args.cwd {
        command.current_dir(cwd);
    }
    let mut child = command.spawn().map_err(|e| format!("{}: {e}", args.exe.display()))?;
    let started = Instant::now();
    let stream = loop {
        match listener.accept() {
            Ok((s, _)) => break s,
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                if let Ok(Some(_)) = child.try_wait() {
                    return Err("Program berhenti sebelum terhubung ke debugger. Build ulang dengan info debug.".into());
                }
                if started.elapsed() > Duration::from_secs(15) {
                    let _ = child.kill();
                    return Err("Program tidak terhubung ke debugger".into());
                }
                std::thread::sleep(Duration::from_millis(5));
            }
            Err(e) => return Err(e.to_string()),
        }
    };
    stream.set_nonblocking(false).map_err(|e| e.to_string())?;
    let (tx, rx) = channel();
    reader_thread(stream.try_clone().map_err(|e| e.to_string())?, tx.clone());
    ide_thread(input, tx);
    let mut ids: HashMap<(u32, u32), Vec<u32>> = HashMap::new();
    for (id, &line) in info.lines.iter().enumerate() {
        ids.entry(line).or_default().push(id as u32);
    }
    let flags = vec![0u8; info.lines.len()];
    let mut s = Session {
        info,
        slide: 0,
        stack: 0,
        stream,
        rx,
        pending: VecDeque::new(),
        ide_closed: false,
        out: out.try_clone().map_err(|e| e.to_string())?,
        shm,
        child,
        ids,
        flags,
        breakpoints: HashMap::new(),
        temporary: Vec::new(),
        stop: None,
        step: None,
        frames: None,
        exit_code: None,
    };
    let hello = match s.link().wait(HELLO) {
        Ok(h) if h.len() >= 18 => h,
        _ => {
            s.finish();
            return Ok(());
        }
    };
    let anchor = u64::from_le_bytes(hello[2..10].try_into().unwrap());
    s.slide = (anchor as i64).wrapping_sub(s.info.anchor as i64);
    s.stack = u64::from_le_bytes(hello[10..18].try_into().unwrap());
    s.emit("ready", vec![("lines", int(s.info.lines.len() as i64))]);
    s.run();
    Ok(())
}
