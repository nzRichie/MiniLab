// The document the canvas is editing, and the journal that makes undo work.
//
// The model itself lives in `create/core`: every edit goes to the server as a
// command and the whole project comes back applied. What lives here is only what
// a browser has to own, which is the sequence of commands, the selection, and
// whether there is unsaved work.
//
// Undo is a journal of commands rather than a diff between snapshots. Each entry
// records the command's own label and the document before and after it, so one
// gesture is one undo step however much it moved: a renumber touches every
// address in a scope and is still one entry, which is exactly the case a diff
// between snapshots cannot get right without guessing where an edit began.

import { api } from './api.js';

const JOURNAL_MAX = 120;
const DRAFT_DEBOUNCE_MS = 1500;

export class Editor {
  constructor() {
    this.name = null;          // the sandbox directory name
    this.doc = null;           // { topology, layout }
    this.findings = [];
    this.footprint = null;
    this.presets = [];
    this.selection = new Set(); // ids: node, link, scope or interface
    /// The scope being looked at, or null for the whole project. Navigation,
    /// not a filter on the document: nothing about the project changes.
    this.focus = null;
    /// Where each blueprint instance stands against its blueprint, by scope id.
    /// It arrives with every edit, so the badge is never stale.
    this.blueprints = {};
    this.dirty = false;
    this.unreviewed = false;
    this.journal = [];
    this.at = -1;              // index of the last applied entry
    this.listeners = new Map();
    this.draftTimer = null;
  }

  on(event, fn) {
    if (!this.listeners.has(event)) this.listeners.set(event, []);
    this.listeners.get(event).push(fn);
  }

  emit(event, detail) {
    for (const fn of this.listeners.get(event) || []) fn(detail);
  }

  // ---------------------------------------------------------------- opening

  async loadPresets() {
    this.presets = await api.presets();
    this.emit('presets', this.presets);
  }

  async open(name) {
    const doc = normalise(await api.project(name));
    this.name = name;
    this.doc = doc;
    this.journal = [];
    this.at = -1;
    this.dirty = false;
    this.focus = null;
    this.selection.clear();
    const review = await api.review(name).catch(() => ({ unreviewed: false }));
    this.unreviewed = !!review.unreviewed;
    await this.revalidate();
    this.emit('opened', { name, doc });
    return doc;
  }

  /// Findings and footprint for the document as it stands, without saving it.
  /// An empty command list is a validate: the same endpoint, nothing applied.
  async revalidate() {
    const res = await api.ops(this.doc, []);
    this.findings = res.findings.findings;
    this.footprint = res.footprint;
    this.blueprints = res.blueprints || {};
    this.emit('changed', this);
  }

  // ----------------------------------------------------------------- edits

  /// Apply one command, or several that belong to one gesture.
  ///
  /// A refusal is returned rather than thrown at the caller: the canvas shows it
  /// and leaves the document as it was, which is what "the link you just drew is
  /// not allowed" has to look like.
  async run(commands, { label } = {}) {
    const list = Array.isArray(commands) ? commands : [commands];
    const before = clone(this.doc);
    let res;
    try {
      res = await api.ops(this.doc, list);
    } catch (e) {
      this.emit('refused', e.message || String(e));
      // Redraw from the document as it still stands, so a field that was
      // refused goes back to the value the project actually holds rather than
      // sitting there showing text the server rejected.
      this.emit('changed', this);
      return null;
    }
    this.doc = normalise({ topology: res.topology, layout: res.layout });
    this.findings = res.findings.findings;
    this.footprint = res.footprint;
    this.blueprints = res.blueprints || {};
    this.dirty = true;

    const applied = res.applied || [];
    this.push({
      label: label || applied.map((a) => a.label).join(', ') || 'edit',
      before,
      after: clone(this.doc),
    });

    const selected = applied.flatMap((a) => a.selected || []);
    if (selected.length) this.select(selected);

    for (const note of applied.flatMap((a) => a.notes || [])) this.emit('note', note);
    this.emit('changed', this);
    this.scheduleDraft();
    return res;
  }

  push(entry) {
    // Anything undone and then edited over is gone, which is what every editor
    // does and what keeps the journal a line rather than a tree.
    this.journal.length = this.at + 1;
    this.journal.push(entry);
    if (this.journal.length > JOURNAL_MAX) this.journal.shift();
    this.at = this.journal.length - 1;
  }

  canUndo() {
    return this.at >= 0;
  }

  canRedo() {
    return this.at < this.journal.length - 1;
  }

  async undo() {
    if (!this.canUndo()) return;
    const entry = this.journal[this.at];
    this.doc = clone(entry.before);
    this.at -= 1;
    this.dirty = true;
    await this.revalidate();
    this.emit('note', `undo: ${entry.label}`);
    this.scheduleDraft();
  }

  async redo() {
    if (!this.canRedo()) return;
    const entry = this.journal[this.at + 1];
    this.doc = clone(entry.after);
    this.at += 1;
    this.dirty = true;
    await this.revalidate();
    this.emit('note', `redo: ${entry.label}`);
    this.scheduleDraft();
  }

  // ------------------------------------------------------------- selection

