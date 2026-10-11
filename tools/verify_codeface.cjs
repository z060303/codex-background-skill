/* Optional isolated integration test: npm install --no-save playwright first.
   Usage: node tools/verify_codeface.cjs CODEFACE_EXE RUNTIME_BASE [SCREENSHOT]
   Does not connect to an existing browser or the user's Codex instance. */
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const [exe, runtimeBase, screenshot] = process.argv.slice(2);
if (!exe || !runtimeBase) throw new Error('Pass CodeFace executable and isolated runtime base');

(async () => {
  // Chromium chooses a free debugging port; this process owns the fixture.
  const browser = await chromium.launch({headless: true, args: ['--enable-automation', '--remote-debugging-port=0']});
  try {
    const context = await browser.newContext({ viewport: {width: 1400, height: 900} });
    const page = await context.newPage();
    const session = await browser.newBrowserCDPSession();
    const command = await session.send('Browser.getBrowserCommandLine');
    const directory = command.arguments.find(x => x.startsWith('--user-data-dir=')).split('=').slice(1).join('=');
    const port = Number(fs.readFileSync(path.join(directory,'DevToolsActivePort'),'utf8').split('\n')[0]);
    assert(port > 0);
    await page.setContent(`<!doctype html><html><head><title>Codex isolated theme fixture</title></head>
      <body style="margin:0;font:16px system-ui"><main class="main-surface" style="padding:28px;box-sizing:border-box">
        <article style="padding:24px;max-width:820px;margin:auto">
          <div data-message-author-role="assistant"><h2>Local theme verification</h2>
          <p>A readable conversation. Normal body weight, clear controls, and no horizontal overflow.</p>
          <p>独立测试页面：这不是用户的 Codex 对话。</p></div>
        </article><div class="composer-surface-chrome" style="padding:20px;max-width:820px;margin:30px auto">
        <textarea aria-label="Message" style="width:80%;min-height:60px"></textarea><button>Send</button></div>
      </main></body></html>`);
    const run = (...args) => execFileSync(exe,args,{env:{...process.env, LOCALAPPDATA:runtimeBase},encoding:'utf8',timeout:35000,windowsHide:true}).trim();
    const manifest = JSON.parse(fs.readFileSync(path.join(runtimeBase,'CodeFace','theme','theme.json'),'utf8'));
    run('--inject-active',String(port));
    const report = JSON.parse(run('--health-check',manifest.id,String(port)));
    assert.equal(report.healthy,true);
    assert.equal(report.expected_theme_id,manifest.id);
    assert(report.pages.length > 0 && report.pages.every(x=>x.healthy && x.theme_id===manifest.id));
    for(const width of [760,1100,1440]){
      await page.setViewportSize({width,height:900});
      for(const zoom of [0.8,1,1.25,1.5]){
        await page.evaluate(z=>document.documentElement.style.zoom=String(z),zoom);
        const reading=await page.evaluate(()=>({
          overflow:document.documentElement.scrollWidth>document.documentElement.clientWidth+2,
          weight:getComputedStyle(document.querySelector('[data-message-author-role="assistant"] p')).fontWeight,
          style:!!document.getElementById('codeface-style'),
          marker:document.documentElement.classList.contains('codeface'),
          wallpaper:/^url\("(?:blob:|data:image\/)/.test(getComputedStyle(document.body).backgroundImage),
          surface:getComputedStyle(document.querySelector('article')).backgroundColor
        }));
        assert(reading.style && reading.marker,'theme missing');
        assert(reading.wallpaper,'wallpaper not painted on body');
        assert.notEqual(reading.surface,'rgba(0, 0, 0, 0)','reading surface absent');
        assert.equal(reading.weight,'400','body weight changed');
        assert(!reading.overflow,`fixture overflow at width ${width}, CSS zoom ${zoom}`);
      }
    }
    await page.evaluate(()=>document.documentElement.style.zoom='1');
    if(screenshot) await page.screenshot({path:screenshot});
    // Exercise CodeFace's own renderer cleanup without touching another process.
    await page.evaluate(()=>window.__CODEFACE_STATE__?.cleanup?.());
    const removed=await page.evaluate(()=>!document.getElementById('codeface-style'));
    assert(removed,'CodeFace cleanup did not remove style');
    console.log(JSON.stringify({theme:manifest.id,health:true,fixtureLayouts:12,cleanup:true,scope:'isolated Chromium fixture; not live Codex or Windows login'}));
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1});
