// Standalone behavioural regressions: node --test tests/audit/widget.test.js
// A simulated canvas checks routing and geometry commands, not browser pixels.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

// `extra.window` adds browser properties (devicePixelRatio, getComputedStyle)
// and `extra.globals` adds globals such as fake timers.
function harness(delayed = false, canvasSize = 100, extra = {}) {
  let widget;
  const ready = [];
  const handlers = {}, inputs = [], images = [], registrations = {}, listeners = new Set();
  const ctx = {
    HTMLWidgets: { widget(x) { widget = x; } },
    Shiny: {
      addCustomMessageHandler(name, fn) { handlers[name] = fn; registrations[name] = (registrations[name] || 0) + 1; },
      setInputValue(name, value) { (name.endsWith("_ready") ? ready : inputs).push({name, value}); }
    },
    Image: class { set src(value) { this.uri = value; images.push(this); if (!delayed) this.onload(); } },
    window: { addEventListener(name, fn) { listeners.add(fn); }, removeEventListener(name, fn) { listeners.delete(fn); } }
  };
  ctx.window.Shiny = ctx.Shiny;
  Object.assign(ctx.window, extra.window || {});
  Object.assign(ctx, extra.globals || {});
  ctx.document = { createElement() {
    const canvas = {setAttribute(){}, focus(){}, style: {}, events: {}, moves: [], commands: [],
      getBoundingClientRect() { return {left:0, top:0, width:canvasSize, height:canvasSize}; },
      addEventListener(name, fn) { this.events[name] = fn; }, removeEventListener(name) { delete this.events[name]; }, remove() {}
    };
    canvas.getContext = () => ({
      setTransform() {}, beginPath() {}, moveTo(x,y) { canvas.moves.push([x,y]); }, lineTo(x,y) { canvas.commands.push(["lineTo",x,y]); },
      arc(x,y,r) { canvas.commands.push(["arc",x,y]); canvas.lastRadius = r; }, closePath() { canvas.commands.push(["closePath"]); }, fill(rule) { canvas.commands.push(["fill",rule]); }, stroke() {},
      clearRect() { canvas.moves = []; canvas.commands = []; canvas.pixels = null; }, drawImage(im) { canvas.pixels = im.uri; }
    });
    return canvas;
  }};
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../../inst/htmlwidgets/atcanvas.js'),'utf8'),ctx);
  function create(id, features=[]) {
    let canvas;
    const el = {id, isConnected: true, getBoundingClientRect() { return {width:100,height:100}; },
      appendChild(child) { canvas = child; }};
    const w = widget.factory(el,100,100);
    const value = {tileSource:{width:100,height:100,dataUri:'fixture'}, identity:{entry_id:'entry-a',revision:0},tool:'erase',annotations:{features}};
    w.renderValue(value);
    return {canvas, w, el, value, render(changes = {}) { Object.assign(value, changes); w.renderValue(value); }, click(x,y) { canvas.events.mousedown({clientX:x,clientY:y}); }};
  }
  return {create, inputs, ready, handlers, images, registrations, listeners, ctx};
}
const ring = (x0,y0,x1,y1) => [[x0,y0],[x1,y0],[x1,y1],[x0,y1],[x0,y0]];
const feature = geometry => ({type:'Feature',properties:{roi_id:'roi',layer:'L',label:'a'},geometry});

test('line uses two clicks, preserves endpoints under zoom and rejects zero length', () => {
  const h = harness(), a = h.create('a');
  a.render({tool:'line', options:{creationTarget:{layer:'reference',label:'thickness'}}});
  a.canvas.events.wheel({clientX:0,clientY:0,deltaY:-1,preventDefault(){}});
  a.click(12,24);
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,0);
  a.canvas.events.mousemove({clientX:36,clientY:48});
  a.click(12,24);
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,0);
  a.click(36,48);
  const f=h.inputs.find(x=>x.name==='a_created').value.payload;
  assert.equal(f.geometry.type,'LineString');
  assert.deepEqual(JSON.parse(JSON.stringify(f.geometry.coordinates)),[[10,20],[30,40]]);
  assert.equal(f.target.layer,'reference');
  assert.equal(f.target.label,'thickness');
  a.click(24,24); a.click(36,24);
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,2);
});

