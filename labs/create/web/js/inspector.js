// The inspector: what the selection is, and every field of it that can change.
//
// Raw fields sit behind an "advanced" disclosure rather than beside the ordinary
// ones, because their size is the expressiveness metric: a topology whose every
// node needs `run_args` is a topology the presets do not cover, and that should
// be visible as work rather than as the normal way to fill a node in.

import { derivedValue, isPinned } from './doc.js';
import { linkKind } from './canvas.js';

export class Inspector {
  constructor(root, editor, ui) {
    this.root = root;
    this.ed = editor;
    this.ui = ui; // { toast, renumberDialog }
  }

  render() {
    const r = this.root;
    r.textContent = '';
    if (!this.ed.doc) {
      r.appendChild(p('empty', 'No project is open.'));
      return;
    }

    const nodes = this.ed.selectedNodes();
    const links = this.ed.selectedLinks();
    const scopeId = [...this.ed.selection].find((id) => id.startsWith('sc-'));

    if (nodes.length === 1 && !links.length) return this.node(nodes[0]);
    if (links.length === 1 && !nodes.length) return this.link(links[0]);
    if (scopeId) return this.scope(this.ed.scope(scopeId));
    if (nodes.length + links.length > 1) return this.many(nodes, links);
    return this.project();
  }

  // -------------------------------------------------------------- project

  project() {
    const t = this.ed.doc.topology;
    this.root.appendChild(h2(t.name));
    this.root.appendChild(
      p(
        'empty',
        [
          plural(t.nodes.length, 'node'),
          plural(t.links.length, 'link'),
          plural(t.scopes.length, 'scope'),
        ].join(', '),
      ),
    );
    this.root.appendChild(h3('Rename the project'));
    this.root.appendChild(
      field('The name every container this sandbox creates is labelled with', textInput(t.name, (v) => {
        if (v && v !== t.name) this.ed.run({ op: 'set_project_name', name: v });
      })),
    );
    this.root.appendChild(h3('Scopes'));
    for (const s of t.scopes) {
      const row = document.createElement('div');
      row.className = 'scope-row';
      row.innerHTML = `<span>${escape(s.name)}</span><span class="sub">AS ${s.asn} ${escape(
        s.subnet,
      )}</span>`;
      row.onclick = () => this.ed.select(s.id);
      this.root.appendChild(row);
    }
  }

  // ----------------------------------------------------------------- node

  node(node) {
    const r = this.root;
    r.appendChild(h2(node.name));
    const scope = this.ed.scope(node.scope);
    r.appendChild(
      p('empty', `container ${scope ? scope.asn : '?'}_SBX_${node.name}`),
    );

    r.appendChild(field('Name', textInput(node.name, (v) => {
      if (v && v !== node.name) this.ed.run({ op: 'rename_node', node: node.id, name: v });
    })));

    r.appendChild(
      field(
        'Built from',
        select(
          this.ed.presets.map((x) => [x.name, `${x.name}  ${x.summary}`]),
          node.preset,
          (v) => this.ed.run({ op: 'set_node_preset', node: node.id, preset: v }),
        ),
      ),
    );

    r.appendChild(
      field(
        'Drawn as',
        select(
          ['router', 'switch', 'attacker', 'victim', 'server', 'host'].map((x) => [x, x]),
          node.role,
          (v) => this.ed.run({ op: 'set_node_role', node: node.id, role: v }),
        ),
      ),
    );

    r.appendChild(
      field(
        'Scope',
        select(
          this.ed.doc.topology.scopes.map((s) => [s.id, `${s.name} (AS ${s.asn})`]),
          node.scope,
          (v) => this.ed.run({ op: 'set_node_scope', node: node.id, scope: v }),
        ),
      ),
    );

    const legend = node.legend || node.extra?.legend || '';
    r.appendChild(
      field(
        'Figure label',
        textInput(legend, (v) => this.ed.run({ op: 'set_node_legend', node: node.id, legend: v })),
      ),
    );

    r.appendChild(h3('Interfaces'));
    for (const iface of node.interfaces || []) r.appendChild(this.iface(node, iface));

    const add = button('Add an interface', () =>
      this.ed.run({ op: 'add_interface', node: node.id }),
    );
    r.appendChild(add);

    r.appendChild(this.advanced(node));

    const del = button('Delete this node', () =>
      this.ed.run({ op: 'delete_nodes', nodes: [node.id] }),
    );
    del.className = 'danger';
    del.style.marginTop = '14px';
    r.appendChild(del);
  }

