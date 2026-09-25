// Blueprints, from the canvas: saving a scope as one, adding an instance,
// seeing what an instance has drifted into, and pulling or pushing.
//
// The pieces that decide what a blueprint means are in `create/core`; this is
// the dialogs over them. Two of the four write a file, so they go through their
// own endpoints and the project is saved first: what goes into a blueprint is
// what is in the file, not what is in the browser.

import { api } from './api.js';
import { ask, button, confirmAsk, el, modal, pre, toast } from './ui.js';

export class Blueprints {
  constructor(editor, app) {
    this.ed = editor;
    this.app = app;
    this.list = [];
  }

  async load() {
    this.list = await api.blueprints().catch(() => []);
    return this.list;
  }

  /// Save one scope as a blueprint, choosing what becomes a parameter.
  ///
  /// The parameters are offered rather than asked for from nothing: the ASN and
  /// the subnet are what varies between instances almost every time, so they are
  /// pre-filled with what this scope has, and the user unticks what should stay
  /// fixed.
  async saveBlueprint(scope) {
    // A blueprint with no border port cannot take an inter-AS link: promoted
    // ports are the only thing a pull keeps, so every instance of it would have
    // to have one promoted by hand before it could be wired to anything. Said
    // before the blueprint is written, where the fix is one click away, rather
    // than discovered on the third instance.
    const ports = this.ed
      .nodesInScope(scope.id)
      .flatMap((n) => (n.interfaces || []).filter((i) => i.external));
    if (!ports.length) {
      const go = await confirmAsk(
        `${scope.name} has no border ports`,
        'A border port is where a link from another AS lands, and it is the only thing that ' +
          'survives a pull from a blueprint. Without one, an instance of this blueprint cannot ' +
          'be wired to anything while it is drawn as one node. Select an interface inside the ' +
          'scope and use "Make this a border port" first, or save it anyway.',
        { ok: 'Save it anyway' },
      );
      if (!go) return;
    }

    const suggestions = [
      { name: 'asn', description: 'the AS number', value: String(scope.asn), on: true },
      { name: 'subnet', description: 'the subnet', value: scope.subnet, on: false },
      { name: 'site', description: 'a name to put in node names', value: '', on: false },
    ];

    const chosen = await new Promise((resolve) => {
      modal((box, close) => {
        box.appendChild(el('h2', `Save ${scope.name} as a blueprint`));
        box.appendChild(
          el(
            'p',
            'Everywhere the value below appears in this scope becomes the parameter, so an instance can be given a different one. A value of one or two characters is left alone, because replacing every 3 in every address is not what anybody means.',
          ),
        );

        const nameField = document.createElement('div');
        nameField.className = 'field';
        nameField.appendChild(el('label', 'Blueprint name'));
        const nameInput = document.createElement('input');
        nameInput.type = 'text';
        nameInput.value = scope.name;
        nameField.appendChild(nameInput);
        box.appendChild(nameField);

        const rows = [];
        for (const s of suggestions) {
          const row = document.createElement('div');
          row.className = 'field row';
          const tick = document.createElement('input');
          tick.type = 'checkbox';
          tick.checked = s.on;
          tick.style.flex = '0 0 auto';
          const name = document.createElement('input');
          name.type = 'text';
          name.value = s.name;
          const value = document.createElement('input');
          value.type = 'text';
          value.value = s.value;
          value.placeholder = 'the value it has now';
          row.append(tick, name, value);
          box.appendChild(row);
          rows.push({ tick, name, value, description: s.description });
        }

        const actions = document.createElement('div');
        actions.className = 'actions';
        actions.appendChild(button('Cancel', () => {
          close();
          resolve(null);
        }));
        actions.appendChild(
          button('Save', () => {
            const params = rows
              .filter((r) => r.tick.checked && r.name.value.trim() && r.value.value.trim())
              .map((r) => ({
                name: r.name.value.trim(),
                description: r.description,
                value: r.value.value.trim(),
              }));
            const out = { name: nameInput.value.trim(), params };
            close();
            resolve(out.name ? out : null);
          }, 'primary'),
        );
        box.appendChild(actions);
      });
    });
    if (!chosen) return;

    try {
      if (this.ed.dirty) await this.ed.save();
      await api.saveBlueprint(this.ed.name, {
        scope: scope.id,
        name: chosen.name,
        params: chosen.params,
      });
      await this.load();
      await this.app.reopen();
      toast(`saved the blueprint ${chosen.name}`);
    } catch (e) {
      if (e.status === 409) {
        const over = await confirmAsk(
          'That name is taken',
          `A blueprint called ${chosen.name} already exists. Write over it?`,
          { ok: 'Overwrite' },
        );
        if (!over) return;
        try {
          await api.saveBlueprint(this.ed.name, {
            scope: scope.id,
            name: chosen.name,
            params: chosen.params,
            overwrite: true,
          });
          await this.load();
          await this.app.reopen();
          toast(`saved the blueprint ${chosen.name}`);
        } catch (inner) {
          toast(inner.message, true);
        }
        return;
      }
      toast(e.message, true);
    }
  }

