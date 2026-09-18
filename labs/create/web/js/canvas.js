// The canvas: SVG, drawn from the document, with the gestures that edit it.
//
// The drawing deliberately matches `labs/tools/topofig.py`: the same six roles,
// the same shape per role, the same stroke colour per role. A user who draws a
// topology here and then reads the figure in a handout should recognise the same
// picture, and shape carrying the role a second time is what keeps that true on
// a greyscale printout.
//
// Edges are routed orthogonally. Ports sit on the side of a node that faces
// their peer, which is what makes an orthogonal route read as a cable rather
// than as a diagonal with corners in it.

import { derivedValue } from './doc.js';

const SVG = 'http://www.w3.org/2000/svg';

/** Shape and stroke per role: topofig.py's own table. */
const ROLE = {
  router: { shape: 'ellipse', stroke: '#2a78d6' },
  switch: { shape: 'roundrect', stroke: '#1baf7a' },
  attacker: { shape: 'rect', stroke: '#e34948' },
  victim: { shape: 'rect', stroke: '#eda100' },
  server: { shape: 'rect', stroke: '#4a3aa7' },
  host: { shape: 'rect', stroke: '#52514e' },
};

const NODE_H = 40;
const MIN_W = 76;
const SCOPE_H = 64;
const SCOPE_MIN_W = 150;
const CHAR_W = 8.2;
const STUB = 18;      // how far a link leaves a port before it turns
const PORT_R = 5;

export class Canvas {
  constructor(svg, editor) {
    this.svg = svg;
    this.ed = editor;
    this.view = { x: 0, y: 0, scale: 1 };
    this.drag = null;
    this.onRequestLink = () => {};
    this.onOpenNode = () => {};
    this.onOpenScope = () => {};
    this.onDropOnScope = () => {};
    this.bind();
  }

  // -------------------------------------------------------------- geometry

  nodeBox(node) {
    const pos = this.ed.position(node.id) || [480, 200];
    const w = Math.max(MIN_W, node.name.length * CHAR_W + 26);
    return { x: pos[0], y: pos[1], w, h: NODE_H };
  }

  /// The box a collapsed scope draws as: one node, with its promoted border
  /// ports as the handles a link from outside lands on.
  scopeBox(scope) {
    const pos = this.ed.scopePosition(scope.id) || [480, 200];
    const label = `${scope.name}  AS ${scope.asn}`;
    const w = Math.max(SCOPE_MIN_W, label.length * CHAR_W + 30);
    return { x: pos[0], y: pos[1], w, h: SCOPE_H };
  }

  /// What is drawn for a given topology object: itself, or the collapsed scope
  /// standing in for it.
  ///
  /// Everything downstream asks this rather than looking at the node, which is
  /// what lets one routing and one hit-testing path serve both.
  entityOfNode(node) {
    if (!node) return null;
    if (this.ed.focus !== node.scope && this.ed.isCollapsed(node.scope)) {
      const scope = this.ed.scope(node.scope);
      return scope ? { type: 'scope', id: scope.id, scope } : null;
    }
    return { type: 'node', id: node.id, node };
  }

  boxOf(entity) {
    return entity.type === 'scope' ? this.scopeBox(entity.scope) : this.nodeBox(entity.node);
  }

  /// Every interface an entity shows a handle for.
  ///
  /// For a node that is all of them. For a collapsed scope it is the promoted
  /// border ports, plus any interface inside it that a link from outside already
  /// lands on: a link that exists has to be drawn, whether or not its landing
  /// point was ever named.
  interfacesOf(entity) {
    if (entity.type === 'node') return entity.node.interfaces || [];
    const inside = this.ed.nodesInScope(entity.id);
    const out = [];
    for (const n of inside) {
      for (const i of n.interfaces || []) {
        const peer = this.peerOf(i.id);
        const crosses = peer && peer.node.scope !== entity.id;
        if (i.external || crosses) out.push(i);
      }
    }
    return out;
  }

