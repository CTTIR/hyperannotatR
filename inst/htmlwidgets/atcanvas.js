// atcanvas: a self-contained HTML5 canvas widget for ROI annotation.
//
// No external libraries: this works fully offline. Each render embeds one
// downsampled base image (a PNG data URI built in R); there is no tile
// streaming, so band and view changes arrive as a new render from R.
//
// COORDINATE DISCIPLINE: the drawing space is the level-0 image pixel space
// (tileSource.width x tileSource.height). All coordinates emitted to R are
// level-0 image pixels; toImageCoords() is the single conversion point. Screen
// coordinates are CSS pixels relative to the canvas content box, and the
// backing store is scaled to device pixels, so drawn positions match pointer
// positions exactly on any display.
//
// EVENT PROTOCOL: every value sent to R is {entry_id, revision, payload},
// stamped with the identity rendered when the gesture began. A render with a
// different identity cancels unfinished gestures, and an event whose stamp no
// longer matches the rendered identity is never sent. Shapes drawn locally are
// provisional (dashed) until R answers with new annotations.

(function () {
  // Shiny stores one handler per message name, so route through live instances.
  var instances = Object.create(null), dispatcherShiny = null, observer = null;
  var methods = ["set_annotations", "set_tool", "set_band", "set_overlay", "fit_bounds",
                 "set_selection", "clear_overlay"];
  function registerDispatcher() {
    if (window.Shiny && dispatcherShiny !== window.Shiny) {
      dispatcherShiny = window.Shiny;
      methods.forEach(function (name) {
        Shiny.addCustomMessageHandler("atcanvas-" + name, function (m) {
          var instance = m && instances[m.id];
          if (instance) instance.message(name, m);
        });
      });
    }
    if (!observer && typeof MutationObserver !== "undefined") {
      observer = new MutationObserver(function () {
        Object.keys(instances).forEach(function (id) {
          if (!instances[id].el.isConnected) instances[id].dispose();
        });
      });
      observer.observe(document.documentElement, { childList: true, subtree: true });
    }
  }
  // Keyboard shortcuts read the identity of the app canvas actually rendered.
  window.atcanvasIdentity = function (id) {
    return instances[id] ? instances[id].identity() : null;
  };
  // Read-only snapshot of a mounted canvas, for tests and debugging.
  window.atcanvasInspect = function (id) {
    return instances[id] ? instances[id].inspect() : null;
  };

  var PENDING_MS = 5000;  // how long an unanswered local shape stays visible
  var CLICK_TOL = 3;      // screen px below which a drag counts as a click
  var CLOSE_TOL = 8;      // screen px: clicking near the first vertex closes
  var DBL_MS = 350;       // double-click / double-tap interval
  var timers = typeof setTimeout === "function";

  function toArray(v) {
    if (v === null || v === undefined) return [];
    return Array.isArray(v) ? v : [v];
  }

HTMLWidgets.widget({
  name: "atcanvas",
  type: "output",

  factory: function (el, width, height) {
    if (instances[el.id]) instances[el.id].dispose();
    var disposed = false, baseGeneration = 0, overlayGeneration = 0, listeners = [];
    var canvas = document.createElement("canvas");
    canvas.tabIndex = 0;
    canvas.setAttribute("aria-label", "Annotation canvas. Arrows move; Enter or Space draws; Escape cancels.");
    var status = document.createElement("div");
    status.setAttribute("role", "status"); status.setAttribute("aria-live", "polite");
    status.className = "atcanvas-status";
    el.appendChild(status);
    canvas.className = "atcanvas-canvas";
    canvas.style.width = "100%";
    canvas.style.height = "calc(100% - 1.5rem)";
    status.style.height = "1.5rem"; status.style.lineHeight = "1.5rem";
    status.style.overflow = "hidden"; status.style.whiteSpace = "nowrap";
    canvas.style.cursor = "grab";
    el.appendChild(canvas);
    var ctx = canvas.getContext("2d");

    var state = {
      imgW: 1, imgH: 1, baseImg: null, overlayImg: null, overlayAlpha: 0.5,
      zoom: 1, panX: 0, panY: 0, tool: "pan", viewW: 1, viewH: 1, scaleX: 1, scaleY: 1,
      features: [], drawing: null, selection: [], pending: [], ready: false, cursor: [0, 0],
      viewNote: null, pointRadius: 4, circleRadius: 0, suggestion: null
    };
    var inset = { l: 0, t: 0 };   // canvas border + padding (CSS px)
    var pendingTimer = null;

    // The canvas content box in CSS px (fractional): the box the backing store
    // is displayed in, excluding any border and padding of the canvas itself.
    function measure() {
      var r = canvas.getBoundingClientRect();
      var cs = window.getComputedStyle ? window.getComputedStyle(canvas) : null;
      var px = function (k) { var v = cs ? parseFloat(cs[k]) : 0; return isFinite(v) ? v : 0; };
      inset = { l: px("borderLeftWidth") + px("paddingLeft"), t: px("borderTopWidth") + px("paddingTop") };
      return {
        w: r.width - inset.l - px("borderRightWidth") - px("paddingRight"),
        h: r.height - inset.t - px("borderBottomWidth") - px("paddingBottom")
      };
    }

    function resize() {
      var m = measure();
      if (!(m.w > 0) || !(m.h > 0)) { state.needsFit = true; return; }
      var density = window.devicePixelRatio || 1;
      var bw = Math.max(1, Math.round(m.w * density)), bh = Math.max(1, Math.round(m.h * density));
      if (bw !== canvas.width || bh !== canvas.height || m.w !== state.viewW || m.h !== state.viewH) {
        // Keep the image point at the centre of the view in place.
        var c = state.needsFit ? null : toImageCoords(state.viewW / 2, state.viewH / 2);
        canvas.width = bw; canvas.height = bh;
        state.viewW = m.w; state.viewH = m.h;
        // The measured backing/CSS ratio, not a rounded devicePixelRatio.
        state.scaleX = bw / m.w; state.scaleY = bh / m.h;
        if (c) { state.panX = m.w / 2 - c[0] * state.zoom; state.panY = m.h / 2 - c[1] * state.zoom; }
      }
      if (state.needsFit) { state.needsFit = false; fitBounds(null); }
      render();
    }

    // Screen (canvas) pixel -> level-0 image pixel.
    function toImageCoords(sx, sy) {
      return [(sx - state.panX) / state.zoom, (sy - state.panY) / state.zoom];
    }
    // Level-0 image pixel -> screen pixel.
    function toScreen(ix, iy) {
      return [ix * state.zoom + state.panX, iy * state.zoom + state.panY];
    }
    // Event position in CSS px relative to the canvas content box.
    function localPoint(e) {
      var r = canvas.getBoundingClientRect();
      return [e.clientX - r.left - inset.l, e.clientY - r.top - inset.t];
    }

    function fitZoom() {
      return Math.min(state.viewW / Math.max(1, state.imgW), state.viewH / Math.max(1, state.imgH));
    }
    // From a quarter of the whole-image fit to 32 screen px per image pixel.
    function clampZoom(z) {
      var fit = fitZoom();
      if (!(fit > 0) || !isFinite(fit)) return z;
      return Math.min(Math.max(fit * 4, 32), Math.max(fit / 4, z));
    }

    function fitBounds(bbox) {
      var x0, y0, x1, y1;
      bbox = toArray(bbox);
      if (bbox.length === 4) { x0 = +bbox[0]; y0 = +bbox[1]; x1 = +bbox[2]; y1 = +bbox[3]; }
      else { x0 = 0; y0 = 0; x1 = state.imgW; y1 = state.imgH; }
      var bw = Math.max(1, x1 - x0), bh = Math.max(1, y1 - y0);
      state.zoom = clampZoom(Math.min(state.viewW / bw, state.viewH / bh));
      state.panX = -x0 * state.zoom + (state.viewW - bw * state.zoom) / 2;
      state.panY = -y0 * state.zoom + (state.viewH - bh * state.zoom) / 2;
      render();
    }

    // kind: "roi" (from R), "pending" (local, unanswered) or "draw" (in progress).
    function drawFeature(f, kind) {
      var props = f.properties || {};
      if (props.visible === false) return;
      var g = f.geometry;
      if (!g) return;
      ctx.beginPath();
      function point(c) {
        var p = toScreen(c[0], c[1]);
        var radius = markerRadius(props);
        ctx.moveTo(p[0] + radius, p[1]); ctx.arc(p[0], p[1], radius, 0, 2 * Math.PI);
      }
      function line(ring, close) {
        ring.forEach(function (c, i) {
          var p = toScreen(c[0], c[1]);
          if (i === 0) ctx.moveTo(p[0], p[1]); else ctx.lineTo(p[0], p[1]);
        });
        if (close) ctx.closePath();
      }
      function polygon(rings) { rings.forEach(function (ring) { line(ring, true); }); }
      if (g.type === "Point") point(g.coordinates);
      else if (g.type === "MultiPoint") g.coordinates.forEach(point);
      else if (g.type === "LineString") line(g.coordinates, false);
      else if (g.type === "MultiLineString") g.coordinates.forEach(function (l) { line(l, false); });
      else if (g.type === "Polygon") polygon(g.coordinates);
      else if (g.type === "MultiPolygon") g.coordinates.forEach(polygon);
      var provisional = kind !== "roi" || f._pending === true;
      var selected = kind === "roi" && props.roi_id !== undefined && state.selection.indexOf(props.roi_id) >= 0;
      var width = (kind === "roi" && props.stroke_width) || 2;
      ctx.lineWidth = selected ? Math.max(4, width + 2) : width;
      ctx.strokeStyle = kind !== "roi" ? "#5E2C8E" : (props.colour || "#E69F00");
      ctx.fillStyle = ctx.strokeStyle;
      ctx.globalAlpha = kind !== "roi" ? 0.15 : (typeof props.fill_alpha === "number" ? props.fill_alpha : 0.15);
      if (g.type === "Polygon" || g.type === "MultiPolygon") ctx.fill("evenodd");
      else if (g.type !== "LineString" && g.type !== "MultiLineString") ctx.fill();
      ctx.globalAlpha = 1;
      if (selected) ctx.strokeStyle = "#e3a008";
      if (provisional && ctx.setLineDash) ctx.setLineDash([6, 4]);
      ctx.stroke();
      if (provisional && ctx.setLineDash) ctx.setLineDash([]);
    }

    function render() {
      if (disposed) return;
      canvas.setAttribute("data-tool", state.tool);
      ctx.setTransform(state.scaleX, 0, 0, state.scaleY, 0, 0);
      ctx.clearRect(0, 0, state.viewW, state.viewH);
      var tl = toScreen(0, 0), sw = state.imgW * state.zoom, sh = state.imgH * state.zoom;
      if (state.baseImg) {
        var natural = state.baseImg.naturalWidth || state.baseImg.width || 0;
        // Magnified beyond one image pixel per device pixel: show crisp pixels.
        ctx.imageSmoothingEnabled = !(natural > 0) || sw * state.scaleX / natural < 1;
        ctx.drawImage(state.baseImg, tl[0], tl[1], sw, sh);
      }
      if (state.overlayImg) {
        ctx.imageSmoothingEnabled = false;  // class colours must not blend
        ctx.globalAlpha = state.overlayAlpha;
        ctx.drawImage(state.overlayImg, tl[0], tl[1], sw, sh);
        ctx.globalAlpha = 1;
      }
      ctx.imageSmoothingEnabled = true;
      if (!state.ready) return;
      state.features.forEach(function (f) { drawFeature(f, "roi"); });
      state.pending.forEach(function (f) { drawFeature(f, "pending"); });
      if (state.drawing) drawFeature(state.drawing, "draw");
      if (state.suggestion) drawFeature(state.suggestion, "draw");
      if (document.activeElement === canvas && state.keyboardCursor) {
        var cursor = toScreen(state.cursor[0], state.cursor[1]);
        ctx.beginPath(); ctx.moveTo(cursor[0]-6,cursor[1]); ctx.lineTo(cursor[0]+6,cursor[1]);
        ctx.moveTo(cursor[0],cursor[1]-6); ctx.lineTo(cursor[0],cursor[1]+6);
        ctx.strokeStyle = "#111"; ctx.lineWidth = 1; ctx.stroke();
      }
    }

    function identity() {
      return state.identity && {entry_id: state.identity.entry_id, revision: state.identity.revision};
    }
    function sameIdentity(a, b) {
      return a && b && a.entry_id === b.entry_id && a.revision === b.revision;
    }
    function shinyInput(suffix, value, origin) {
      if (disposed) return;
      var stamp = origin || identity();
      if (!sameIdentity(stamp, state.identity)) return;
      value = {entry_id: stamp.entry_id, revision: stamp.revision, payload: value};
      if (window.Shiny && el.id) {
        Shiny.setInputValue(el.id + "_" + suffix, value, { priority: "event" });
      }
    }

    function loadImage(uri, cb) {
      if (!uri) { cb(null); return; }
      var im = new Image();
      im.onload = function () { cb(im); };
      im.onerror = function () { cb(null); };
      im.src = uri;
    }

    // ---- Provisional shapes ----
    // A shape the user drew or moved is shown dashed until R answers with new
    // annotations (accepted: R re-renders) or until PENDING_MS pass without an
    // answer (rejected), so the canvas never keeps showing an unsaved ROI.
    function clearPending() {
      state.pending = [];
      if (pendingTimer !== null && timers) clearTimeout(pendingTimer);
      pendingTimer = null;
    }
    function armPending() {
      if (!timers) return;
      if (pendingTimer !== null) clearTimeout(pendingTimer);
      pendingTimer = setTimeout(function () {
        pendingTimer = null;
        if (disposed) return;
        state.pending = [];
        state.features.forEach(function (f) {
          if (f._pending) { f.geometry = f._original; delete f._pending; delete f._original; }
        });
        render();
      }, PENDING_MS);
    }
    function setFeatures(features) {
      clearPending();
      state.features = toArray(features);
    }

    // ---- Hit-testing and geometry helpers (for erase / edit / select) ----
    function pointInRing(pt, ring) {
      var x = pt[0], y = pt[1], inside = false;
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        var xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1];
        if (((yi > y) !== (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi)) {
          inside = !inside;
        }
      }
      return inside;
    }
    function pointInPolygon(pt, rings) {
      return pointInRing(pt, rings[0]) && !rings.slice(1).some(function (r) { return pointInRing(pt, r); });
    }
    function markerRadius(properties) {
      var r = properties && properties.attributes && properties.attributes.point_radius;
      return typeof r === "number" && isFinite(r) && r > 0 && r <= 100 ? r : 4;
    }
    function nearPoint(pt, p, radius) { return Math.hypot(pt[0] - p[0], pt[1] - p[1]) <= (radius || 6) / state.zoom; }
    function nearLine(pt, coords) {
      for (var i = 1; i < coords.length; i++) {
        var a = coords[i - 1], b = coords[i], dx = b[0] - a[0], dy = b[1] - a[1];
        var length2 = dx * dx + dy * dy;
        var t = length2 ? Math.max(0, Math.min(1, ((pt[0]-a[0])*dx + (pt[1]-a[1])*dy) / length2)) : 0;
        if (nearPoint(pt, [a[0] + t * dx, a[1] + t * dy])) return true;
      }
      return false;
    }
    // Topmost feature; holes and gaps never select the surrounding polygon.
    // Locked features are skipped unless `includeLocked` (selection reads only).
    function featureAt(ic, includeLocked) {
      for (var k = state.features.length - 1; k >= 0; k--) {
        var properties = state.features[k].properties || {};
        if (properties.visible === false || (properties.locked === true && !includeLocked)) continue;
        var g = state.features[k].geometry, c = g.coordinates;
        if ((g.type === "Polygon" && pointInPolygon(ic, c)) ||
            (g.type === "MultiPolygon" && c.some(function (p) { return pointInPolygon(ic, p); })) ||
            (g.type === "Point" && nearPoint(ic, c, Math.max(6, markerRadius(properties)))) ||
            (g.type === "MultiPoint" && c.some(function (p) { return nearPoint(ic, p, Math.max(6, markerRadius(properties))); })) ||
            (g.type === "LineString" && nearLine(ic, c)) ||
            (g.type === "MultiLineString" && c.some(function (l) { return nearLine(ic, l); }))) return state.features[k];
      }
      return null;
    }
    function lockedAt(ic) {
      var f = featureAt(ic, true);
      return f && f.properties && f.properties.locked === true ? f : null;
    }
    function circlePoly(c, r) {
      var pts = [];
      for (var a = 0; a < 40; a++) { var t = a / 40 * 2 * Math.PI; pts.push([c[0] + r * Math.cos(t), c[1] + r * Math.sin(t)]); }
      pts.push(pts[0].slice()); // close the ring EXACTLY: sf/GeoJSON require last coord identical to first
      return pts;
    }
    function translateFeature(f, dx, dy) {
      function shift(c) {
        if (typeof c[0] === "number") return [c[0] + dx, c[1] + dy].concat(c.slice(2));
        return c.map(shift);
      }
      f.geometry.coordinates = shift(f.geometry.coordinates);
    }
    // Drop consecutive vertices closer than `tol` image px (a double-click
    // places its final vertex twice).
    function dedupe(pts, tol) {
      var out = [];
      pts.forEach(function (p) {
        var q = out[out.length - 1];
        if (!q || Math.hypot(p[0] - q[0], p[1] - q[1]) > tol) out.push(p);
      });
      return out;
    }

    // ---- Pointer interaction ----
    // `gesture` is the identity stamp taken when a gesture began; `drag` is the
    // in-progress single-pointer action.
    var drag = null, polyPts = null, gesture = null, gestureTarget = null;
    var hover = null, lastClick = null, pointers = {}, pinch = null;
    function cursorFor(tool) {
      if (tool === "pan") return "grab";
      if (tool === "edit") return "move";
      if (tool === "erase" || tool === "select") return "pointer";
      return "crosshair";
    }
    function cancelGesture() {
      if (state.editing) state.editing.feature.geometry = state.editing.original;
      endMouseDrag();
      drag = null; polyPts = null; gesture = null; gestureTarget = null;
      hover = null; lastClick = null; pointers = {}; pinch = null;
      state.drawing = null; state.editing = null;
      canvas.style.cursor = cursorFor(state.tool);
    }
    function listen(name, callback, options) {
      canvas.addEventListener(name, callback, options);
      listeners.push([name, callback, options]);
    }
    function polygonPreview() {
      if (!polyPts) { state.drawing = null; return; }
      var pts = hover && state.tool === "polygon" ? polyPts.concat([hover]) : polyPts;
      state.drawing = { type: "Feature", geometry: { type: "Polygon", coordinates: [pts.concat([pts[0]])] } };
    }
    function finishPolygon() {
      if (!polyPts) return false;
      var pts = dedupe(polyPts, 1.5 / state.zoom);
      if (pts.length < 3) return false;
      emitCreated({ type: "Polygon", coordinates: [pts.concat([pts[0].slice()])] });
      polyPts = null; hover = null; lastClick = null; state.drawing = null;
      gesture = null; gestureTarget = null;
      render();
      return true;
    }

    var drawingTools = ["point", "rect", "polygon", "freehand", "circle", "reflection"];
    function down(s, src) {
      // Focusing must not scroll a partly visible canvas under the pointer.
      canvas.focus({ preventScroll: true }); state.keyboardCursor = false; render();
      if (!state.ready) return;
      if (state.creationTarget && state.creationTarget.locked && drawingTools.includes(state.tool)) {
        announce("This layer is locked. Select an unlocked layer to draw."); return;
      }
      var ic = toImageCoords(s[0], s[1]);
      if (!gesture) {
        gesture = identity();
        gestureTarget = state.creationTarget && {layer: state.creationTarget.layer, label: state.creationTarget.label};
      }
      var tool = state.tool;
      if (tool === "pan") {
        drag = { type: "pan", src: src, last: s }; canvas.style.cursor = "grabbing";
      } else if (tool === "rect") {
        drag = { type: "rect", src: src, s0: s, last: s };
        state.drawing = { type: "Feature", geometry: { type: "Polygon", coordinates: [[[ic[0], ic[1]]]] }, _start: ic };
      } else if (tool === "circle") {
        if (state.circleRadius > 0) {
          emitCreated({type: "Polygon", coordinates: [circlePoly(ic, state.circleRadius)]});
          cancelGesture();
        } else {
          drag = { type: "circle", src: src, s0: s, last: s };
          state.drawing = { type: "Feature", geometry: { type: "Polygon", coordinates: [[[ic[0], ic[1]]]] }, _center: ic };
        }
      } else if (tool === "point") {
        emitCreated({ type: "Point", coordinates: [ic[0], ic[1]] });
        cancelGesture();
      } else if (tool === "reflection") {
        shinyInput("reflection_seed", {x: ic[0], y: ic[1], target: gestureTarget}, gesture);
        cancelGesture();
      } else if (tool === "probe") {
        shinyInput("probed", { x: ic[0], y: ic[1] });
      } else if (tool === "select") {
        var sh = featureAt(ic, true);
        state.selection = sh && sh.properties && sh.properties.roi_id !== undefined ? [sh.properties.roi_id] : [];
        render();
        shinyInput("selected", state.selection);
      } else if (tool === "polygon") {
        var now = Date.now();
        var dbl = lastClick && now - lastClick.t < DBL_MS &&
          Math.hypot(s[0] - lastClick.s[0], s[1] - lastClick.s[1]) < CLOSE_TOL;
        if (polyPts && polyPts.length >= 3) {
          var first = toScreen(polyPts[0][0], polyPts[0][1]);
          if (dbl || Math.hypot(s[0] - first[0], s[1] - first[1]) < CLOSE_TOL) { finishPolygon(); return; }
        }
        if (!dbl) polyPts = (polyPts || []).concat([[ic[0], ic[1]]]);
        lastClick = { t: now, s: s };
        polygonPreview(); render();
      } else if (tool === "freehand") {
        drag = { type: "freehand", src: src, s0: s, last: s };
        polyPts = [[ic[0], ic[1]]];
        polygonPreview(); render();
      } else if (tool === "erase") {
        var eh = featureAt(ic);
        if (eh && eh.properties && eh.properties.roi_id) shinyInput("erased", eh.properties.roi_id);
        else if (lockedAt(ic)) announce("This annotation's layer is locked.");
      } else if (tool === "edit") {
        var mh = featureAt(ic);
        if (mh) {
          state.editing = { feature: mh, start: ic, original: JSON.parse(JSON.stringify(mh.geometry)),
            id: mh.properties && mh.properties.roi_id,
            layer: mh.properties && mh.properties.layer,
            label: mh.properties && mh.properties.label };
          drag = { type: "edit", src: src, s0: s, last: s, moved: false };
        } else if (lockedAt(ic)) {
          announce("This annotation's layer is locked.");
        }
      }
      if (!drag && !polyPts) { gesture = null; gestureTarget = null; }
    }

    function move(s) {
      if (!drag) {
        if (state.tool === "polygon" && polyPts) {
          hover = toImageCoords(s[0], s[1]); polygonPreview(); render();
        }
        return;
      }
      var ic = toImageCoords(s[0], s[1]);
      if (drag.type === "pan") {
        state.panX += s[0] - drag.last[0]; state.panY += s[1] - drag.last[1];
        drag.last = s; render();
        return;
      }
      if (drag.type === "edit" && !drag.moved &&
          Math.hypot(s[0] - drag.s0[0], s[1] - drag.s0[1]) < CLICK_TOL) return;
      drag.last = s;
      if (drag.type === "rect" && state.drawing) {
        var a = state.drawing._start;
        state.drawing.geometry.coordinates = [[[a[0], a[1]], [ic[0], a[1]], [ic[0], ic[1]], [a[0], ic[1]], [a[0], a[1]]]];
      } else if (drag.type === "freehand" && polyPts) {
        polyPts.push([ic[0], ic[1]]); polygonPreview();
      } else if (drag.type === "circle" && state.drawing) {
        var cc = state.drawing._center;
        state.drawing.geometry.coordinates = [circlePoly(cc, Math.hypot(ic[0] - cc[0], ic[1] - cc[1]))];
      } else if (drag.type === "edit" && state.editing) {
        drag.moved = true;
        translateFeature(state.editing.feature, ic[0] - state.editing.start[0], ic[1] - state.editing.start[1]);
        state.editing.start = ic;
      }
      render();
    }

    function up(s) {
      var d = drag;
      drag = null;
      if (!d) return;
      // Some synthetic or cancelled events carry no position: use the last one.
      if (!s || !isFinite(s[0]) || !isFinite(s[1])) s = d.last;
      if (d.type === "pan") {
        canvas.style.cursor = cursorFor(state.tool); emitViewport();
      } else if (d.type === "rect") {
        // A click without a drag is not a rectangle.
        if (state.drawing && Math.min(Math.abs(s[0] - d.s0[0]), Math.abs(s[1] - d.s0[1])) >= CLICK_TOL) {
          emitCreated(state.drawing.geometry);
        }
        state.drawing = null;
      } else if (d.type === "circle") {
        if (state.drawing && Math.hypot(s[0] - d.s0[0], s[1] - d.s0[1]) >= CLICK_TOL) emitCreated(state.drawing.geometry);
        state.drawing = null;
      } else if (d.type === "freehand") {
        var pts = polyPts ? dedupe(polyPts, 0.5 / state.zoom) : [];
        polyPts = null; state.drawing = null;
        if (pts.length >= 3) emitCreated({ type: "Polygon", coordinates: [pts.concat([pts[0].slice()])] });
      } else if (d.type === "edit" && state.editing) {
        var ed = state.editing; state.editing = null;
        if (!d.moved) {
          ed.feature.geometry = ed.original;  // a click is not an edit
        } else if (ed.id) {
          ed.feature._pending = true; ed.feature._original = ed.original;
          armPending();
          shinyInput("edited", { roi_id: ed.id, layer: ed.layer, label: ed.label, geometry: ed.feature.geometry }, gesture);
        }
      }
      if (!state.drawing && !polyPts) { gesture = null; gestureTarget = null; }
      render();
    }

    // Pointer events drive mouse, pen and touch input. Capturing the pointer
    // keeps a drag alive outside the canvas; two touches pinch-zoom.
    function pointerIds() { return Object.keys(pointers); }
    function startPinch() {
      var ids = pointerIds(), a = pointers[ids[0]], b = pointers[ids[1]];
      var mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
      pinch = { d0: Math.max(1, Math.hypot(a[0] - b[0], a[1] - b[1])), z0: state.zoom,
        anchor: toImageCoords(mid[0], mid[1]) };
    }
    function updatePinch() {
      var ids = pointerIds();
      if (ids.length < 2) return;
      var a = pointers[ids[0]], b = pointers[ids[1]];
      var mid = [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
      state.zoom = clampZoom(pinch.z0 * Math.hypot(a[0] - b[0], a[1] - b[1]) / pinch.d0);
      state.panX = mid[0] - pinch.anchor[0] * state.zoom;
      state.panY = mid[1] - pinch.anchor[1] * state.zoom;
      render();
    }
    listen("pointerdown", function (e) {
      if (e.pointerType === "mouse" && e.button !== 0) return;
      var s = localPoint(e);
      pointers[e.pointerId] = s;
      try { canvas.setPointerCapture(e.pointerId); } catch (err) { /* not capturable */ }
      var n = pointerIds().length;
      if (n === 2) {
        // A second finger turns the gesture into a pinch; abandon the drawing.
        if (state.editing) state.editing.feature.geometry = state.editing.original;
        drag = null; state.drawing = null; state.editing = null;
        if (!polyPts) { gesture = null; gestureTarget = null; }
        startPinch(); render();
        return;
      }
      if (n > 2) return;
      down(s, "pointer");
    });
    listen("pointermove", function (e) {
      var s = localPoint(e);
      if (e.pointerId in pointers) pointers[e.pointerId] = s;
      if (pinch) { updatePinch(); return; }
      if (drag && drag.src !== "pointer") return;
      move(s);
    });
    function pointerEnd(e, cancelled) {
      if (!(e.pointerId in pointers)) return;
      delete pointers[e.pointerId];
      try { canvas.releasePointerCapture(e.pointerId); } catch (err) { /* released */ }
      if (pinch) {
        if (pointerIds().length < 2) { pinch = null; pointers = {}; emitViewport(); }
        return;
      }
      if (!drag || drag.src !== "pointer") return;
      if (cancelled) { cancelGesture(); render(); } else up(localPoint(e));
    }
    listen("pointerup", function (e) { pointerEnd(e, false); });
    listen("pointercancel", function (e) { pointerEnd(e, true); });

    // Mouse events drive the canvas only where pointer events cannot: browsers
    // without them, and synthetic (untrusted) events from automated tests.
    // Real mouse input in other browsers arrives as pointer events above.
    function mouseIgnored(e) { return !!window.PointerEvent && e.isTrusted === true; }
    var dragWindow = false;
    // Window listeners only take over events outside the canvas; the canvas
    // listeners below handle (and see first) the ones on it.
    function onWindowMove(e) { if (e.target !== canvas && drag && drag.src === "mouse") move(localPoint(e)); }
    function onWindowUp(e) {
      if (e.target !== canvas && drag && drag.src === "mouse") { endMouseDrag(); up(localPoint(e)); }
    }
    function endMouseDrag() {
      if (!dragWindow) return;
      dragWindow = false;
      window.removeEventListener("mousemove", onWindowMove);
      window.removeEventListener("mouseup", onWindowUp);
    }
    listen("mousedown", function (e) {
      if (mouseIgnored(e) || (e.button !== undefined && e.button !== 0)) return;
      down(localPoint(e), "mouse");
      if (drag && drag.src === "mouse" && !dragWindow) {
        // Follow a drag that leaves the canvas until the button is released.
        dragWindow = true;
        window.addEventListener("mousemove", onWindowMove);
        window.addEventListener("mouseup", onWindowUp);
      }
    });
    listen("mousemove", function (e) {
      if (mouseIgnored(e) || (drag && drag.src !== "mouse")) return;
      move(localPoint(e));
    });
    listen("mouseup", function (e) {
      if (mouseIgnored(e) || !drag || drag.src !== "mouse") return;
      endMouseDrag(); up(localPoint(e));
    });
    listen("dblclick", function (e) {
      // Quick double-clicks already finish in down(). The native event also
      // honours the system's double-click speed (slower settings exceed
      // DBL_MS); finishing twice is a no-op and the repeated vertex is deduped.
      if (state.tool === "polygon") finishPolygon();
    });

    function announce(text) { status.textContent = text; }
    function displayReady(ready, error) {
      state.ready = ready;
      canvas.setAttribute("aria-disabled", String(!ready));
      announce(ready ? "Image ready. Cursor " + state.cursor.join(", ") + (state.viewNote ? ". " + state.viewNote : "") : error);
      shinyInput("ready", {ready: ready, error: error || null});
    }
    listen("focus", function () { state.keyboardCursor = true; render(); });
    listen("blur", function () { render(); });
    listen("keydown", function (e) {
      if (e.key === "Escape") {
        e.preventDefault(); e.stopPropagation(); cancelGesture(); render(); announce("Drawing cancelled."); return;
      }
      // Shift+Enter belongs to the one global synchronous save/advance action.
      if (e.key === "Enter" && e.shiftKey) return;
      if (!["ArrowLeft","ArrowRight","ArrowUp","ArrowDown","Enter"," "].includes(e.key)) return;
      e.preventDefault(); e.stopPropagation();
      if (!state.ready) return;
      state.keyboardCursor = true;
      var step = e.shiftKey ? 10 : 1;
      if (e.key.indexOf("Arrow") === 0) {
        if (e.key === "ArrowLeft") state.cursor[0] -= step;
        if (e.key === "ArrowRight") state.cursor[0] += step;
        if (e.key === "ArrowUp") state.cursor[1] -= step;
        if (e.key === "ArrowDown") state.cursor[1] += step;
        state.cursor[0] = Math.max(0, Math.min(state.imgW, state.cursor[0]));
        state.cursor[1] = Math.max(0, Math.min(state.imgH, state.cursor[1]));
        if (state.drawing && state.tool === "rect") {
          var a = state.drawing._start, b = state.cursor;
          state.drawing.geometry.coordinates = [[[a[0],a[1]],[b[0],a[1]],[b[0],b[1]],[a[0],b[1]],[a[0],a[1]]]];
        }
        render(); announce("Cursor " + state.cursor.join(", ") + (state.drawing ? "; drawing in progress" : "")); return;
      }
      if (!["point","rect","polygon","reflection"].includes(state.tool) &&
          !(state.tool === "circle" && state.circleRadius > 0)) {
        announce("Choose point, fixed round area, rectangle, polygon or reflection wand for keyboard drawing."); return;
      }
      if (state.creationTarget && state.creationTarget.locked) { announce("This layer is locked. Select an unlocked layer to draw."); return; }
      if (!gesture) {
        gesture = identity();
        gestureTarget = state.creationTarget && {layer:state.creationTarget.layer,label:state.creationTarget.label};
      }
      var c = state.cursor.slice();
      if (state.tool === "point") {
        emitCreated({type:"Point",coordinates:c}); cancelGesture();
      } else if (state.tool === "circle") {
        emitCreated({type:"Polygon",coordinates:[circlePoly(c,state.circleRadius)]}); cancelGesture();
      } else if (state.tool === "reflection") {
        shinyInput("reflection_seed", {x:c[0], y:c[1], target:gestureTarget}, gesture); cancelGesture();
      } else if (state.tool === "rect") {
        if (!state.drawing) state.drawing = {type:"Feature",geometry:{type:"Polygon",coordinates:[[c,c,c,c,c]]},_start:c};
        else {
          var start = state.drawing._start;
          if (start[0] === c[0] || start[1] === c[1]) { announce("Move in both directions before completing a rectangle."); return; }
          emitCreated(state.drawing.geometry); cancelGesture();
        }
      } else {
        if (e.key === "Enter" && polyPts && polyPts.length >= 3) {
          emitCreated({type:"Polygon",coordinates:[polyPts.concat([polyPts[0]])]}); cancelGesture();
        } else {
          polyPts = (polyPts || []).concat([c]);
          state.drawing = {type:"Feature",geometry:{type:"Polygon",coordinates:[polyPts.concat([polyPts[0]])]}};
        }
      }
      render(); announce(state.drawing ? "Anchor placed; drawing in progress." : "Drawing submitted.");
    });

    listen("wheel", function (e) {
      e.preventDefault();
      var s = localPoint(e);
      var before = toImageCoords(s[0], s[1]);
      state.zoom = clampZoom(state.zoom * (e.deltaY < 0 ? 1.2 : 1 / 1.2));
      state.panX = s[0] - before[0] * state.zoom;
      state.panY = s[1] - before[1] * state.zoom;
      render(); emitViewport();
    }, { passive: false });

    function emitCreated(geometry) {
      if (!state.ready || (state.creationTarget && state.creationTarget.locked)) return;
      var f = { type: "Feature", geometry: geometry, properties: {} };
      if (geometry.type === "Point") f.properties.attributes = {point_radius: state.pointRadius};
      if (gestureTarget) f.target = gestureTarget;
      if (window.Shiny && el.id) { state.pending.push(f); armPending(); }
      else state.features.push(f);  // a static page has no one to confirm it
      render();
      shinyInput("created", f, gesture);
    }
    function emitViewport() {
      var tl = toImageCoords(0, 0), br = toImageCoords(state.viewW, state.viewH);
      shinyInput("viewport", { zoom: state.zoom, center_x: (state.viewW / 2 - state.panX) / state.zoom,
        center_y: (state.viewH / 2 - state.panY) / state.zoom, bounds: [tl[0], tl[1], br[0], br[1]] });
    }

    // ---- R -> JS messages and lifecycle ----
    function loadOverlay() {
      var generation = overlayGeneration;
      loadImage(state.overlayUri, function (im) {
        if (disposed || generation !== overlayGeneration) return;
        state.overlayImg = im; render();
      });
    }
    function message(name, m) {
      if (disposed) return;
      if (name === "set_annotations") {
        cancelGesture();
        if (m.identity) state.identity = m.identity;
        setFeatures(m.annotations && m.annotations.features); render();
      } else if (name === "set_tool") { cancelGesture(); state.tool = m.tool; canvas.style.cursor = cursorFor(m.tool); render(); }
      else if (name === "set_overlay") {
        ++overlayGeneration;
        state.overlayUri = m.overlay || null;
        state.overlayAlpha = typeof m.alpha === "number" ? m.alpha : 0.5;
        state.overlayImg = null; render();
        loadOverlay();
      } else if (name === "clear_overlay") {
        ++overlayGeneration;
        state.overlayUri = null; state.overlayImg = null; render();
      } else if (name === "set_selection") {
        state.selection = toArray(m.roi_ids); render();
      } else if (name === "fit_bounds") fitBounds(m.bbox);
      // set_band is a no-op: the embedded image cannot be re-banded in the
      // browser, so R re-renders the widget with a new view instead.
    }
    var resizeObserver = null;
    function dispose() {
      if (disposed) return;
      cancelGesture(); clearPending(); disposed = true; baseGeneration++; overlayGeneration++;
      state.overlayUri = null;
      window.removeEventListener("resize", resize);
      if (resizeObserver) { resizeObserver.disconnect(); resizeObserver = null; }
      listeners.forEach(function (l) { canvas.removeEventListener(l[0], l[1], l[2]); });
      canvas.remove(); status.remove();
      if (instances[el.id] && instances[el.id].dispose === dispose) delete instances[el.id];
      if (!Object.keys(instances).length && observer) { observer.disconnect(); observer = null; }
    }
    function inspect() {
      return {
        tool: state.tool, ready: state.ready, status: status.textContent, identity: identity(),
        features: state.features.length, pending: state.pending.length,
        pendingEdits: state.features.filter(function (f) { return f._pending; }).length,
        drawing: !!state.drawing, vertices: polyPts ? polyPts.length : 0,
        hasImage: !!state.baseImg, hasOverlay: !!state.overlayImg, zoom: state.zoom,
        selection: state.selection.slice(), viewW: state.viewW, viewH: state.viewH,
        backingW: canvas.width, backingH: canvas.height,
        // Level-0 image pixel -> page (client) coordinates.
        toClient: function (ix, iy) {
          var r = canvas.getBoundingClientRect(), p = toScreen(ix, iy);
          return [r.left + inset.l + p[0], r.top + inset.t + p[1]];
        }
      };
    }
    instances[el.id] = {el: el, message: message, dispose: dispose, identity: identity, inspect: inspect};
    registerDispatcher();
    window.addEventListener("resize", resize);
    if (typeof ResizeObserver !== "undefined") {
      // Layout changes (cards, sidebars) resize the canvas without a window resize.
      resizeObserver = new ResizeObserver(function () { if (!disposed) resize(); });
      resizeObserver.observe(el);
    }

    return {
      renderValue: function (x) {
        if (disposed) return;
        registerDispatcher();
        // Rendering replaces the annotation objects, so abandon any partial edit.
        cancelGesture();
        var previous = state.identity;
        state.identity = x.identity || {entry_id: el.id, revision: 0};
        state.tool = x.tool || "pan";
        canvas.style.cursor = cursorFor(state.tool);
        state.creationTarget = x.options && x.options.creationTarget;
        var opts = x.options || {};
        state.pointRadius = typeof opts.pointRadius === "number" && isFinite(opts.pointRadius) &&
          opts.pointRadius > 0 && opts.pointRadius <= 100 ? opts.pointRadius : 4;
        state.circleRadius = typeof opts.circleRadius === "number" && isFinite(opts.circleRadius) &&
          opts.circleRadius > 0 && opts.circleRadius <= 1000 ? opts.circleRadius : 0;
        state.suggestion = opts.suggestion || null;
        if (x.options && x.options.selection !== undefined) state.selection = toArray(x.options.selection);
        state.imgW = x.tileSource.width;
        state.imgH = x.tileSource.height;
        setFeatures(x.annotations && x.annotations.features);
        state.viewNote = x.tileSource.viewError ?
          "View not applied (" + x.tileSource.viewError + "); showing natural colour" : null;
        var uri = x.tileSource.dataUri || null;
        var sourceChanged = uri !== state._lastUri || !previous || previous.entry_id !== state.identity.entry_id;
        var generation = ++baseGeneration;
        ++overlayGeneration;
        if (sourceChanged) {
          state.baseImg = null; state.overlayImg = null; state.overlayUri = null;
          state.ready = false;
          state.cursor = [Math.floor(state.imgW / 2), Math.floor(state.imgH / 2)];
          state._lastUri = uri; state.needsFit = true; resize();
        } else {
          resize();
          // Preserve the latest requested overlay across compatible renders,
          // but let only this render's callback paint it.
          if (state.overlayUri && !state.overlayImg) loadOverlay();
        }
        // A same-source render keeps its decoded image: ready, with no error.
        displayReady(!!state.baseImg, state.baseImg ? null : uri ? "Loading image…" :
          (x.tileSource.displayError || "Image display unavailable. Install magick to encode the canvas image, or choose another image."));
        // A pending same-source load is restarted so its callback belongs to this render.
        if (uri && (sourceChanged || !state.baseImg)) {
          loadImage(uri, function (im) {
            if (disposed || generation !== baseGeneration) return;
            state.baseImg = im;
            displayReady(!!im, im ? null : "Image could not be decoded. Choose another image or restore the previous queue.");
            render();
          });
        }
      },
      resize: function () { if (!disposed) resize(); },
      dispose: dispose
    };
  }
});
})();
