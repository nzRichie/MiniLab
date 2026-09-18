// The editor, wired together.
//
// Every edit goes through `Editor.run`, which sends a command to the server and
// takes the whole project back. Nothing here mutates a topology directly, and
// that is what keeps the canvas and `minicreate` from being two implementations
// of what a topology means.

import { api } from './api.js';
import { Blueprints } from './blueprints.js';
import { Canvas } from './canvas.js';
import { clone, derivedValue, Editor } from './doc.js';
import { Inspector } from './inspector.js';
import { openPalette } from './palette.js';
import { Findings, FootprintMeter } from './panels.js';
import { Projects } from './projects.js';
import { ask, button, confirmAsk, el, modal, pre, toast } from './ui.js';

const ed = new Editor();
const svg = document.getElementById('canvas');
const canvas = new Canvas(svg, ed);
const blueprints = new Blueprints(ed, { reopen: () => reopen() });
const inspector = new Inspector(document.getElementById('inspector'), ed, {
  renumberDialog: (scope) => renumberDialog(scope),
  saveBlueprint: (scope) => blueprints.saveBlueprint(scope),
  blueprintDiff: (scope) => blueprints.diff(scope),
  pullBlueprint: (scope) => blueprints.pull(scope),
  pushBlueprint: (scope) => blueprints.push(scope),
  groupIntoScope: (nodes) => blueprints.groupIntoScope(nodes),
  focusScope: (scope) => focusScope(scope),
});
const findings = new Findings(document.getElementById('findings'), ed, selectSubject);
const meter = new FootprintMeter(document.getElementById('footprint'), ed);
const projects = new Projects(ed, { openProject });

// --------------------------------------------------------------- rendering

function renderAll() {
  canvas.render();
  inspector.render();
  findings.render();
  meter.render();
  // The left panel lists the scopes, and an edit can add one: grouping a
  // selection, or adding a blueprint instance. Redrawing it only on open left it
  // showing the scopes a project had when it was opened.
  renderPalettePanel();
  renderChrome();
}

function renderChrome() {
  const focus = ed.focus ? ed.scope(ed.focus) : null;
  const crumb = document.getElementById('breadcrumb');
  crumb.hidden = !focus;
  if (focus) {
    crumb.textContent = `▸ ${focus.name}  (AS ${focus.asn}) · back to the whole project`;
    crumb.onclick = () => focusScope(null);
  }
  document.getElementById('project-name').textContent = ed.name || 'no project';
  document.getElementById('dirty').hidden = !ed.dirty;
  document.getElementById('unreviewed').hidden = !ed.unreviewed;
  document.getElementById('btn-undo').disabled = !ed.canUndo();
  document.getElementById('btn-redo').disabled = !ed.canRedo();
  const errors = (ed.findings || []).filter((f) => f.severity === 'error').length;
  const emit = document.getElementById('btn-emit');
  emit.disabled = !ed.doc || errors > 0;
  emit.title = errors
    ? `${errors} error(s) block emitting; warnings do not`
    : 'Write the spawnable package';
  document.getElementById('hint').textContent = ed.doc
    ? 'Drag a port to another node to link them. Alt-drag to pan, scroll to zoom, Ctrl+K for commands.'
    : '';
}