  iface(node, iface) {
    const box = document.createElement('div');
    box.className = 'iface';

    const name = derivedValue(iface.name) || '';
    const namePinned = isPinned(iface.name);
    const head = document.createElement('div');
    head.className = 'head';
    head.innerHTML = `<code>${escape(name)}</code>`;
    head.appendChild(
      pinToggle(namePinned, () =>
        namePinned
          ? this.ed.run({ op: 'unpin_if_name', iface: iface.id })
          : this.ed.run({ op: 'pin_if_name', iface: iface.id, name }),
      ),
    );
    box.appendChild(head);

    if (namePinned) {
      box.appendChild(
        field(
          'Name inside the container',
          textInput(name, (v) => this.ed.run({ op: 'pin_if_name', iface: iface.id, name: v }), true),
        ),
      );
    }

    const ip = derivedValue(iface.ip);
    const ipPinned = isPinned(iface.ip);
    const ipField = field(
      ipPinned ? 'Address (pinned)' : 'Address (from the scope plan)',
      textInput(
        ip || '',
        (v) => {
          if (!v) {
            if (ipPinned) this.ed.run({ op: 'unpin_ip', iface: iface.id });
            return;
          }
          this.ed.run({ op: 'pin_ip', iface: iface.id, ip: v });
        },
        true,
      ),
    );
    box.appendChild(ipField);
    if (ipPinned) {
      box.appendChild(
        button('Let the plan set this address', () =>
          this.ed.run({ op: 'unpin_ip', iface: iface.id }),
        ),
      );
    }

    // VLAN configuration is a switch-port property, so it is offered where it
    // means something and hidden where it does not.
    if (node.role === 'switch') {
      const current = iface.vlan
        ? Object.keys(iface.vlan)[0] === 'access'
          ? 'access'
          : 'trunk'
        : 'none';
      box.appendChild(
        field(
          'Port mode',
          select(
            [
              ['none', 'unset'],
              ['access', 'access port'],
              ['trunk', 'trunk port'],
            ],
            current,
            (v) => {
              if (v === 'none') return this.ed.run({ op: 'set_vlan', iface: iface.id, vlan: null });
              if (v === 'access') {
                return this.ed.run({
                  op: 'set_vlan',
                  iface: iface.id,
                  vlan: { access: { vlan: 1 } },
                });
              }
              return this.ed.run({
                op: 'set_vlan',
                iface: iface.id,
                vlan: { trunk: { vlans: [1], native: null } },
              });
            },
          ),
        ),
      );
      if (iface.vlan?.access) {
        box.appendChild(
          field(
            'VLAN',
            numberInput(iface.vlan.access.vlan, (v) =>
              this.ed.run({ op: 'set_vlan', iface: iface.id, vlan: { access: { vlan: v } } }),
            ),
          ),
        );
      }
      if (iface.vlan?.trunk) {
        box.appendChild(
          field(
            'VLANs carried, comma separated',
            textInput(iface.vlan.trunk.vlans.join(', '), (v) =>
              this.ed.run({
                op: 'set_vlan',
                iface: iface.id,
                vlan: {
                  trunk: { vlans: numbers(v), native: iface.vlan.trunk.native ?? null },
                },
              }),
            ),
          ),
        );
        box.appendChild(
          field(
            'Native VLAN, carried untagged',
            textInput(
              iface.vlan.trunk.native ?? '',
              (v) =>
                this.ed.run({
                  op: 'set_vlan',
                  iface: iface.id,
                  vlan: {
                    trunk: {
                      vlans: iface.vlan.trunk.vlans,
                      native: v === '' ? null : Number(v),
                    },
                  },
                }),
            ),
          ),
        );
      }
    }

    // A border port is what a link from outside lands on when this scope is
    // drawn collapsed, and the only thing that survives a pull from a blueprint.
    if (iface.external) {
      box.appendChild(
        field(
          'Border port',
          textInput(iface.external, (v) =>
            v
              ? this.ed.run({ op: 'promote_interface', iface: iface.id, name: v })
              : this.ed.run({ op: 'demote_interface', iface: iface.id }),
          ),
        ),
      );
      box.appendChild(
        button('Stop this being a border port', () =>
          this.ed.run({ op: 'demote_interface', iface: iface.id }),
        ),
      );
    } else {
      box.appendChild(
        button('Make this a border port', () =>
          this.ed.run({
            op: 'promote_interface',
            iface: iface.id,
            name: derivedValue(iface.name) || 'port',
          }),
        ),
      );
    }

    const del = button('Delete', () => this.ed.run({ op: 'delete_interface', iface: iface.id }));
    del.className = 'danger';
    box.appendChild(del);
    return box;
  }