  /// Where each interface sits on its entity's border.
  ///
  /// A port faces its peer: the side is whichever axis the peer is further along,
  /// so a link between two nodes side by side leaves the right edge of one and
  /// enters the left edge of the other and the route between them is a straight
  /// horizontal line. Ports with no link yet are spread along the bottom, where
  /// they read as "nothing is plugged in here".
  ports(entity) {
    const box = this.boxOf(entity);
    const sides = { left: [], right: [], top: [], bottom: [] };
    for (const i of this.interfacesOf(entity)) {
      const peer = this.peerOf(i.id);
      const peerEntity = peer ? this.entityOfNode(peer.node) : null;
      // A link that does not leave the entity has no side to face: both ends are
      // inside one collapsed scope, and neither is drawn.
      if (!peerEntity || peerEntity.id === entity.id) {
        sides.bottom.push({ iface: i, peer: null });
        continue;
      }
      const pbox = this.boxOf(peerEntity);
      const dx = pbox.x - box.x;
      const dy = pbox.y - box.y;
      const side =
        Math.abs(dx) >= Math.abs(dy) ? (dx >= 0 ? 'right' : 'left') : dy >= 0 ? 'bottom' : 'top';
      sides[side].push({ iface: i, peer });
    }

    const out = [];
    for (const [side, list] of Object.entries(sides)) {
      list.forEach((entry, k) => {
        const t = (k + 1) / (list.length + 1);
        let x = box.x;
        let y = box.y;
        let dir = [0, 0];
        if (side === 'left') {
          x = box.x - box.w / 2;
          y = box.y - box.h / 2 + t * box.h;
          dir = [-1, 0];
        } else if (side === 'right') {
          x = box.x + box.w / 2;
          y = box.y - box.h / 2 + t * box.h;
          dir = [1, 0];
        } else if (side === 'top') {
          x = box.x - box.w / 2 + t * box.w;
          y = box.y - box.h / 2;
          dir = [0, -1];
        } else {
          x = box.x - box.w / 2 + t * box.w;
          y = box.y + box.h / 2;
          dir = [0, 1];
        }
        out.push({ iface: entry.iface, entity, x, y, dir, side, slot: k });
      });
    }
    return out;
  }

  /// The node and interface at the other end of an interface's link.
  peerOf(ifaceId) {
    const link = (this.ed.doc?.topology.links || []).find(
      (l) => l.a === ifaceId || l.b === ifaceId,
    );
    if (!link) return null;
    const otherId = link.a === ifaceId ? link.b : link.a;
    const found = this.ed.iface(otherId);
    return found ? { ...found, link } : null;
  }

  portOf(ifaceId) {
    const found = this.ed.iface(ifaceId);
    if (!found) return null;
    const entity = this.entityOfNode(found.node);
    if (!entity) return null;
    return this.ports(entity).find((p) => p.iface.id === ifaceId) || null;
  }

  /// An orthogonal route between two ports: out along each port's own direction,
  /// then one turn, then in. The middle segment is placed on whichever axis the
  /// two stubs leave room for, so the path never crosses back over a node it
  /// just left.
  route(a, b) {
    const a1 = [a.x + a.dir[0] * STUB, a.y + a.dir[1] * STUB];
    const b1 = [b.x + b.dir[0] * STUB, b.y + b.dir[1] * STUB];
    const pts = [[a.x, a.y], a1];
    const horizontalFirst = a.dir[0] !== 0;
    if (a1[0] !== b1[0] || a1[1] !== b1[1]) {
      if (horizontalFirst && b.dir[0] !== 0) {
        const mx = (a1[0] + b1[0]) / 2;
        pts.push([mx, a1[1]], [mx, b1[1]]);
      } else if (!horizontalFirst && b.dir[1] !== 0) {
        const my = (a1[1] + b1[1]) / 2;
        pts.push([a1[0], my], [b1[0], my]);
      } else if (horizontalFirst) {
        pts.push([b1[0], a1[1]]);
      } else {
        pts.push([a1[0], b1[1]]);
      }
    }
    pts.push(b1, [b.x, b.y]);
    return pts;
  }

  // --------------------------------------------------------------- drawing