function renderPalettePanel() {
  const list = document.getElementById('preset-list');
  list.textContent = '';
  for (const preset of ed.presets) {
    const b = document.createElement('button');
    b.className = 'preset';
    b.innerHTML = `<span class="name"></span><span class="summary"></span>`;
    b.querySelector('.name').textContent = preset.name;
    b.querySelector('.summary').textContent = preset.summary;
    b.onclick = () => addNode(preset.name);
    list.appendChild(b);
  }

  const scopes = document.getElementById('scope-list');
  scopes.textContent = '';
  for (const s of ed.doc?.topology.scopes || []) {
    const row = document.createElement('div');
    row.className = 'scope-row';
    const drift = ed.divergenceOf(s.id);
    const marks = [
      ed.isCollapsed(s.id) ? 'collapsed' : '',
      drift && !drift.clean ? 'diverged' : '',
    ].filter(Boolean);
    row.appendChild(el('span', s.name));
    row.appendChild(el('span', marks.length ? `AS ${s.asn} · ${marks.join(' · ')}` : `AS ${s.asn}`, 'sub'));
    row.onclick = () => {
      ed.select(s.id);
    };
    row.ondblclick = () => focusScope(s.id);
    scopes.appendChild(row);
  }
  const add = button('Add a scope', addScope);
  add.style.marginTop = '6px';
  scopes.appendChild(add);

  const bp = document.getElementById('blueprint-list');
  bp.textContent = '';
  for (const b of blueprints.list) {
    const item = document.createElement('button');
    item.className = 'preset';
    item.innerHTML = '<span class="name"></span><span class="summary"></span>';
    item.querySelector('.name').textContent = b.name;
    item.querySelector('.summary').textContent =
      `${b.nodes} nodes${b.params.length ? ` · ${b.params.map((p) => p.name).join(', ')}` : ''}`;
    item.onclick = () => blueprints.insert(canvas.freeSpot());
    bp.appendChild(item);
  }
  if (!blueprints.list.length) {
    bp.appendChild(el('div', 'None yet. Select a scope and save it as one.', 'empty'));
  }
}

/// Look at one scope on its own, or go back to the whole project.
function focusScope(id) {
  ed.setFocus(id);
  canvas.fit();
  renderAll();
}

/// Re-read the project from the server, keeping the view.
///
/// Used after an endpoint that writes files of its own: saving a blueprint
/// stamps the scope as an instance of it, and pushing moves the hash, so what
/// the browser holds is a version behind.
async function reopen() {
  if (!ed.name) return;
  const focus = ed.focus;
  await ed.open(ed.name);
  ed.focus = focus;
  await blueprints.load();
  renderPalettePanel();
  renderAll();
}

// ------------------------------------------------------------------ edits

async function addNode(presetName) {
  if (!ed.doc) {
    toast('open a sandbox first');
    return;
  }
  const pos = canvas.freeSpot();
  await ed.run({ op: 'add_node', preset: presetName, pos });
}

async function addScope() {
  if (!ed.doc) return;
  const name = await ask('Add a scope', {
    label: 'Name',
    value: `as${(ed.doc.topology.scopes.length || 0) + 100}`,
    note: 'A scope is one AS number, one subnet, and the plan that fills it. Container names start with its AS number.',
  });
  if (!name) return;
  const asn = Number(
    (await ask('AS number', { label: 'A number', value: '101' })) || '0',
  );
  if (!asn) return;
  const subnet = await ask('Subnet', { label: 'For example 101.0.0.0/24', value: `${asn}.0.0.0/24` });
  if (!subnet) return;
  await ed.run({ op: 'add_scope', name, asn, subnet });
}

/// Two ports, or a port and a node. The server decides which interface is used
/// when the drop landed on a node's body rather than on a port.
async function requestLink(fromIface, toNode, toIface) {
  const from = ed.iface(fromIface);
  if (!from) return;
  await ed.run({
    op: 'add_link',
    a: { node: from.node.id, iface: fromIface },
    b: toIface ? { node: toNode, iface: toIface } : { node: toNode },
  });
}

canvas.onRequestLink = requestLink;
canvas.onOpenScope = (id) => focusScope(id);
canvas.onDropOnScope = () => {
  toast(
    'drop the link on one of the scope\'s border ports, or open the scope and link to a node inside it',
    true,
  );
};
canvas.onOpenNode = (id) => {
  ed.select(id);
  const input = document.querySelector('.inspector input[type="text"]');
  if (input) input.select();
};