  /// Add an instance: pick a blueprint, then bind its parameters.
  async insert(pos) {
    await this.load();
    if (!this.list.length) {
      toast('there are no blueprints yet; save a scope as one first');
      return;
    }
    const chosen = await new Promise((resolve) => {
      modal((box, close) => {
        box.appendChild(el('h2', 'Add a blueprint'));
        const list = document.createElement('div');
        list.className = 'list';
        for (const b of this.list) {
          const row = document.createElement('div');
          row.className = 'list-row';
          const main = document.createElement('div');
          main.className = 'grow';
          main.appendChild(el('div', b.name));
          main.appendChild(
            el(
              'div',
              `${b.nodes} nodes · ${b.links} links${b.ports.length ? ` · ports: ${b.ports.join(', ')}` : ''}`,
              'meta',
            ),
          );
          if (b.summary) main.appendChild(el('div', b.summary, 'meta'));
          row.appendChild(main);
          row.onclick = () => {
            close();
            resolve(b);
          };
          list.appendChild(row);
        }
        box.appendChild(list);
        const actions = document.createElement('div');
        actions.className = 'actions';
        actions.appendChild(button('Cancel', () => {
          close();
          resolve(null);
        }));
        box.appendChild(actions);
      });
    });
    if (!chosen) return;

    const params = await this.bindParams(chosen);
    if (!params) return;
    await this.ed.run({ op: 'instantiate_blueprint', blueprint: chosen.name, params, pos });
  }

  /// One field per declared parameter, filled with its default.
  bindParams(b) {
    if (!b.params.length) return Promise.resolve({});
    return new Promise((resolve) => {
      modal((box, close) => {
        box.appendChild(el('h2', `${b.name}`));
        box.appendChild(el('p', 'What this instance is given.'));
        const inputs = [];
        for (const p of b.params) {
          const field = document.createElement('div');
          field.className = 'field';
          field.appendChild(el('label', p.description ? `${p.name} — ${p.description}` : p.name));
          const input = document.createElement('input');
          input.type = 'text';
          input.value = p.default ?? '';
          field.appendChild(input);
          box.appendChild(field);
          inputs.push({ name: p.name, input });
        }
        const actions = document.createElement('div');
        actions.className = 'actions';
        actions.appendChild(button('Cancel', () => {
          close();
          resolve(null);
        }));
        actions.appendChild(
          button('Add it', () => {
            const out = {};
            for (const i of inputs) out[i.name] = i.input.value.trim();
            close();
            resolve(out);
          }, 'primary'),
        );
        box.appendChild(actions);
      });
    });
  }