test('keyboard line and Escape preserve exactly two endpoints', () => {
  const h=harness(),a=h.create('a'); a.render({tool:'line'});
  const key=key=>a.canvas.events.keydown({key,preventDefault(){},stopPropagation(){}});
  key('Enter'); key('ArrowRight'); key('ArrowDown'); key('Enter');
  const f=h.inputs.find(x=>x.name==='a_created').value.payload;
  assert.deepEqual(JSON.parse(JSON.stringify(f.geometry.coordinates)),[[50,50],[51,51]]);
  key('Enter'); key('ArrowRight'); key('Escape'); key('Enter'); key('Escape');
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,1);
});

test('partial line cancels when its layer, image or tool changes', () => {
  const h=harness(),a=h.create('a');
  a.render({tool:'line'}); a.click(10,10);
  a.render({tool:'line',identity:{entry_id:'entry-b',revision:0}});
  a.click(40,40);
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,0);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'line'});
  a.click(60,60);
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,0);
  a.render({tool:'line',options:{creationTarget:{layer:'locked',locked:true}}});
  a.click(10,10); a.click(20,20);
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,0);
});

test('A24 hole hit-testing ignores empty interior and selects shell', () => {
  const h = harness();
  const a = h.create('a',[feature({type:'Polygon',coordinates:[ring(0,0,100,100),ring(40,40,60,60)]})]);
  a.click(50,50);
  assert.equal(h.inputs.length,0,'a click in a hole must not erase the polygon');
  a.click(20,20);
  assert.equal(h.inputs.at(-1).name,'a_erased');
  assert.equal(h.inputs.at(-1).value.payload,'roi');
});

test('A24 polygon display submits the exterior and hole contours', () => {
  const h = harness();
  const a = h.create('a',[feature({type:'Polygon',coordinates:[ring(0,0,100,100),ring(40,40,60,60)]})]);
  assert.deepEqual(a.canvas.moves,[[0,0],[40,40]]);
});

test('A24 MultiPolygon display submits both disconnected components', () => {
  const h = harness();
  const a = h.create('a',[feature({type:'MultiPolygon',coordinates:[[ring(0,0,20,20)],[ring(80,80,100,100)]]})]);
  assert.deepEqual(a.canvas.moves,[[0,0],[80,80]]);
});

test('A24 MultiPolygon hit-testing selects a component and ignores the gap', () => {
  const h = harness();
  const a = h.create('a',[feature({type:'MultiPolygon',coordinates:[[ring(0,0,20,20)],[ring(80,80,100,100)]]})]);
  a.click(50,50);
  assert.equal(h.inputs.length,0);
  a.click(90,90);
  assert.equal(h.inputs.at(-1)?.name,'a_erased');
});

test('A25 tool routing targets each mounted widget independently', () => {
  const h = harness();
  const a = h.create('a'), b = h.create('b');
  h.handlers['atcanvas-set_tool']({id:'a',tool:'point'});
  a.click(20,20);
  assert.equal(h.inputs.at(-1)?.name,'a_created');
  assert.equal(h.inputs.at(-1).value.payload.geometry.type,'Point');
  h.inputs.length = 0;
  b.click(30,30);
  assert.equal(h.inputs.length,0);
  h.handlers['atcanvas-set_tool']({id:'b',tool:'point'});
  b.click(30,30);
  assert.equal(h.inputs.at(-1)?.name,'b_created');
});