async function deleteSelection() {
  const nodes = ed.selectedNodes();
  const links = ed.selectedLinks();
  if (!nodes.length && !links.length) return;
  const cmds = [];
  if (links.length) cmds.push({ op: 'delete_links', links: links.map((l) => l.id) });
  if (nodes.length) cmds.push({ op: 'delete_nodes', nodes: nodes.map((n) => n.id) });
  await ed.run(cmds, { label: 'delete the selection' });
}

async function autoLayout() {
  await ed.run({ op: 'auto_layout' });
  canvas.fit();
}

function selectSubject(subject) {
  if (!subject?.id) return;
  // A finding about an interface selects the node it sits on, because an
  // interface is not a thing on the canvas: its node is.
  if (subject.type === 'interface') {
    const found = ed.iface(subject.id);
    if (found) ed.select(found.node.id);
    return;
  }
  ed.select(subject.id);
}

// ---------------------------------------------------------------- actions

async function save() {
  if (!ed.doc) return;
  try {
    await ed.save();
    toast('saved');
  } catch (e) {
    const body = e.body;
    if (body?.findings) {
      ed.findings = body.findings;
      findings.render();
      toast(`${body.errors} error(s) block saving`, true);
    } else {
      toast(e.message, true);
    }
  }
}

async function emit() {
  if (!ed.doc) return;
  try {
    if (ed.dirty) await ed.save();
    const res = await api.emit(ed.name);
    modal((box, close) => {
      box.appendChild(el('h2', 'Emitted'));
      box.appendChild(
        el(
          'p',
          `${res.files.length} files in ${res.out}. Run it from the TUI: Sandboxes, then Spawn, and give it the name ${ed.name}.`,
        ),
      );
      box.appendChild(pre(res.files.join('\n')));
      box.appendChild(el('h2', 'Images'));
      box.appendChild(
        pre(
          Object.entries(res.images)
            .map(([preset, tag]) => `${preset}  ${tag}`)
            .join('\n') || 'none',
        ),
      );
      const actions = document.createElement('div');
      actions.className = 'actions';
      actions.appendChild(button('Close', close, 'primary'));
      box.appendChild(actions);
    });
  } catch (e) {
    const body = e.body;
    if (body?.findings) {
      ed.findings = body.findings;
      findings.render();
      toast(`${body.errors} error(s) block emitting`, true);
    } else {
      toast(e.message, true);
    }
  }
}

/// Renumber, with the preview first.
///
/// The preview is the same command applied to a copy of the document: `ops` is
/// pure and writes nothing, so what the preview shows and what the apply does
/// cannot drift apart. One apply, one undo step.
async function renumberDialog(scope) {
  const template = await ask(`Renumber ${scope.name}`, {
    label: 'Address plan',
    value: scope.address_plan?.template || '{asn}.0.0.{host}',
    ok: 'Preview',
    note: 'The bindings are {asn}, {site}, {link}, {host} and {index}. Pinned addresses do not move.',
  });
  if (!template) return;

  const command = { op: 'renumber', scope: scope.id, template };
  let preview;
  try {
    preview = await api.ops(clone(ed.doc), [command]);
  } catch (e) {
    toast(e.message, true);
    return;
  }

  const before = addressMap(ed.doc.topology);
  const after = addressMap(preview.topology);
  const changes = [];
  for (const [id, value] of after) {
    if (before.get(id) !== value) changes.push(`${id}  ${before.get(id) || '-'} -> ${value}`);
  }

  const go = await confirmAsk(
    `Renumber ${scope.name}`,
    changes.length
      ? `${changes.length} address(es) change. Pinned ones stay where they are.`
      : 'Nothing changes under this plan.',
    { ok: 'Apply' },
  );
  if (!go) return;
  await ed.run(command, { label: `renumber ${scope.name}` });
}

function addressMap(topology) {
  const out = new Map();
  for (const n of topology.nodes) {
    for (const i of n.interfaces || []) {
      const ip = derivedValue(i.ip);
      if (ip) out.set(`${n.name}/${derivedValue(i.name)}`, ip);
    }
  }
  return out;
}

// ----------------------------------------------------------------- opening