  advanced(node) {
    const raw = node.raw || {};
    const d = document.createElement('details');
    d.className = 'advanced';
    const s = document.createElement('summary');
    s.textContent = 'Advanced: what no preset expresses';
    d.appendChild(s);

    const state = {
      image: raw.image || '',
      run_args: (raw.run_args || []).join(' '),
      cap_add: (raw.cap_add || []).join(', '),
      packages: (raw.packages || []).join(', '),
      sysctls: Object.entries(raw.sysctls || {})
        .map(([k, v]) => `${k}=${v}`)
        .join('\n'),
      init_script: raw.init_script || '',
    };

    const push = () => {
      const sysctls = {};
      for (const line of state.sysctls.split('\n')) {
        const [k, ...rest] = line.split('=');
        if (k.trim() && rest.length) sysctls[k.trim()] = rest.join('=').trim();
      }
      this.ed.run({
        op: 'set_raw',
        node: node.id,
        raw: {
          image: state.image.trim() || null,
          run_args: words(state.run_args),
          cap_add: list(state.cap_add),
          packages: list(state.packages),
          sysctls,
          init_script: state.init_script.trim() || null,
        },
      });
    };

    d.appendChild(
      field('Image, instead of the preset’s', textInput(state.image, (v) => {
        state.image = v;
        push();
      })),
    );
    d.appendChild(
      field('docker run arguments', textInput(state.run_args, (v) => {
        state.run_args = v;
        push();
      }, true)),
    );
    d.appendChild(
      field('Capabilities to add', textInput(state.cap_add, (v) => {
        state.cap_add = v;
        push();
      }, true)),
    );
    d.appendChild(
      field('Extra packages', textInput(state.packages, (v) => {
        state.packages = v;
        push();
      })),
    );
    d.appendChild(
      field('Sysctls, one key=value per line', textArea(state.sysctls, (v) => {
        state.sysctls = v;
        push();
      })),
    );
    d.appendChild(
      field(
        'Init script, run at spawn and again on reset',
        textArea(state.init_script, (v) => {
          state.init_script = v;
          push();
        }),
      ),
    );
    return d;
  }

  // ----------------------------------------------------------------- link