test('polygon contours close and fill even-odd, without filling lines', () => {
  const h = harness(), a = h.create('a',[feature({type:'Polygon',coordinates:[ring(0,0,100,100),ring(40,40,60,60)]})]);
  assert.equal(a.canvas.commands.filter(x=>x[0]==='lineTo').length,8);
  assert.equal(a.canvas.commands.filter(x=>x[0]==='closePath').length,2);
  assert.deepEqual(a.canvas.commands.filter(x=>x[0]==='fill'),[['fill','evenodd']]);
  a.render({annotations:{features:[feature({type:'LineString',coordinates:[[10,10],[30,30],[50,10]]})]}});
  assert.equal(a.canvas.commands.filter(x=>x[0]==='fill').length,0);
});

for (const [type, coordinates, hit] of [
  ['Point',[20,20],[20,20]], ['MultiPoint',[[20,20],[80,80]],[80,80]],
  ['LineString',[[10,10],[30,30]],[20,20]],
  ['Polygon',[ring(10,10,30,30)],[20,20]],
  ['MultiPolygon',[[ring(10,10,30,30)],[ring(70,70,90,90)]],[80,80]]
]) test(type+' hit and translation preserve every coordinate and properties', () => {
  const h = harness(), f = feature({type,coordinates}), before = JSON.parse(JSON.stringify(coordinates));
  const a = h.create('a',[f]);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'edit'});
  a.click(...hit); a.canvas.events.mousemove({clientX:hit[0]+5,clientY:hit[1]+7}); a.canvas.events.mouseup({});
  const emitted = h.inputs.at(-1)?.value;
  assert.equal(emitted?.entry_id,'entry-a'); assert.equal(emitted?.revision,0);
  assert.equal(emitted?.payload.roi_id,'roi');
  const shift = c => typeof c[0]==='number' ? [c[0]+5,c[1]+7] : c.map(shift);
  assert.deepEqual(JSON.parse(JSON.stringify(emitted.payload.geometry.coordinates)),shift(before));
  assert.equal(f.properties.label,'a');
});

for (const changed of [{entry_id:'entry-b',revision:0},{entry_id:'entry-a',revision:1}])
for (const tool of ['rect','freehand','circle','polygon','edit']) test(tool+' is cancelled on '+JSON.stringify(changed), () => {
  const h = harness(), a = h.create('a',[feature({type:'Polygon',coordinates:[ring(0,0,100,100)]})]);
  h.handlers['atcanvas-set_tool']({id:'a',tool}); a.click(20,20);
  a.render({identity:changed,tool,annotations:{features:[]}});
  a.canvas.events.mousemove({clientX:40,clientY:40}); a.canvas.events.mouseup({}); a.canvas.events.dblclick({});
  assert.equal(h.inputs.length,0);
});

test('base and overlay loads ignore older generations and missing sources clear pixels', () => {
  const h = harness(true), a = h.create('a');
  const old = h.images[0];
  a.render({tileSource:{width:100,height:100,dataUri:'new'},identity:{entry_id:'entry-b',revision:1}});
  h.images[1].onload(); old.onload(); assert.equal(a.canvas.pixels,'new');
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'old-overlay',alpha:0.5});
  const overlay = h.images.at(-1);
  a.render({tileSource:{width:100,height:100,dataUri:null}}); overlay.onload();
  assert.equal(a.canvas.pixels,null);
  a.render({tileSource:{width:100,height:100,dataUri:'pending'}});
  a.render({identity:{entry_id:'entry-b',revision:2}});
  h.images.at(-1).onload(); assert.equal(a.canvas.pixels,'pending');
});

test('one dispatcher per message survives remount, disposal removes listeners and callbacks', () => {
  const h = harness(true), a = h.create('a'), b = h.create('b');
  const fresh = h.create('a');
  assert.equal(h.listeners.size,2);
  assert.ok(Object.values(h.registrations).every(n=>n===1));
  assert.equal(Object.keys(a.canvas.events).length,0);
  fresh.w.dispose(); assert.equal(h.listeners.size,1);
  h.images.at(-1).onload(); assert.equal(fresh.canvas.pixels,null);
  h.images[1].onload();
  h.handlers['atcanvas-set_tool']({id:'b',tool:'point'}); b.click(10,10);
  assert.equal(h.inputs.at(-1).name,'b_created');
});

