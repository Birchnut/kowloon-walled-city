// 웹(데스크톱 브라우저) 빌드 확인 — 로컬 서버 + Playwright(소프트웨어 GL).
// 사용: python3 -m http.server 8790 --directory godot/build/web &  →  node tools/web_check.js <out_dir> [1920x1080|1366x768] [phase]
//   phase: all(기본) | reload(저장 이어 하기만)
// 하는 일: 부팅(콘솔·실패한 요청 모음) → 오프닝 첫 단계(휠·오른쪽 끌기·Q/E) → H 판잣집 칠하기 → 시장 R 돌려 놓기 → Tab 현황판 → F4·F6 창 →
//   배속 키 → 줍줍 본부 → ×4 기다림 → F4 직접 줍기 → 줍기 안에서 WASD·클릭·Esc → 자동(F2) → 도시로 → 새로 고침 → 저장 이어 하기.
// 좌표는 1920×1080 논리 화면 기준(1366×768 은 배율을 곱한다). 결과: <out>/web_*.png, <out>/console.txt
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const out = process.argv[2] || 'web_out';
const res = (process.argv[3] || '1920x1080').split('x').map(Number);
const phase = process.argv[4] || 'all';
const URL = process.env.WEB_URL || 'http://localhost:8790/index.html';
fs.mkdirSync(out, { recursive: true });
const log = [];
const t0 = Date.now();
const stamp = () => ((Date.now() - t0) / 1000).toFixed(1);
const note = (s) => { const l = `[${stamp()}s] ${s}`; log.push(l); console.log(l); };

