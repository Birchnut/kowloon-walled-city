import asyncio, sys, json
from playwright.async_api import async_playwright
ROOT=sys.argv[1]; PORT=sys.argv[2]
INIT = """
(() => {
  window.__an = []; window.__ctxs = []; window.__edges=[]; let nid=0;
  const idof = n => { if(!n.__id){ n.__id = (++nid)+':'+n.constructor.name.replace('Node',''); } return n.__id; };
  const od = AudioNode.prototype.disconnect;
  AudioNode.prototype.disconnect = function(...a){ window.__edges.push(['D', idof(this), a.length? (a[0].__id||'?') : '*']); return od.apply(this,a); };
  window.__idof = idof;
  const AC = window.AudioContext || window.webkitAudioContext;
  const origConnect = AudioNode.prototype.connect;
  AudioNode.prototype.connect = function(dest, ...rest) {
    try {
      if (dest instanceof AudioNode) window.__edges.push(['C', idof(this), idof(dest)]);
      if (dest instanceof AudioDestinationNode) {
        const ctx = dest.context;
        if (!ctx.__an) { ctx.__an = ctx.createAnalyser(); ctx.__an.fftSize = 2048; window.__an.push(ctx.__an); window.__ctxs.push(ctx); }
        origConnect.call(this, ctx.__an);
      }
    } catch (e) {}
    return origConnect.call(this, dest, ...rest);
  };
  window.__starts = []; window.__gains = []; window.__conn = 0;
  const os = AudioBufferSourceNode.prototype.start;
  AudioBufferSourceNode.prototype.start = function(...a){ try{ window.__starts.push([Math.round(this.context.currentTime*10)/10, this.buffer? Math.round(this.buffer.duration*10)/10 : -1]); this.__g=1;}catch(e){} return os.apply(this,a); };
  const cg = AudioContext.prototype.createGain;
  AudioContext.prototype.createGain = function(...a){ const g = cg.apply(this,a); window.__gains.push(g); return g; };
  window.__info = () => ({starts: window.__starts.slice(-12), nstarts: window.__starts.length, gains: window.__gains.map(g=>Math.round(g.gain.value*1000)/1000)});
  window.__rms = () => window.__an.map(a => { const b = new Float32Array(a.fftSize); a.getFloatTimeDomainData(b); let s=0; for (const v of b) s+=v*v; return Math.sqrt(s/b.length); });
  window.__state = () => window.__ctxs.map(c => c.state);
})();
"""
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(args=["--use-gl=swiftshader","--enable-unsafe-swiftshader","--ignore-gpu-blocklist","--autoplay-policy=no-user-gesture-required"])
        pg=await b.new_page(viewport={"width":1920,"height":1080})
        logs=[]
        pg.on("console", lambda m: logs.append(m.type+": "+m.text[:200]))
        await pg.add_init_script(INIT)
        await pg.goto(f"http://localhost:{PORT}/index.html")
        await pg.wait_for_timeout(30000)
        await pg.mouse.click(960,400)
        out=[]
        for i in range(10):
            await pg.wait_for_timeout(1000)
            r=await pg.evaluate("[window.__rms(), window.__state()]")
            out.append(r)
        await pg.keyboard.press("F1"); await pg.wait_for_timeout(500); await pg.keyboard.press("F1")
        await pg.mouse.click(1000,500); await pg.wait_for_timeout(8000)
        print("info:", json.dumps(await pg.evaluate("window.__info()")))
        print("rms now:", await pg.evaluate("window.__rms()"))
        r=await pg.evaluate("(async()=>{const c=window.__ctxs[0]; const o=c.createOscillator(); o.connect(c.destination); o.start(); await new Promise(r=>setTimeout(r,500)); const v=window.__rms(); o.stop(); return [v, c.sampleRate, c.destination.channelCount, c.destination.maxChannelCount];})()")
        print("osc control rms:", r)
        e=await pg.evaluate("[window.__edges.slice(0,60), window.__edges.length, window.__gains.map(g=>[g.__id||'-', Math.round(g.gain.value*1000)/1000]).slice(0,24)]")
        print("edges:", json.dumps(e[0])); print("n edges", e[1]); print("gains:", json.dumps(e[2]))
        print("ctx states:", out[-1][1])
        print("rms per sec:", [ [round(x,5) for x in o[0]] for o in out])
        print("\n".join([l for l in logs if 'error' in l.lower() or 'warn' in l.lower()][:15]))
        await b.close()
asyncio.run(main())