test('creation captures the displayed target at gesture birth', () => {
  const h = harness(), a = h.create('a');
  a.render({tool:'rect',options:{creationTarget:{layer:'L',label:'first'}}});
  a.click(10,10);
  a.value.options.creationTarget = {layer:'L',label:'second'};
  a.canvas.events.mousemove({clientX:30,clientY:30}); a.canvas.events.mouseup({});
  assert.deepEqual(JSON.parse(JSON.stringify(h.inputs.at(-1).value.payload.target)),{layer:'L',label:'first'});
});

test('MultiPoint display draws disconnected circles and lines select only their stroke', () => {
  const h = harness(), a = h.create('a',[feature({type:'MultiPoint',coordinates:[[20,20],[80,80]]})]);
  assert.deepEqual(a.canvas.commands.filter(x=>x[0]==='arc'),[['arc',20,20],['arc',80,80]]);
  assert.deepEqual(a.canvas.commands.filter(x=>x[0]==='fill'),[['fill',undefined]],'overlapping point markers use a union fill');
  a.click(50,50); assert.equal(h.inputs.length,0);
  a.render({annotations:{features:[feature({type:'LineString',coordinates:[[10,10],[30,30],[50,10]]})]}});
  a.click(30,15); assert.equal(h.inputs.length,0,'line interior must not behave like a polygon');
  a.click(20,20); assert.equal(h.inputs.at(-1).value.payload,'roi');
});

test('only the newest overlay callback can paint and disposal cancels pending overlays', () => {
  const h = harness(true), a = h.create('a');
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'old',alpha:0.5}); const old = h.images.at(-1);
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'new',alpha:0.5}); const recent = h.images.at(-1);
  recent.onload(); old.onload(); assert.equal(a.canvas.pixels,'new');
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'pending',alpha:0.5});
  a.w.dispose(); h.images.at(-1).onload(); assert.equal(a.canvas.pixels,null);
});

test('a same-source render restarts its pending overlay without accepting the old callback', () => {
  const h = harness(true), a = h.create('a');
  h.images[0].onload();
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'requested-overlay',alpha:0.25});
  const old = h.images.at(-1);
  a.render({tool:'point'});
  assert.equal(h.images.filter(im=>im.uri==='requested-overlay').length,2,
    'a compatible render must retain and restart the pending overlay');
  const retry = h.images.at(-1);
  old.onload(); assert.equal(a.canvas.pixels,'fixture','the superseded callback must stay ignored');
  retry.onload(); assert.equal(a.canvas.pixels,'requested-overlay');
  const count = h.images.length;
  a.render({tool:'erase'});
  assert.equal(h.images.length,count,'an already-loaded compatible overlay is retained without a new request');
  assert.equal(a.canvas.pixels,'requested-overlay');
});

test('failed decode reports not ready and blocks drawing until current load succeeds', () => {
  const h=harness(true),a=h.create('a');
  a.render({tool:'point'}); a.click(20,20);
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,0);
  assert.equal(typeof h.images.at(-1).onerror,'function');
  h.images.at(-1).onerror();
  assert.equal(h.ready.at(-1).name,'a_ready');
  assert.equal(h.ready.at(-1).value.payload.ready,false);
});
test('keyboard rectangle anchors and Escape cancellation create real geometry', () => {
  const h=harness(),a=h.create('a'); a.render({tool:'rect'});
  assert.equal(a.canvas.tabIndex,0);
  const key=key=>a.canvas.events.keydown({key,preventDefault(){},stopPropagation(){}});
  key('Enter'); key('ArrowRight'); key('ArrowDown'); key('Enter');
  const f=h.inputs.filter(x=>x.name==='a_created').at(-1).value.payload;
  assert.deepEqual(JSON.parse(JSON.stringify(f.geometry.coordinates)),[ring(50,50,51,51)]);
  key('Enter'); key('ArrowRight'); key('Escape'); key('Enter'); key('Escape');
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,1);
});
test('protected and hidden features cannot be hit by erase', () => {
  const h=harness(), f=feature({type:'Point',coordinates:[20,20]}); f.properties.locked=true;
  const a=h.create('a',[f]); a.click(20,20);
  assert.equal(h.inputs.filter(x=>x.name==='a_erased').length,0);
});