  render() {
    const doc = this.ed.doc;
    this.svg.textContent = '';
    if (!doc) return;

    const root = el('g', { id: 'viewport' });
    this.svg.appendChild(root);
    this.applyView();

    const linksLayer = el('g', {});
    const nodesLayer = el('g', {});
    root.appendChild(linksLayer);
    root.appendChild(nodesLayer);
    this.root = root;

    // What is on the page: every node that is neither inside a collapsed scope
    // nor outside the one being looked at, plus a box per collapsed scope.
    const focus = this.ed.focus;
    const visibleNodes = doc.topology.nodes.filter((n) => {
      if (focus) return n.scope === focus;
      return !this.ed.isCollapsed(n.scope);
    });
    const visibleScopes = focus
      ? []
      : doc.topology.scopes.filter((s) => this.ed.isCollapsed(s.id));

    for (const link of doc.topology.links) this.drawLink(linksLayer, link);
    for (const scope of visibleScopes) this.drawScope(nodesLayer, scope);
    for (const node of visibleNodes) this.drawNode(nodesLayer, node);

    if (this.drag?.kind === 'rubber') this.drawRubber(root);
    if (this.drag?.kind === 'link') this.drawDraftLink(root);
  }

  drawNode(layer, node) {
    const box = this.nodeBox(node);
    const style = ROLE[node.role] || ROLE.host;
    const selected = this.ed.selection.has(node.id);
    const flagged = hasRaw(node);

    const g = el('g', {
      class: `node${selected ? ' selected' : ''}${flagged ? ' flagged' : ''}`,
      'data-node': node.id,
    });

    if (selected) {
      g.appendChild(
        el('rect', {
          class: 'halo',
          x: box.x - box.w / 2 - 7,
          y: box.y - box.h / 2 - 7,
          width: box.w + 14,
          height: box.h + 14,
          rx: 10,
        }),
      );
    }

    const fill = mixWithSurface(style.stroke);
    if (style.shape === 'ellipse') {
      g.appendChild(
        el('ellipse', {
          class: 'node-body',
          cx: box.x,
          cy: box.y,
          rx: box.w / 2,
          ry: box.h / 2,
          fill,
          stroke: style.stroke,
        }),
      );
    } else {
      g.appendChild(
        el('rect', {
          class: 'node-body',
          x: box.x - box.w / 2,
          y: box.y - box.h / 2,
          width: box.w,
          height: box.h,
          rx: style.shape === 'roundrect' ? 10 : 2,
          fill,
          stroke: style.stroke,
        }),
      );
    }

    g.appendChild(
      el('text', {
        class: 'node-label',
        x: box.x,
        y: box.y + 4,
        'text-anchor': 'middle',
        fill: 'currentColor',
      }, node.name),
    );

    const legend = node.legend || node.extra?.legend;
    if (legend) {
      g.appendChild(
        el('text', {
          class: 'node-legend',
          x: box.x,
          y: box.y + box.h / 2 + 13,
          'text-anchor': 'middle',
        }, legend),
      );
    }

    // A node carrying raw fields is marked, so a user can see at a glance which
    // nodes the generator did not fully author.
    if (flagged) {
      g.appendChild(
        el('text', {
          class: 'raw-mark',
          x: box.x + box.w / 2 - 7,
          y: box.y - box.h / 2 + 12,
          'text-anchor': 'middle',
        }, '!'),
      );
    }

    for (const port of this.ports({ type: 'node', id: node.id, node })) {
      const busy = this.ed.ifaceBusy(port.iface.id);
      const promoted = !!port.iface.external;
      g.appendChild(
        el('circle', {
          class: `port${busy ? ' taken' : ''}${promoted ? ' border' : ''}`,
          cx: port.x,
          cy: port.y,
          r: promoted ? PORT_R + 1.5 : PORT_R,
          'data-iface': port.iface.id,
          'data-node': node.id,
        }),
      );
      if (promoted) {
        g.appendChild(
          el('text', {
            class: 'port-label',
            x: port.x + port.dir[0] * 10,
            y: port.y + port.dir[1] * 14 - 8,
            'text-anchor': port.dir[0] < 0 ? 'end' : 'start',
          }, port.iface.external),
        );
      }
    }

    layer.appendChild(g);
  }

