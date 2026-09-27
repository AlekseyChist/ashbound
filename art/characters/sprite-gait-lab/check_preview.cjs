const {chromium}=require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const {pathToFileURL}=require('node:url');const {resolve}=require('node:path');
const {writeFileSync,mkdirSync}=require('node:fs');const assert=require('node:assert/strict');
mkdirSync('.tools/sprite-gait-lab',{recursive:true});
(async()=>{const b=await chromium.launch({executablePath:process.env.CHROMIUM_EXECUTABLE});try{
 const p=await b.newPage({viewport:{width:1120,height:1100}});const errors=[];
 p.on('pageerror',e=>errors.push(e.message));p.on('requestfailed',r=>errors.push(r.url()+': '+r.failure().errorText));
 await p.goto(pathToFileURL(resolve('art/characters/sprite-gait-lab/index.html')).href);
 await p.waitForFunction(()=>document.querySelector('canvas').dataset.count==='8');
 await p.waitForFunction(()=>document.querySelector('canvas').dataset.frame!=='0');
 await p.getByRole('button',{name:'Пауза',exact:true}).click();
 for(let i=0;i<8;i++){await p.evaluate(n=>{frame=n;paint();},i);await p.locator('#stage').screenshot({path:'.tools/sprite-gait-lab/frame-'+i+'.png'});}
 await p.getByRole('button',{name:'Следующий кадр',exact:true}).click();
 assert.equal(await p.locator('#stage').getAttribute('data-frame'),'0');
 await p.getByRole('button',{name:'Назад',exact:true}).click();
 assert.equal(await p.locator('#stage').getAttribute('data-frame'),'7');
 await p.getByRole('button',{name:'Соседний кадр',exact:true}).click();
 assert.equal(await p.locator('#onion').getAttribute('aria-pressed'),'true');
 await p.getByRole('button',{name:'Влево',exact:true}).click();
 assert.equal(await p.locator('#flip').getAttribute('aria-pressed'),'true');
 await p.locator('#duration').selectOption('1.5');
 for(const v of ['raw','keys','final']){await p.locator('#variant').selectOption(v);assert.equal(await p.locator('#stage').getAttribute('data-count'),v==='final'?'8':'4');}
 await p.locator('#onion').click();await p.locator('#flip').click();
 assert.equal(await p.locator('#onion').getAttribute('aria-pressed'),'false');
 assert.equal(await p.locator('#flip').getAttribute('aria-pressed'),'false');
 await p.evaluate(()=>{frame=0;paint();});await p.screenshot({path:'.tools/sprite-gait-lab/preview.png',fullPage:true});
 assert.deepEqual(errors,[]);writeFileSync('.tools/sprite-gait-lab/browser-checks.json',JSON.stringify({pass:true,variants:3,frames:8,errors},null,2));
 console.log('SPRITE_LAB_PREVIEW_OK 3 variants; 8 phases; playback, wrap, onion, flip, timing');
}finally{await b.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