  link(link) {
    const r = this.root;
    const a = this.ed.iface(link.a);
    const b = this.ed.iface(link.b);
    r.appendChild(h2('Link'));
    r.appendChild(
      p(
        'empty',
        `${a ? a.node.name : '?'} ↔ ${b ? b.node.name : '?'}`,
      ),
    );

    const kind = linkKind(link);
    r.appendChild(
      field(
        'Kind',
        select(
          [
            ['l2', 'L2 attachment, through a switch'],
            ['l3p2p', 'routed point to point'],
            ['trunk', '802.1Q trunk'],
          ],
          kind,
          (v) => {
            const value =
              v === 'trunk'
                ? { trunk: { vlans: link.kind?.trunk?.vlans || [1] } }
                : v;
            this.ed.run({ op: 'set_link_kind', link: link.id, kind: value });
          },
        ),
      ),
    );

    if (kind === 'trunk') {
      r.appendChild(
        field(
          'VLANs carried, comma separated',
          textInput((link.kind.trunk.vlans || []).join(', '), (v) =>
            this.ed.run({ op: 'set_link_kind', link: link.id, kind: { trunk: { vlans: numbers(v) } } }),
          ),
        ),
      );
    }

    const del = button('Delete this link', () =>
      this.ed.run({ op: 'delete_links', links: [link.id] }),
    );
    del.className = 'danger';
    del.style.marginTop = '14px';
    r.appendChild(del);
  }

  // ---------------------------------------------------------------- scope

  scope(scope) {
    if (!scope) return;
    const r = this.root;
    r.appendChild(h2(`Scope ${scope.name}`));
    r.appendChild(
      p('empty', 'A scope is one AS number, one subnet, and the plan that fills it.'),
    );

    const patch = (fields) => this.ed.run({ op: 'update_scope', scope: scope.id, ...fields });

    r.appendChild(field('Name', textInput(scope.name, (v) => patch({ name: v }))));
    r.appendChild(field('AS number', numberInput(scope.asn, (v) => patch({ asn: v }))));
    r.appendChild(field('Subnet', textInput(scope.subnet, (v) => patch({ subnet: v }), true)));
    r.appendChild(
      field(
        'Address plan',
        textInput(scope.address_plan?.template || '', (v) => patch({ template: v }), true),
      ),
    );
    r.appendChild(
      p('empty', 'The bindings are {asn}, {site}, {link}, {host} and {index}. The subnet is the authority: a template that can render outside it is refused.'),
    );
    r.appendChild(
      field(
        'Prefix length on each address',
        numberInput(scope.address_plan?.prefix_len || 24, (v) => patch({ prefix_len: v })),
      ),
    );
    const pool = scope.host_pool || { start: 10, end: 250 };
    const row = document.createElement('div');
    row.className = 'row';
    row.appendChild(
      field('Pool from', numberInput(pool.start, (v) => patch({ pool: [v, pool.end] }))),
    );
    row.appendChild(
      field('to', numberInput(pool.end, (v) => patch({ pool: [pool.start, v] }))),
    );
    r.appendChild(row);

    if (scope.reservations?.length) {
      r.appendChild(h3('Reserved'));
      r.appendChild(p('empty', scope.reservations.join(', ')));
    }

    const renumber = button('Renumber this scope', () => this.ui.renumberDialog(scope));
    renumber.style.marginTop = '12px';
    r.appendChild(renumber);

    r.appendChild(h3('On the canvas'));
    const collapsed = this.ed.isCollapsed(scope.id);
    const view = document.createElement('div');
    view.className = 'row';
    view.appendChild(
      button(collapsed ? 'Open it up' : 'Draw it as one node', () =>
        this.ed.run({ op: 'set_collapsed', scope: scope.id, collapsed: !collapsed }),
      ),
    );
    view.appendChild(
      button('Look inside', () => this.ui.focusScope(scope.id)),
    );
    r.appendChild(view);
    const ports = this.ed
      .nodesInScope(scope.id)
      .flatMap((n) => (n.interfaces || []).filter((i) => i.external).map((i) => `${i.external} (${n.name})`));
    r.appendChild(
      p(
        'empty',
        ports.length
          ? `Border ports: ${ports.join(', ')}`
          : 'No border ports. A link from outside has nowhere defined to land while this scope is collapsed, and a pull from a blueprint would drop it.',
      ),
    );

    this.blueprintSection(scope);
  }