async function openProject(name) {
  await ed.open(name);
  await blueprints.load();
  renderPalettePanel();

  // A project written by `minicreate` or imported from somebody else has no
  // layout.toml, so every node sits at the same default point. Lay it out on
  // first open and save that, because a pile of nodes on top of each other
  // looks like a broken editor rather than like a project nobody has drawn yet.
  const nodes = ed.doc.topology.nodes;
  if (nodes.length && nodes.some((n) => !ed.position(n.id))) {
    await ed.run({ op: 'auto_layout' }, { label: 'lay the topology out' });
    await ed.save().catch(() => {});
  }

  canvas.fit();
  renderAll();

  // A draft is unsaved work from a session that did not end with a save: the
  // editor container was killed, the tab was closed, the machine went away.
  try {
    const draft = await api.getDraft(name);
    if (draft.exists && draft.differs) {
      const take = await confirmAsk(
        'There is unsaved work',
        'This sandbox has a draft that is newer than the saved file. Recover it, or keep what was saved and throw the draft away.',
        { ok: 'Recover the draft' },
      );
      if (take) {
        await ed.adoptDraft(draft);
        canvas.fit();
        renderAll();
        toast('recovered; save it to keep it');
      } else {
        await api.dropDraft(name);
      }
    }
  } catch {
    // A project with no draft is the ordinary case, and a draft that cannot be
    // read is not a reason to refuse to open the project.
  }

  if (ed.unreviewed) await projects.review();
}

// ---------------------------------------------------------------- commands

function commandList() {
  const cmds = [
    { label: 'Save', hint: 'Ctrl+S', run: save },
    { label: 'Emit the spawnable package', hint: 'e', run: emit },
    { label: 'Auto layout', hint: 'l', run: autoLayout },
    { label: 'Fit the topology in view', hint: 'f', run: () => canvas.fit() },
    { label: 'Undo', hint: 'Ctrl+Z', run: () => ed.undo() },
    { label: 'Redo', hint: 'Ctrl+Shift+Z', run: () => ed.redo() },
    { label: 'Open a sandbox', hint: 'g p', run: () => projects.browse() },
    { label: 'New sandbox', run: () => projects.createProject() },
    { label: 'Duplicate this sandbox', run: () => projects.duplicate() },
    { label: 'Rename this sandbox', run: () => projects.rename() },
    { label: 'Delete this sandbox', run: () => projects.remove() },
    { label: 'Export this sandbox as a file', run: () => projects.exportBundle() },
    { label: 'Export as a lab skeleton', run: () => projects.skeletonCommand() },
    { label: 'Import a sandbox from a file', run: () => projects.importBundle() },
    { label: 'Review what this sandbox runs', run: () => projects.review() },
    { label: 'Save a version', run: () => projects.saveVersion() },
    { label: 'Versions', run: () => projects.versions() },
    { label: 'Select everything', run: () => ed.select((ed.doc?.topology.nodes || []).map((n) => n.id)) },
    { label: 'Delete the selection', hint: 'Delete', run: deleteSelection },
    { label: 'Add a scope', run: addScope },
    { label: 'Add a blueprint', run: () => blueprints.insert(canvas.freeSpot()) },
    {
      label: 'Group the selection into a scope',
      run: () => {
        const nodes = ed.selectedNodes().map((n) => n.id);
        if (nodes.length < 1) {
          toast('select the nodes first');
          return;
        }
        blueprints.groupIntoScope(nodes);
      },
    },
    { label: 'Back to the whole project', run: () => focusScope(null) },
  ];
  for (const s of ed.doc?.topology.scopes || []) {
    cmds.push({
      label: `${ed.isCollapsed(s.id) ? 'Open' : 'Collapse'} the scope ${s.name}`,
      run: () => ed.run({ op: 'set_collapsed', scope: s.id, collapsed: !ed.isCollapsed(s.id) }),
    });
    cmds.push({ label: `Look inside ${s.name}`, run: () => focusScope(s.id) });
    if (s.blueprint) {
      cmds.push({ label: `What differs in ${s.name}`, run: () => blueprints.diff(s) });
      cmds.push({ label: `Take the blueprint again for ${s.name}`, run: () => blueprints.pull(s) });
    } else {
      cmds.push({ label: `Save ${s.name} as a blueprint`, run: () => blueprints.saveBlueprint(s) });
    }
  }
  for (const preset of ed.presets) {
    cmds.push({
      label: `Add a node: ${preset.name}`,
      hint: preset.summary,
      run: () => addNode(preset.name),
    });
  }
  for (const s of ed.doc?.topology.scopes || []) {
    cmds.push({ label: `Renumber ${s.name}`, run: () => renumberDialog(s) });
  }
  return cmds;
}