  /// A collapsed scope: one box, its promoted ports as handles.
  ///
  /// What the box is for is stated on it, because a collapsed scope hides the
  /// thing a user is looking for: the node count says how much is inside, and
  /// the AS number says what every container in it is named after.
  drawScope(layer, scope) {
    const box = this.scopeBox(scope);
    const selected = this.ed.selection.has(scope.id);
    const entity = { type: 'scope', id: scope.id, scope };
    const inside = this.ed.nodesInScope(scope.id);
    const drift = this.ed.divergenceOf(scope.id);

    const g = el('g', {
      class: `scope-node${selected ? ' selected' : ''}`,
      'data-scope': scope.id,
    });
    g.appendChild(
      el('rect', {
        class: 'scope-body',
        x: box.x - box.w / 2,
        y: box.y - box.h / 2,
        width: box.w,
        height: box.h,
        rx: 12,
      }),
    );
    g.appendChild(
      el('text', {
        class: 'node-label',
        x: box.x,
        y: box.y - 2,
        'text-anchor': 'middle',
        fill: 'currentColor',
      }, scope.name),
    );
    g.appendChild(
      el('text', {
        class: 'node-legend',
        x: box.x,
        y: box.y + 14,
        'text-anchor': 'middle',
      }, `AS ${scope.asn} · ${inside.length} node${inside.length === 1 ? '' : 's'}`),
    );
    if (drift && !drift.clean) {
      g.appendChild(
        el('text', {
          class: 'raw-mark',
          x: box.x + box.w / 2 - 9,
          y: box.y - box.h / 2 + 14,
          'text-anchor': 'middle',
        }, '≠'),
      );
    }

    for (const port of this.ports(entity)) {
      g.appendChild(
        el('circle', {
          class: `port${this.ed.ifaceBusy(port.iface.id) ? ' taken' : ''} border`,
          cx: port.x,
          cy: port.y,
          r: PORT_R + 1.5,
          'data-iface': port.iface.id,
          'data-scope': scope.id,
        }),
      );
      g.appendChild(
        el('text', {
          class: 'port-label',
          x: port.x + port.dir[0] * 10,
          y: port.y + port.dir[1] * 14 - 8,
          'text-anchor': port.dir[0] < 0 ? 'end' : 'start',
        }, port.iface.external || ''),
      );
    }

    layer.appendChild(g);
  }

  drawLink(layer, link) {
    // Inside a collapsed scope, or outside the scope being looked at: not drawn
    // as a link at all. A link that leaves the focused scope is drawn as a stub
    // labelled with its far end, so navigation never hides that it is there.
    const owners = [link.a, link.b].map((id) => this.ed.iface(id)?.node);
    if (!owners[0] || !owners[1]) return;
    const focus = this.ed.focus;
    if (focus) {
      const inside = owners.map((n) => n.scope === focus);
      if (!inside[0] && !inside[1]) return;
      if (inside[0] !== inside[1]) {
        this.drawStub(layer, link, inside[0] ? owners[0] : owners[1], inside[0] ? owners[1] : owners[0]);
        return;
      }
    } else if (
      owners[0].scope === owners[1].scope &&
      this.ed.isCollapsed(owners[0].scope)
    ) {
      return;
    }

    const a = this.portOf(link.a);
    const b = this.portOf(link.b);
    if (!a || !b) return;
    const pts = this.route(a, b);
    const d = pathOf(pts);
    const kind = linkKind(link);
    const selected = this.ed.selection.has(link.id);

    const g = el('g', { class: 'link-group', 'data-link': link.id });
    g.appendChild(el('path', { class: 'link-hit', d, 'data-link': link.id }));
    g.appendChild(
      el('path', { class: `link ${kind}${selected ? ' selected' : ''}`, d, 'data-link': link.id }),
    );

    // Each end's own label sits beside its own stub: the interface name, and the
    // address when it has one. This is the same pairing the figure prints, and
    // it is what makes an addressing mistake visible without opening anything.
    for (const port of [a, b]) {
      // A port on a collapsed scope already carries the border port's name,
      // drawn by the box itself. Printing the interface's name over it as well
      // puts two labels in one place and neither is readable.
      if (port.entity.type === 'scope') continue;
      const text = endLabel(port.iface);
      if (!text) continue;
      // Ports on the same side of a node stagger their labels, because a switch
      // with three ports along one edge otherwise prints three interface names
      // on top of each other and none of them is readable.
      const step = port.slot * 12;
      const vertical = port.dir[1] !== 0;
      const x = port.x + port.dir[0] * (STUB + 6) + (vertical ? 0 : 0);
      const y = port.y + (vertical ? port.dir[1] * (STUB + 12 + step) : -8 - step);
      g.appendChild(
        el('text', {
          class: 'link-label',
          x,
          y,
          'text-anchor': vertical ? 'middle' : port.dir[0] < 0 ? 'end' : 'start',
        }, text),
      );
    }

    if (kind === 'trunk') {
      const mid = pts[Math.floor(pts.length / 2)];
      const vlans = (link.kind?.trunk?.vlans || []).join(', ');
      g.appendChild(
        el('text', { class: 'link-label', x: mid[0] + 6, y: mid[1] - 6 }, `trunk ${vlans}`),
      );
    }

    layer.appendChild(g);
  }