test('pointer coordinates use canvas content dimensions rather than bordered host size',()=>{
 const h=harness(false,98),a=h.create('a');a.render({tool:'point'});a.click(49,49);
 assert.deepEqual(JSON.parse(JSON.stringify(h.inputs.at(-1).value.payload.geometry.coordinates)),[50,50]);
});

// ---- Fixes beyond the roadmap: provisional shapes, clicks, tools, sizing ----

const named = (h, suffix) => h.inputs.filter(x => x.name.endsWith(suffix));
const inspect = (h, id) => h.ctx.window.atcanvasInspect(id);
const key = (a, k) => a.canvas.events.keydown({key: k, preventDefault() {}, stopPropagation() {}});

test('W24 an edit click without a drag sends nothing and leaves the geometry', () => {
  const h = harness(), f = feature({type:'Polygon',coordinates:[ring(10,10,30,30)]});
  const a = h.create('a',[f]);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'edit'});
  a.click(20,20); a.canvas.events.mousemove({clientX:21,clientY:20}); a.canvas.events.mouseup({});
  assert.equal(named(h,'_edited').length,0);
  assert.deepEqual(JSON.parse(JSON.stringify(f.geometry.coordinates)),[ring(10,10,30,30)]);
});

test('W10 drawn shapes stay provisional until R answers, and expire unanswered', () => {
  const pending = [];
  const h = harness(false, 100, {globals: {setTimeout: fn => { pending.push(fn); return pending.length; }, clearTimeout() {}}});
  const a = h.create('a');
  h.handlers['atcanvas-set_tool']({id:'a',tool:'point'});
  a.click(20,20);
  assert.equal(named(h,'_created').length,1);
  assert.equal(inspect(h,'a').pending,1);
  assert.equal(inspect(h,'a').features,0,'a drawing is not an ROI until R adds it');
  h.handlers['atcanvas-set_annotations']({id:'a',annotations:{features:[feature({type:'Point',coordinates:[20,20]})]}});
  assert.equal(inspect(h,'a').pending,0);
  assert.equal(inspect(h,'a').features,1);
  a.click(40,40);
  assert.equal(inspect(h,'a').pending,1);
  pending.at(-1)();  // no answer from R: the provisional shape disappears
  assert.equal(inspect(h,'a').pending,0);
  // An unanswered move snaps back to the stored geometry.
  const f = feature({type:'Polygon',coordinates:[ring(10,10,30,30)]});
  a.render({tool:'edit',annotations:{features:[f]}});
  a.click(20,20); a.canvas.events.mousemove({clientX:25,clientY:27}); a.canvas.events.mouseup({});
  assert.equal(named(h,'_edited').length,1);
  assert.equal(inspect(h,'a').pendingEdits,1);
  pending.at(-1)();
  assert.deepEqual(JSON.parse(JSON.stringify(f.geometry.coordinates)),[ring(10,10,30,30)]);
});

test('W10 a click with the rectangle or circle tool is not a shape', () => {
  const h = harness(), a = h.create('a');
  for (const tool of ['rect','circle']) {
    h.handlers['atcanvas-set_tool']({id:'a',tool});
    a.click(20,20); a.canvas.events.mouseup({clientX:21,clientY:21});
    a.click(20,20); a.canvas.events.mousemove({clientX:40,clientY:35}); a.canvas.events.mouseup({});
  }
  assert.equal(named(h,'_created').length,2);
});