// --------------------------------------------------------------- keyboard

let pendingG = false;

document.addEventListener('keydown', async (ev) => {
  const typing = ['INPUT', 'TEXTAREA', 'SELECT'].includes(ev.target.tagName);
  const meta = ev.ctrlKey || ev.metaKey;

  if (meta && ev.key.toLowerCase() === 'k') {
    ev.preventDefault();
    openPalette(commandList());
    return;
  }
  if (meta && ev.key.toLowerCase() === 's') {
    ev.preventDefault();
    await save();
    return;
  }
  if (meta && ev.key.toLowerCase() === 'z') {
    ev.preventDefault();
    await (ev.shiftKey ? ed.redo() : ed.undo());
    return;
  }
  if (typing) return;

  if (pendingG) {
    pendingG = false;
    if (ev.key === 'p') {
      projects.browse();
      return;
    }
  }
  switch (ev.key) {
    case 'g':
      pendingG = true;
      break;
    case 'Delete':
    case 'Backspace':
      ev.preventDefault();
      await deleteSelection();
      break;
    case 'l':
      await autoLayout();
      break;
    case 'f':
      canvas.fit();
      break;
    case 'e':
      await emit();
      break;
    case 'Escape':
      // Out of the scope being looked at first, and only then out of the
      // selection: a user in a focused scope presses Escape to come back up.
      if (ed.focus) focusScope(null);
      else ed.clearSelection();
      break;
    case 'a':
      if (ev.shiftKey) ed.select((ed.doc?.topology.nodes || []).map((n) => n.id));
      break;
    default:
      break;
  }
});

// ----------------------------------------------------------------- events

ed.on('changed', renderAll);
ed.on('selection', () => {
  canvas.render();
  inspector.render();
});
ed.on('opened', renderPalettePanel);
ed.on('note', (text) => toast(text));
ed.on('refused', (text) => toast(text, true));

document.getElementById('btn-save').onclick = save;
document.getElementById('btn-emit').onclick = emit;
document.getElementById('btn-layout').onclick = autoLayout;
document.getElementById('btn-undo').onclick = () => ed.undo();
document.getElementById('btn-redo').onclick = () => ed.redo();
document.getElementById('btn-palette').onclick = () => openPalette(commandList());
document.getElementById('btn-version').onclick = () => projects.saveVersion();
document.getElementById('menu-projects').onclick = () => projects.browse();

window.addEventListener('beforeunload', (ev) => {
  if (ed.dirty) {
    ev.preventDefault();
    ev.returnValue = '';
  }
});

// ------------------------------------------------------------------- boot

(async function boot() {
  try {
    await ed.loadPresets();
    await blueprints.load();
    renderPalettePanel();
    const list = await api.projects();
    // Straight into the only sandbox, when there is one: a user who came here
    // from the TUI has a sandbox in mind, and a browser between them and it is
    // a step that says nothing.
    if (list.length === 1) {
      await openProject(list[0].name);
    } else if (list.length === 0) {
      await projects.createProject();
    } else {
      await projects.browse();
    }
  } catch (e) {
    toast(`the editor could not start: ${e.message}`, true);
  }
  renderAll();
})();