  /// What this scope is to its blueprint, if it came from one.
  blueprintSection(scope) {
    const r = this.root;
    r.appendChild(h3('Blueprint'));
    const drift = this.ed.divergenceOf(scope.id);

    if (!scope.blueprint) {
      r.appendChild(
        p('empty', 'This scope is its own drawing. Saving it as a blueprint lets you add it again with different parameters.'),
      );
      r.appendChild(button('Save as a blueprint', () => this.ui.saveBlueprint(scope)));
      return;
    }

    const bound = Object.entries(scope.blueprint.params || {})
      .map(([k, v]) => `${k}=${v}`)
      .join('  ');
    r.appendChild(p('empty', `From ${scope.blueprint.name}${bound ? `  ${bound}` : ''}`));

    if (drift) {
      const badge = document.createElement('div');
      badge.className = drift.clean ? 'empty' : 'badge warn';
      badge.textContent = drift.summary;
      badge.style.display = 'inline-block';
      badge.style.marginBottom = '8px';
      r.appendChild(badge);
    }

    const row = document.createElement('div');
    row.className = 'row';
    row.appendChild(button('What differs', () => this.ui.blueprintDiff(scope)));
    row.appendChild(button('Take the blueprint', () => this.ui.pullBlueprint(scope)));
    r.appendChild(row);
    const row2 = document.createElement('div');
    row2.className = 'row';
    row2.appendChild(button('Write this back', () => this.ui.pushBlueprint(scope)));
    row2.appendChild(
      button('Detach', () => this.ed.run({ op: 'detach_from_blueprint', scope: scope.id })),
    );
    r.appendChild(row2);
  }

  // ------------------------------------------------------------ many things

  many(nodes, links) {
    const r = this.root;
    r.appendChild(h2(`${nodes.length + links.length} selected`));
    r.appendChild(p('empty', nodes.map((n) => n.name).join(', ')));

    if (nodes.length > 1) {
      r.appendChild(h3('Scope'));
      r.appendChild(
        p('empty', 'An AS is a scope: one address plan, one numbering domain, and the prefix every container name in it carries.'),
      );
      const group = button('Group these into a new scope', () =>
        this.ui.groupIntoScope(nodes.map((n) => n.id)),
      );
      r.appendChild(group);

      r.appendChild(h3('Align'));
      const row = document.createElement('div');
      row.className = 'row';
      row.appendChild(button('Left', () => this.align(nodes, 'left')));
      row.appendChild(button('Middle', () => this.align(nodes, 'middle')));
      row.appendChild(button('Top', () => this.align(nodes, 'top')));
      r.appendChild(row);
      const row2 = document.createElement('div');
      row2.className = 'row';
      row2.appendChild(button('Spread across', () => this.distribute(nodes, 0)));
      row2.appendChild(button('Spread down', () => this.distribute(nodes, 1)));
      r.appendChild(row2);
    }

    const del = button('Delete the selection', () => {
      const cmds = [];
      if (links.length) cmds.push({ op: 'delete_links', links: links.map((l) => l.id) });
      if (nodes.length) cmds.push({ op: 'delete_nodes', nodes: nodes.map((n) => n.id) });
      this.ed.run(cmds, { label: 'delete the selection' });
    });
    del.className = 'danger';
    del.style.marginTop = '14px';
    r.appendChild(del);
  }

  align(nodes, how) {
    const pts = nodes.map((n) => this.ed.position(n.id) || [0, 0]);
    const positions = nodes.map((n, i) => {
      const [x, y] = pts[i];
      if (how === 'left') return [n.id, [Math.min(...pts.map((p) => p[0])), y]];
      if (how === 'middle') {
        return [n.id, [pts.reduce((a, p) => a + p[0], 0) / pts.length, y]];
      }
      return [n.id, [x, Math.min(...pts.map((p) => p[1]))]];
    });
    this.ed.run({ op: 'move_nodes', positions }, { label: 'align' });
  }