test('probe and select send stamped payloads; selection reads locked ROIs', () => {
  const h = harness(), f = feature({type:'Polygon',coordinates:[ring(10,10,30,30)]});
  f.properties.locked = true;
  const a = h.create('a',[f]);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'probe'}); a.click(12.5,40);
  const probe = named(h,'_probed').at(-1).value;
  assert.deepEqual([probe.entry_id, probe.revision], ['entry-a', 0]);
  assert.deepEqual(JSON.parse(JSON.stringify(probe.payload)),{x:12.5,y:40});
  h.handlers['atcanvas-set_tool']({id:'a',tool:'select'}); a.click(20,20);
  assert.deepEqual(JSON.parse(JSON.stringify(named(h,'_selected').at(-1).value.payload)),['roi']);
  a.click(80,80);
  assert.deepEqual(JSON.parse(JSON.stringify(named(h,'_selected').at(-1).value.payload)),[]);
  h.handlers['atcanvas-set_selection']({id:'a',roi_ids:'roi'});
  assert.deepEqual(JSON.parse(JSON.stringify(inspect(h,'a').selection)),['roi']);
});

test('clear_overlay removes the overlay and cancels its pending load', () => {
  const h = harness(true), a = h.create('a');
  h.images[0].onload();
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'overlay',alpha:0.5});
  h.handlers['atcanvas-clear_overlay']({id:'a'});
  h.images.at(-1).onload();
  assert.equal(a.canvas.pixels,'fixture');
  assert.equal(inspect(h,'a').hasOverlay,false);
});

test('W11 polygons close on the first vertex, drop double-click duplicates, and Escape cancels', () => {
  const h = harness(), a = h.create('a');
  h.handlers['atcanvas-set_tool']({id:'a',tool:'polygon'});
  for (const [x,y] of [[10,10],[60,10],[60,60]]) a.click(x,y);
  a.click(11,11);  // within the closing tolerance of the first vertex
  let ring1 = named(h,'_created').at(-1).value.payload.geometry.coordinates[0];
  assert.equal(ring1.length,4);
  for (const [x,y] of [[10,10],[60,10],[60,60],[10,60]]) a.click(x,y);
  a.click(10,60); a.canvas.events.dblclick({});  // a double-click repeats the last vertex
  ring1 = named(h,'_created').at(-1).value.payload.geometry.coordinates[0];
  assert.equal(ring1.length,5,'four distinct vertices plus the closing one');
  a.click(10,10); a.click(60,10); a.click(60,60);
  key(a,'Escape');
  assert.equal(inspect(h,'a').vertices,0);
  a.canvas.events.dblclick({});
  assert.equal(named(h,'_created').length,2);
  // A tool change also abandons an unfinished polygon.
  a.click(10,10); a.click(60,10);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'freehand'});
  assert.equal(inspect(h,'a').vertices,0);
});

test('W20 high-density displays keep pointer and image coordinates aligned', () => {
  const h = harness(false, 100, {window: {devicePixelRatio: 2}}), a = h.create('a');
  assert.equal(a.canvas.width,200);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'point'}); a.click(50,25);
  assert.deepEqual(JSON.parse(JSON.stringify(named(h,'_created').at(-1).value.payload.geometry.coordinates)),[50,25]);
});

test('W20 a border and padding on the canvas do not shift coordinates', () => {
  const style = {borderLeftWidth:'3px',borderTopWidth:'3px',borderRightWidth:'3px',borderBottomWidth:'3px',
                 paddingLeft:'2px',paddingTop:'2px',paddingRight:'2px',paddingBottom:'2px'};
  const h = harness(false, 110, {window: {getComputedStyle: () => style}}), a = h.create('a');
  assert.equal(inspect(h,'a').viewW,100);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'point'}); a.click(5 + 50, 5 + 30);
  assert.deepEqual(JSON.parse(JSON.stringify(named(h,'_created').at(-1).value.payload.geometry.coordinates)),[50,30]);
});