  select(ids, { add = false } = {}) {
    if (!add) this.selection.clear();
    for (const id of [].concat(ids)) this.selection.add(id);
    this.emit('selection', this.selection);
  }

  clearSelection() {
    this.selection.clear();
    this.emit('selection', this.selection);
  }

  selectedNodes() {
    return (this.doc?.topology.nodes || []).filter((n) => this.selection.has(n.id));
  }

  selectedLinks() {
    return (this.doc?.topology.links || []).filter((l) => this.selection.has(l.id));
  }

  // ------------------------------------------------------------ persistence

  /// Save. Errors refuse the write; warnings do not, because a topology that is
  /// half drawn warns constantly and a save that refused on a warning would be
  /// unusable.
  async save() {
    const res = await api.save(this.name, this.doc);
    this.dirty = false;
    this.findings = res.findings;
    await api.dropDraft(this.name).catch(() => {});
    this.emit('changed', this);
    this.emit('saved', res);
    return res;
  }

  /// The draft: unsaved work, written where it survives the editor container
  /// being killed. It validates nothing, because a topology in the middle of
  /// being drawn is usually invalid and losing it would be the worse failure.
  scheduleDraft() {
    if (!this.name) return;
    clearTimeout(this.draftTimer);
    this.draftTimer = setTimeout(() => {
      api.putDraft(this.name, this.doc).catch(() => {});
    }, DRAFT_DEBOUNCE_MS);
  }

  /// Take a recovered draft as the current document, as one undoable step.
  adoptDraft(draft) {
    const before = clone(this.doc);
    this.doc = normalise({ topology: draft.topology, layout: draft.layout });
    this.dirty = true;
    this.push({ label: 'recover the draft', before, after: clone(this.doc) });
    return this.revalidate();
  }

  // --------------------------------------------------------------- lookups

  node(id) {
    return (this.doc?.topology.nodes || []).find((n) => n.id === id) || null;
  }

  link(id) {
    return (this.doc?.topology.links || []).find((l) => l.id === id) || null;
  }

  scope(id) {
    return (this.doc?.topology.scopes || []).find((s) => s.id === id) || null;
  }

  /// The node an interface sits on, and the interface itself.
  iface(id) {
    for (const n of this.doc?.topology.nodes || []) {
      const i = n.interfaces?.find((x) => x.id === id);
      if (i) return { node: n, iface: i };
    }
    return null;
  }

  preset(name) {
    return this.presets.find((p) => p.name === name) || null;
  }

  position(id) {
    return this.doc?.layout?.positions?.[id] || null;
  }

  scopePosition(id) {
    return this.doc?.layout?.scope_positions?.[id] || null;
  }

  isCollapsed(id) {
    return (this.doc?.layout?.collapsed || []).includes(id);
  }

  nodesInScope(id) {
    return (this.doc?.topology.nodes || []).filter((n) => n.scope === id);
  }

  /// What the server said about this scope against its blueprint, or null for a
  /// scope that did not come from one.
  divergenceOf(id) {
    return this.blueprints?.[id] || null;
  }

  /// Look at one scope on its own. A view, so it is state here and not an edit.
  setFocus(id) {
    this.focus = id;
    this.selection.clear();
    this.emit('changed', this);
  }

  /// Whether an interface is on a link already, which is what a port handle
  /// renders as taken.
  ifaceBusy(id) {
    return (this.doc?.topology.links || []).some((l) => l.a === id || l.b === id);
  }
}

/// Fill in what the file format leaves out.
///
/// `topology.toml` omits an empty list rather than writing `nodes = []`, which is
/// what makes a hand-written file read well and what makes a fresh project
/// arrive here with no `nodes` and no `links` key at all. Every consumer would
/// otherwise have to guard each one, and the first that forgot took the whole
/// editor down with "doc.topology.links is not iterable" on an empty sandbox.
export function normalise(doc) {
  const t = doc.topology || {};
  t.scopes = t.scopes || [];
  t.nodes = t.nodes || [];
  t.links = t.links || [];
  for (const n of t.nodes) {
    n.interfaces = n.interfaces || [];
    n.raw = n.raw || {};
  }
  const layout = doc.layout || {};
  layout.schema = layout.schema || 1;
  layout.positions = layout.positions || {};
  layout.scope_positions = layout.scope_positions || {};
  layout.collapsed = layout.collapsed || [];
  for (const s of t.scopes) s.reservations = s.reservations || [];
  return { topology: t, layout };
}

/// A deep copy. `structuredClone` is in every browser this ships to, and the
/// fallback keeps the editor working in one that predates it.
export function clone(v) {
  if (typeof structuredClone === 'function') return structuredClone(v);
  return JSON.parse(JSON.stringify(v));
}

/// Read a `Derived<T>`: a pinned value is `{ pinned: v }` in the file, and a
/// derived one is the bare value, which is the same split the TOML carries.
export function derivedValue(d) {
  if (d === null || d === undefined) return null;
  if (typeof d === 'object' && 'pinned' in d) return d.pinned;
  return d;
}

export function isPinned(d) {
  return !!(d && typeof d === 'object' && 'pinned' in d);
}