(async () => {
  const browser = await chromium.launch({ args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=user-gesture-required'] });
  const ctx = await browser.newContext({ viewport: { width: res[0], height: res[1] } });
  const page = await ctx.newPage();
  page.on('console', (m) => log.push(`[${stamp()}s] console.${m.type()}: ${m.text()}`));
  page.on('pageerror', (e) => log.push(`[${stamp()}s] PAGEERROR: ${e.message}`));
  page.on('requestfailed', (r) => log.push(`[${stamp()}s] REQFAILED: ${r.url()} ${r.failure() && r.failure().errorText}`));
  page.on('response', (r) => { if (r.status() >= 400) log.push(`[${stamp()}s] HTTP ${r.status()}: ${r.url()}`); });

  // 논리 1920×1080 → 화면 픽셀(근사: 작은 창에서는 UI 가 0.8 밑으로 줄지 않아 아래·오른쪽 패널 자리가 조금 다르다).
  const P = (x, y) => [x * res[0] / 1920, y * res[1] / 1080];
  const shot = async (name) => { await page.screenshot({ path: path.join(out, `web_${name}.png`) }); note(`shot ${name}`); };
  const wait = (s) => page.waitForTimeout(s * 1000);
  const click = async (x, y, button = 'left') => { const [a, b] = P(x, y); await page.mouse.move(a, b, { steps: 4 }); await page.mouse.down({ button }); await wait(0.08); await page.mouse.up({ button }); };
  const drag = async (x0, y0, x1, y1, button = 'left') => { const [a, b] = P(x0, y0); const [c, d] = P(x1, y1); await page.mouse.move(a, b, { steps: 3 }); await page.mouse.down({ button }); await page.mouse.move(c, d, { steps: 12 }); await wait(0.1); await page.mouse.up({ button }); };
  const key = async (kk, hold = 0) => { if (hold > 0) { await page.keyboard.down(kk); await wait(hold); await page.keyboard.up(kk); } else { await page.keyboard.press(kk); } await wait(0.25); };

  note(`열기 ${URL} ${res.join('x')} phase=${phase}`);
  await page.goto(URL, { waitUntil: 'load', timeout: 120000 });
  // 부팅: Godot 가 캔버스를 만들고 첫 화면을 그릴 때까지(소프트웨어 GL 45–120초)
  await page.waitForSelector('canvas', { timeout: 120000 });
  let booted = false;
  for (let i = 0; i < 40 && !booted; i++) {
    await wait(5);
    booted = log.some((l) => l.includes('Godot Engine') || l.includes('OpenGL')) && (Date.now() - t0) > 40000;
  }
  await wait(15);
  await shot('01_boot');
  if (phase === 'reload') {
    await finish();
    return;
  }
  // 첫 입력(소리 시작) — 땅 가운데 휠
  const [mx, my] = P(1100, 520);
  await page.mouse.move(mx, my);
  await page.mouse.wheel(0, -120); await wait(1.0);
  await drag(1200, 560, 1080, 600, 'right'); await wait(0.5);
  await key('q'); await wait(0.8); await key('e'); await wait(0.5);
  await page.mouse.wheel(0, 120); await wait(2.0);
  await shot('02_camera');
  // 판잣집 칠하기: H → 끌기
  await key('h'); await wait(0.5);
  await drag(930, 470, 1050, 560); await wait(2.0);
  await shot('03_painted');
  await key('Escape'); await wait(0.5);
  // 시장: Z → 첫 카드 → R → 놓기
  await key('z'); await wait(0.8);
  await click(505, 1000); await wait(0.6);
  await key('r'); await wait(0.4);
  const [gx, gy] = P(880, 470); await page.mouse.move(gx, gy, { steps: 6 }); await wait(0.8);
  await shot('04_market_ghost_rotated');
  await click(880, 470); await wait(0.8);
  await key('Escape'); await wait(0.5);
  // 창들
  await key('Tab'); await wait(2.0); await shot('05_metrics'); await key('Tab'); await wait(0.5);
  await key('F4'); await wait(2.0); await shot('06_expedition'); await key('Escape'); await wait(0.5);
  await key('F6'); await wait(2.0); await shot('07_keep'); await key('Escape'); await wait(0.5);
  // 배속
  await key('2'); await wait(1.0); await key('Space'); await wait(1.0); await shot('08_paused'); await key('Space'); await key('3');
  // 줍줍 본부(기반 K) → 놓기 → 기다림
  await key('k'); await wait(0.8);
  await click(505, 1000); await wait(0.6);
  await click(1150, 420); await wait(0.8);
  await key('Escape'); await wait(0.5);
  await shot('09_base_placed');
  await wait(45);
  await key('F4'); await wait(2.5);
  await shot('10_expedition_with_team');
  note('직접 줍기 버튼은 위 그림에서 좌표를 확인해 RUN_X/RUN_Y 로 준다(기본 1590, 395)');
  const rx = Number(process.env.RUN_X || 1590), ry = Number(process.env.RUN_Y || 395);
  await click(rx, ry); await wait(6.0);
  await shot('11_run_start');
  await key('Enter'); await wait(3.0);
  await key('d', 1.0); await key('w', 0.5);
  await click(1300, 500); await wait(0.3); await click(1300, 500);
  await key('Space'); await wait(1.0);
  await shot('12_run_moved');
  await key('Escape'); await wait(1.0); await shot('13_run_pause'); await key('Escape'); await wait(0.5);
  await key('F2'); // 줍기 자동 플레이
  for (let i = 0; i < 40; i++) { await wait(10); if (i % 6 === 5) await shot(`14_run_auto_${i}`); }
  await shot('15_run_result');
  await key('Enter'); await wait(3.0);
  await shot('16_back_city');
  await wait(4.0); // 자동 저장(명령 뒤 2초)
  note('새로 고침');
  await page.reload({ waitUntil: 'load' });
  await page.waitForSelector('canvas', { timeout: 120000 });
  await wait(90);
  await shot('17_after_reload');
  await finish();

  async function finish() {
    fs.writeFileSync(path.join(out, 'console.txt'), log.join('\n'));
    const errs = log.filter((l) => /PAGEERROR|REQFAILED|HTTP [45]|SCRIPT ERROR|ERROR:|console\.error/.test(l));
    note(`끝 — 오류 줄 ${errs.length}`);
    errs.slice(0, 40).forEach((l) => console.log('  ' + l));
    await browser.close();
  }
})();