test('W20 wheel zoom is limited', () => {
  const h = harness(), a = h.create('a');
  for (let i = 0; i < 60; i++) a.canvas.events.wheel({clientX:50,clientY:50,deltaY:-1,preventDefault() {}});
  assert.equal(inspect(h,'a').zoom,32);
  for (let i = 0; i < 60; i++) a.canvas.events.wheel({clientX:50,clientY:50,deltaY:1,preventDefault() {}});
  assert.equal(inspect(h,'a').zoom,0.25);
});

test('V10 a click focuses the canvas without scrolling the page', () => {
  const h = harness(), a = h.create('a'), calls = [];
  a.canvas.focus = options => calls.push(options);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'polygon'});
  a.click(10,10); a.click(60,10);
  assert.deepEqual(JSON.parse(JSON.stringify(calls)),[{preventScroll:true},{preventScroll:true}]);
  assert.equal(inspect(h,'a').vertices,2);
});

test('a trusted double-click finishes a polygon even when the clicks were slower than DBL_MS', () => {
  // A browser with pointer events, where trusted mouse events used to be
  // ignored, and a clock so clicks can be slower than DBL_MS (350 ms).
  let clock = 0;
  const h = harness(false, 100, {window: {PointerEvent: function () {}}, globals: {Date: {now: () => clock}}});
  const a = h.create('a');
  h.handlers['atcanvas-set_tool']({id:'a',tool:'polygon'});
  for (const [x,y] of [[10,10],[60,10],[60,60],[10,60]]) { clock += 1000; a.click(x,y); }
  clock += 500;
  a.click(10,60);  // second click of a slow double-click: a repeated vertex
  assert.equal(named(h,'_created').length,0,'500 ms apart is not a DBL_MS double-click');
  a.canvas.events.dblclick({isTrusted:true});
  const ring = named(h,'_created').at(-1).value.payload.geometry.coordinates[0];
  assert.equal(ring.length,5,'four distinct vertices plus the closing one');
  assert.equal(inspect(h,'a').vertices,0);
});


for (const radius of [2, 4, 8]) test('point marker retains radius ' + radius, () => {
  const h = harness(), a = h.create('a');
  a.render({tool:'point', options:{pointRadius:radius}}); a.click(50,50);
  const f = h.inputs.at(-1).value.payload;
  assert.equal(f.geometry.type, 'Point');
  assert.equal(f.properties.attributes.point_radius, radius);
  assert.equal(a.canvas.lastRadius, radius);
  a.render({annotations:{features:[f]}, options:{pointRadius:2}});
  assert.equal(a.canvas.lastRadius, radius, 'saved marker keeps its own size');
});

for (const radius of [2.5, 5, 10]) test('fixed circle covers image radius ' + radius, () => {
  const h = harness(), a = h.create('a');
  a.render({tool:'circle', options:{circleRadius:radius}});
  h.handlers['atcanvas-fit_bounds']({id:'a',bbox:[25,25,75,75]});
  a.click(50,50);
  const f = h.inputs.at(-1).value.payload;
  assert.equal(f.geometry.type, 'Polygon');
  for (const p of f.geometry.coordinates[0])
    assert.ok(Math.abs(Math.hypot(p[0]-50,p[1]-50)-radius) < 1e-9);
  assert.deepEqual(f.geometry.coordinates[0][0], f.geometry.coordinates[0].at(-1));
});

test('fixed circle keyboard placement and reflection seed emit the intended action', () => {
  const h = harness(), a = h.create('a');
  a.render({tool:'circle', options:{circleRadius:5}});
  a.canvas.events.keydown({key:'Enter',preventDefault(){},stopPropagation(){}});
  assert.equal(h.inputs.at(-1).value.payload.geometry.type, 'Polygon');
  a.render({tool:'reflection',options:{creationTarget:{layer:'Artifacts',label:'reflectations'}}});
  a.click(40,30);
  assert.equal(h.inputs.at(-1).name, 'a_reflection_seed');
  assert.deepEqual(JSON.parse(JSON.stringify(h.inputs.at(-1).value.payload)),
    {x:40,y:30,target:{layer:'Artifacts',label:'reflectations'}});
});