  /// A link that leaves the scope being looked at, drawn as a short stub with
  /// the far end's name on it. Navigation, not a modal: what is out there stays
  /// visible even while it is not on the page.
  drawStub(layer, link, nearNode, farNode) {
    const nearIface = [link.a, link.b].find((id) => {
      const owner = this.ed.iface(id)?.node;
      return owner && owner.id === nearNode.id;
    });
    const port = nearIface ? this.portOf(nearIface) : null;
    if (!port) return;
    const end = [port.x + port.dir[0] * STUB * 2.4, port.y + port.dir[1] * STUB * 2.4];
    const g = el('g', { class: 'link-group', 'data-link': link.id });
    g.appendChild(el('path', { class: 'link-hit', d: pathOf([[port.x, port.y], end]), 'data-link': link.id }));
    g.appendChild(
      el('path', { class: `link ${linkKind(link)} stub`, d: pathOf([[port.x, port.y], end]) }),
    );
    const scope = this.ed.scope(farNode.scope);
    g.appendChild(
      el('text', {
        class: 'link-label',
        x: end[0] + (port.dir[0] === 0 ? 8 : port.dir[0] * 6),
        y: end[1] + (port.dir[1] === 0 ? -6 : port.dir[1] * 12),
        'text-anchor': port.dir[0] < 0 ? 'end' : 'start',
      }, `${farNode.name}${scope ? ` (${scope.name})` : ''}`),
    );
    layer.appendChild(g);
  }

  drawRubber(root) {
    const { from, to } = this.drag;
    root.appendChild(
      el('rect', {
        class: 'rubber',
        x: Math.min(from[0], to[0]),
        y: Math.min(from[1], to[1]),
        width: Math.abs(to[0] - from[0]),
        height: Math.abs(to[1] - from[1]),
      }),
    );
  }

  drawDraftLink(root) {
    const port = this.portOf(this.drag.ifaceId);
    if (!port) return;
    root.appendChild(
      el('path', { class: 'draft-link', d: pathOf([[port.x, port.y], this.drag.to]) }),
    );
  }

  // ---------------------------------------------------------------- events

  applyView() {
    const r = this.svg.getBoundingClientRect();
    const w = Math.max(1, r.width) / this.view.scale;
    const h = Math.max(1, r.height) / this.view.scale;
    this.svg.setAttribute('viewBox', `${this.view.x} ${this.view.y} ${w} ${h}`);
  }

  /// Canvas coordinates for a pointer event.
  point(ev) {
    const r = this.svg.getBoundingClientRect();
    return [
      this.view.x + (ev.clientX - r.left) / this.view.scale,
      this.view.y + (ev.clientY - r.top) / this.view.scale,
    ];
  }

  bind() {
    this.svg.addEventListener('pointerdown', (ev) => this.onDown(ev));
    window.addEventListener('pointermove', (ev) => this.onMove(ev));
    window.addEventListener('pointerup', (ev) => this.onUp(ev));
    this.svg.addEventListener('wheel', (ev) => this.onWheel(ev), { passive: false });
    this.svg.addEventListener('dblclick', (ev) => {
      const scope = ev.target.closest?.('.scope-node');
      if (scope) {
        this.onOpenScope(scope.dataset.scope);
        return;
      }
      const node = ev.target.closest?.('[data-node]');
      if (node) this.onOpenNode(node.dataset.node);
    });
    window.addEventListener('resize', () => this.applyView());
  }