  distribute(nodes, axis) {
    const withPos = nodes.map((n) => ({ n, p: this.ed.position(n.id) || [0, 0] }));
    withPos.sort((a, b) => a.p[axis] - b.p[axis]);
    const first = withPos[0].p[axis];
    const last = withPos[withPos.length - 1].p[axis];
    const step = withPos.length > 1 ? (last - first) / (withPos.length - 1) : 0;
    const positions = withPos.map((item, i) => {
      const p = [...item.p];
      p[axis] = first + step * i;
      return [item.n.id, p];
    });
    this.ed.run({ op: 'move_nodes', positions }, { label: 'spread' });
  }
}

// ------------------------------------------------------------------ helpers

function h2(text) {
  const e = document.createElement('h2');
  e.textContent = text;
  return e;
}

function h3(text) {
  const e = document.createElement('h3');
  e.textContent = text;
  return e;
}

function p(cls, text) {
  const e = document.createElement('p');
  e.className = cls;
  e.textContent = text;
  return e;
}

function field(label, control) {
  const wrap = document.createElement('div');
  wrap.className = 'field';
  const l = document.createElement('label');
  l.textContent = label;
  wrap.appendChild(l);
  wrap.appendChild(control);
  return wrap;
}

/// A text field that commits on blur or Enter, never on every keystroke.
///
/// Every commit is a command and a command is an undo step, so committing per
/// keystroke would make one rename into eleven of them.
function textInput(value, onCommit, mono = false) {
  const e = document.createElement('input');
  e.type = 'text';
  e.value = value ?? '';
  if (mono) e.className = 'mono';
  const commit = () => {
    if (e.value !== (value ?? '')) onCommit(e.value.trim());
  };
  e.addEventListener('blur', commit);
  e.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter') {
      ev.preventDefault();
      e.blur();
    }
    if (ev.key === 'Escape') {
      e.value = value ?? '';
      e.blur();
    }
    ev.stopPropagation();
  });
  return e;
}

function numberInput(value, onCommit) {
  const e = document.createElement('input');
  e.type = 'number';
  e.value = value ?? 0;
  e.addEventListener('blur', () => {
    const v = Number(e.value);
    if (!Number.isNaN(v) && v !== value) onCommit(v);
  });
  e.addEventListener('keydown', (ev) => {
    if (ev.key === 'Enter') e.blur();
    ev.stopPropagation();
  });
  return e;
}

function textArea(value, onCommit) {
  const e = document.createElement('textarea');
  e.value = value ?? '';
  e.addEventListener('blur', () => {
    if (e.value !== (value ?? '')) onCommit(e.value);
  });
  e.addEventListener('keydown', (ev) => ev.stopPropagation());
  return e;
}

function select(options, current, onChange) {
  const e = document.createElement('select');
  for (const [value, label] of options) {
    const o = document.createElement('option');
    o.value = value;
    o.textContent = label;
    if (value === current) o.selected = true;
    e.appendChild(o);
  }
  e.addEventListener('change', () => onChange(e.value));
  return e;
}

function button(label, onClick) {
  const e = document.createElement('button');
  e.textContent = label;
  e.addEventListener('click', onClick);
  return e;
}

function pinToggle(on, onClick) {
  const e = document.createElement('button');
  e.className = `pin${on ? ' on' : ''}`;
  e.textContent = on ? 'pinned' : 'derived';
  e.title = on
    ? 'Fixed by you. A renumber leaves it alone.'
    : 'Computed from the plan. A renumber moves it.';
  e.addEventListener('click', onClick);
  return e;
}

function plural(n, word) {
  return `${n} ${word}${n === 1 ? '' : 's'}`;
}

function words(s) {
  return s.split(/\s+/).filter(Boolean);
}

function list(s) {
  return s.split(',').map((x) => x.trim()).filter(Boolean);
}

function numbers(s) {
  return s
    .split(',')
    .map((x) => Number(x.trim()))
    .filter((x) => Number.isFinite(x) && x > 0);
}

function escape(s) {
  return String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
}