  /// What an instance has drifted into, in the words the core reports.
  diff(scope) {
    const drift = this.ed.divergenceOf(scope.id);
    modal((box, close) => {
      box.appendChild(el('h2', `${scope.name} against ${scope.blueprint?.name}`));
      if (!drift) {
        box.appendChild(el('p', 'This scope did not come from a blueprint.'));
      } else if (drift.missing) {
        box.appendChild(el('p', drift.summary));
        box.appendChild(
          el('p', 'The instance still works and still spawns. What it cannot do is be compared with, or pulled from, a blueprint this machine does not have.'),
        );
      } else if (drift.clean) {
        box.appendChild(el('p', 'This instance matches its blueprint.'));
      } else {
        box.appendChild(el('p', drift.summary));
        box.appendChild(pre(describe(drift.detail)));
        box.appendChild(
          el(
            'p',
            'Taking the blueprint replaces everything in this scope. Writing this back changes the blueprint, and every other instance of it will then report that the blueprint has changed.',
          ),
        );
      }
      const actions = document.createElement('div');
      actions.className = 'actions';
      actions.appendChild(button('Close', close, 'primary'));
      box.appendChild(actions);
    });
  }

  async pull(scope) {
    const yes = await confirmAsk(
      `Take the blueprint again for ${scope.name}`,
      'Everything in this scope is replaced by what the blueprint says. A link from outside is kept only where it lands on a border port. This is one undo step.',
      { ok: 'Take the blueprint' },
    );
    if (!yes) return;
    await this.ed.run({ op: 'pull_from_blueprint', scope: scope.id });
  }

  async push(scope) {
    const yes = await confirmAsk(
      `Write ${scope.name} back to ${scope.blueprint?.name}`,
      'The blueprint becomes what this scope is now. Its parameters are kept, so instances with other values keep theirs, and every other instance will report that the blueprint has changed.',
      { ok: 'Write it back' },
    );
    if (!yes) return;
    try {
      if (this.ed.dirty) await this.ed.save();
      const res = await api.pushBlueprint(this.ed.name, scope.id);
      await this.load();
      await this.app.reopen();
      for (const note of res.notes || []) toast(note, true);
      if (!res.notes?.length) toast(`${scope.blueprint?.name} updated`);
    } catch (e) {
      toast(e.message, true);
    }
  }

  /// Group a selection into a new scope, which is what "assign these to an AS"
  /// means in the model.
  async groupIntoScope(nodes) {
    const name = await ask('Group into a scope', {
      label: 'Name',
      value: '',
      note: 'A scope is one AS number, one subnet and one address plan. Every container in it is named <AS>_SBX_<node>.',
    });
    if (!name) return;
    const asn = Number(await ask('AS number', { label: 'A number', value: '101' }));
    if (!asn) return;
    const subnet = await ask('Subnet', {
      label: 'For example 101.0.0.0/24',
      value: `${asn}.0.0.0/24`,
    });
    if (!subnet) return;
    // The nodes leave the scope that is being looked at, so an inside view would
    // stop drawing every one of them the moment the group is made. Coming back
    // out is the only way the new scope is visible at all.
    const wasFocused = this.ed.focus;
    if (wasFocused) this.ed.setFocus(null);
    const res = await this.ed.run({
      op: 'group_into_scope',
      nodes,
      name,
      asn,
      subnet,
      template: `{asn}.0.0.{host}`,
    });
    if (res && wasFocused) {
      toast(`${nodes.length} node(s) moved into ${name}; showing the whole project`);
    }
    return res;
  }
}

/// The divergence detail as lines a person reads.
function describe(d) {
  if (!d) return 'nothing';
  const lines = [];
  for (const [items, what] of [
    [d.added_nodes, 'added'],
    [d.removed_nodes, 'missing'],
    [d.changed_nodes, 'edited'],
  ]) {
    for (const n of items || []) lines.push(`${what}: ${n}`);
  }
  for (const l of d.added_links || []) lines.push(`added link: ${l}`);
  for (const l of d.removed_links || []) lines.push(`missing link: ${l}`);
  for (const c of d.scope_changes || []) lines.push(c);
  if (d.blueprint_changed) lines.push('the blueprint itself has changed since this instance was made');
  return lines.join('\n') || 'nothing';
}