  onDown(ev) {
    if (ev.button === 1 || ev.altKey) {
      this.drag = { kind: 'pan', from: [ev.clientX, ev.clientY], view: { ...this.view } };
      return;
    }
    if (ev.button !== 0) return;
    const at = this.point(ev);
    const portEl = ev.target.closest?.('.port');
    const nodeEl = ev.target.closest?.('.node');
    const scopeEl = ev.target.closest?.('.scope-node');
    const linkEl = ev.target.closest?.('[data-link]');

    if (portEl) {
      this.drag = { kind: 'link', ifaceId: portEl.dataset.iface, from: at, to: at };
      this.svg.classList.add('linking');
      this.render();
      return;
    }
    if (nodeEl) {
      const id = nodeEl.dataset.node;
      if (!this.ed.selection.has(id)) this.ed.select(id, { add: ev.shiftKey });
      const moving = this.ed.selectedNodes().map((n) => ({
        id: n.id,
        start: this.ed.position(n.id) || [at[0], at[1]],
      }));
      this.drag = { kind: 'move', from: at, moving, moved: false };
      return;
    }
    if (scopeEl) {
      const id = scopeEl.dataset.scope;
      this.ed.select(id, { add: ev.shiftKey });
      // A collapsed scope drags as one box, and the box's position is layout
      // state of its own: the nodes inside keep the positions they had, so
      // opening it again puts them back where they were.
      this.drag = {
        kind: 'move-scope',
        from: at,
        scope: id,
        start: this.ed.scopePosition(id) || [at[0], at[1]],
        moved: false,
      };
      this.render();
      return;
    }
    if (linkEl) {
      this.ed.select(linkEl.dataset.link, { add: ev.shiftKey });
      this.render();
      return;
    }
    this.drag = { kind: 'rubber', from: at, to: at, add: ev.shiftKey };
    if (!ev.shiftKey) this.ed.clearSelection();
    this.render();
  }

  onMove(ev) {
    if (!this.drag) return;
    if (this.drag.kind === 'pan') {
      const dx = (ev.clientX - this.drag.from[0]) / this.view.scale;
      const dy = (ev.clientY - this.drag.from[1]) / this.view.scale;
      this.view.x = this.drag.view.x - dx;
      this.view.y = this.drag.view.y - dy;
      this.applyView();
      return;
    }
    const at = this.point(ev);
    if (this.drag.kind === 'move-scope') {
      const dx = at[0] - this.drag.from[0];
      const dy = at[1] - this.drag.from[1];
      if (Math.abs(dx) > 1 || Math.abs(dy) > 1) this.drag.moved = true;
      this.ed.doc.layout.scope_positions[this.drag.scope] = [
        this.drag.start[0] + dx,
        this.drag.start[1] + dy,
      ];
      this.render();
      return;
    }
    if (this.drag.kind === 'move') {
      const dx = at[0] - this.drag.from[0];
      const dy = at[1] - this.drag.from[1];
      if (Math.abs(dx) > 1 || Math.abs(dy) > 1) this.drag.moved = true;
      // Moved locally while the pointer is down, and sent as one command on
      // release: a drag is one gesture and has to be one undo step.
      for (const m of this.drag.moving) {
        this.ed.doc.layout.positions[m.id] = [m.start[0] + dx, m.start[1] + dy];
      }
      this.render();
      return;
    }
    this.drag.to = at;
    this.render();
  }

  async onUp(ev) {
    const drag = this.drag;
    if (!drag) return;
    this.drag = null;
    this.svg.classList.remove('linking');

    // Where the pointer was released, not where it last moved. A release carries
    // its own position, and a drag whose final movement and release arrive
    // together would otherwise end at the second-to-last point: a node lands
    // short of where it was dropped, and a rubber band misses the row of nodes
    // the user finished over.
    if (drag.kind !== 'pan') {
      const at = this.point(ev);
      if (drag.kind === 'rubber') {
        drag.to = at;
      } else if (drag.kind === 'move') {
        const dx = at[0] - drag.from[0];
        const dy = at[1] - drag.from[1];
        if (Math.abs(dx) > 1 || Math.abs(dy) > 1) drag.moved = true;
        for (const m of drag.moving) {
          this.ed.doc.layout.positions[m.id] = [m.start[0] + dx, m.start[1] + dy];
        }
      } else if (drag.kind === 'move-scope') {
        const dx = at[0] - drag.from[0];
        const dy = at[1] - drag.from[1];
        if (Math.abs(dx) > 1 || Math.abs(dy) > 1) drag.moved = true;
        this.ed.doc.layout.scope_positions[drag.scope] = [
          drag.start[0] + dx,
          drag.start[1] + dy,
        ];
      }
    }

    if (drag.kind === 'move-scope') {
      if (drag.moved) {
        const at = this.ed.doc.layout.scope_positions[drag.scope];
        this.ed.doc.layout.scope_positions[drag.scope] = drag.start;
        await this.ed.run(
          { op: 'move_scope', scope: drag.scope, pos: at },
          { label: 'move a collapsed scope' },
        );
      }
      this.render();
      return;
    }

    if (drag.kind === 'move' && drag.moved) {
      const positions = drag.moving.map((m) => [m.id, this.ed.doc.layout.positions[m.id]]);
      // Put the layout back first, so the command that arrives is the whole move
      // rather than the tail of one already applied by hand.
      for (const m of drag.moving) this.ed.doc.layout.positions[m.id] = m.start;
      await this.ed.run({ op: 'move_nodes', positions }, { label: 'move' });
      this.render();
      return;
    }

    if (drag.kind === 'link') {
      const target = document.elementFromPoint(ev.clientX, ev.clientY);
      const portEl = target?.closest?.('.port');
      const nodeEl = target?.closest?.('.node');
      // Dropping on a node's body means "attach to this node" and lets the
      // server pick the interface. Dropping on a port names it.
      const scopeEl = target?.closest?.('.scope-node');
      if (portEl && portEl.dataset.iface !== drag.ifaceId) {
        // A port on a collapsed scope belongs to a node inside it, so the far
        // end is that node: the box is a drawing, and a link always lands on a
        // real interface.
        const owner = this.ed.iface(portEl.dataset.iface)?.node;
        this.onRequestLink(drag.ifaceId, owner ? owner.id : portEl.dataset.node, portEl.dataset.iface);
      } else if (nodeEl) {
        this.onRequestLink(drag.ifaceId, nodeEl.dataset.node, null);
      } else if (scopeEl) {
        // Dropped on the body of a collapsed scope rather than on one of its
        // ports. There is no defined landing point, which is exactly what
        // promoting an interface to a border port is for, so it is refused with
        // that as the reason rather than picked at random.
        this.onDropOnScope(scopeEl.dataset.scope);
        this.render();
      } else {
        this.render();
      }
      return;
    }

    if (drag.kind === 'rubber') {
      const x0 = Math.min(drag.from[0], drag.to[0]);
      const x1 = Math.max(drag.from[0], drag.to[0]);
      const y0 = Math.min(drag.from[1], drag.to[1]);
      const y1 = Math.max(drag.from[1], drag.to[1]);
      if (x1 - x0 > 3 || y1 - y0 > 3) {
        const inside = (this.ed.doc?.topology.nodes || [])
          .filter((n) => {
            const b = this.nodeBox(n);
            return b.x > x0 && b.x < x1 && b.y > y0 && b.y < y1;
          })
          .map((n) => n.id);
        this.ed.select(inside, { add: drag.add });
      }
      this.render();
    }
  }

  onWheel(ev) {
    ev.preventDefault();
    const at = this.point(ev);
    const factor = ev.deltaY < 0 ? 1.12 : 1 / 1.12;
    const next = Math.min(3, Math.max(0.25, this.view.scale * factor));
    // Zoom about the pointer, so the thing under the cursor stays under it.
    const r = this.svg.getBoundingClientRect();
    this.view.x = at[0] - (ev.clientX - r.left) / next;
    this.view.y = at[1] - (ev.clientY - r.top) / next;
    this.view.scale = next;
    this.applyView();
  }

  /// Put the whole topology in view, with a margin. Called after opening a
  /// project and after auto-layout.
  fit() {
    const focus = this.ed.focus;
    const nodes = (this.ed.doc?.topology.nodes || []).filter((n) =>
      focus ? n.scope === focus : !this.ed.isCollapsed(n.scope),
    );
    const scopes = focus
      ? []
      : (this.ed.doc?.topology.scopes || []).filter((s) => this.ed.isCollapsed(s.id));
    if (!nodes.length && !scopes.length) {
      this.view = { x: 0, y: 0, scale: 1 };
      this.applyView();
      return;
    }
    let x0 = Infinity;
    let y0 = Infinity;
    let x1 = -Infinity;
    let y1 = -Infinity;
    for (const b of [...nodes.map((n) => this.nodeBox(n)), ...scopes.map((s) => this.scopeBox(s))]) {
      x0 = Math.min(x0, b.x - b.w / 2);
      x1 = Math.max(x1, b.x + b.w / 2);
      y0 = Math.min(y0, b.y - b.h / 2);
      y1 = Math.max(y1, b.y + b.h / 2);
    }
    const pad = 90;
    const r = this.svg.getBoundingClientRect();
    const scale = Math.min(
      3,
      Math.max(0.25, Math.min(r.width / (x1 - x0 + pad * 2), r.height / (y1 - y0 + pad * 2))),
    );
    this.view.scale = scale;
    this.view.x = (x0 + x1) / 2 - r.width / (2 * scale);
    this.view.y = (y0 + y1) / 2 - r.height / (2 * scale);
    this.applyView();
  }

  /// Somewhere free to drop a new node: under everything already drawn, near the
  /// middle of what the user is looking at.
  freeSpot() {
    const r = this.svg.getBoundingClientRect();
    const cx = this.view.x + r.width / (2 * this.view.scale);
    const cy = this.view.y + r.height / (2 * this.view.scale);
    const taken = (this.ed.doc?.topology.nodes || []).map((n) => this.nodeBox(n));
    for (let ring = 0; ring < 12; ring += 1) {
      for (let k = 0; k < 8; k += 1) {
        const angle = (k / 8) * Math.PI * 2;
        const x = cx + Math.cos(angle) * ring * 110;
        const y = cy + Math.sin(angle) * ring * 80;
        if (!taken.some((b) => Math.abs(b.x - x) < 120 && Math.abs(b.y - y) < 70)) {
          return [Math.round(x), Math.round(y)];
        }
      }
    }
    return [Math.round(cx), Math.round(cy)];
  }
}

// ------------------------------------------------------------------ helpers

function el(name, attrs, text) {
  const node = document.createElementNS(SVG, name);
  for (const [k, v] of Object.entries(attrs || {})) node.setAttribute(k, String(v));
  if (text !== undefined) node.textContent = text;
  return node;
}

function pathOf(points) {
  return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p[0]},${p[1]}`).join(' ');
}

/// The fill is the stroke hue mixed into the page, which is the same rule the
/// figure uses: identity rides on the stroke and the shape, so the fill can stay
/// light enough for the label on top of it to keep its contrast in both themes.
function mixWithSurface(stroke) {
  return `color-mix(in srgb, ${stroke} 15%, var(--panel))`;
}

function linkKind(link) {
  if (typeof link.kind === 'string') return link.kind;
  if (link.kind && typeof link.kind === 'object') return Object.keys(link.kind)[0];
  return 'l2';
}

function hasRaw(node) {
  const raw = node.raw || {};
  return Boolean(
    raw.image ||
      raw.init_script ||
      (raw.run_args || []).length ||
      (raw.cap_add || []).length ||
      (raw.packages || []).length ||
      Object.keys(raw.sysctls || {}).length,
  );
}

function endLabel(iface) {
  const name = derivedValue(iface.name) || '';
  const ip = derivedValue(iface.ip);
  return ip ? `${name}  ${ip}` : name;
}

export { linkKind, hasRaw };
