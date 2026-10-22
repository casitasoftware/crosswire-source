import { readFile, writeFile, mkdir, cp, rm, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const root=fileURLToPath(new URL('../',import.meta.url));
const source=path.join(root,'site');
const config=JSON.parse(await readFile(path.join(source,'config.json'),'utf8'));
let html=await readFile(path.join(source,'index.html'),'utf8');
for(const [key,value] of Object.entries(config)) {
  if(value!==null && (typeof value!=='string'||! /^(https:\/\/|mailto:)/.test(value))) throw new Error(`Invalid URL for ${key}. Set an HTTPS or mailto URL, or null.`);
}
html=html.replace(/<a\b[^>]*data-url="([^"]+)"[^>]*>/g,(tag,key)=>{
  if(!Object.hasOwn(config,key)) throw new Error(`Missing URL key ${key}. Add it to site/config.json.`);
  const url=config[key];
  const cleaned=tag.replace(/\s(?:href="[^"]*"|hidden(?:="[^"]*")?)/g,'');
  if(!url)return cleaned.slice(0,-1)+' hidden>';
  const escaped=url.replace(/&/g,'&amp;').replace(/"/g,'&quot;').replace(/</g,'&lt;');
  return cleaned.slice(0,-1)+` href="${escaped}">`;
});
for(const match of html.matchAll(/(?:src|srcset|href)="([^"#]+)"/g)) {
  const url=match[1];
  if(/^(https?:|mailto:|\.\/)/.test(url))continue;
  await readFile(path.join(source,url));
}
if(process.argv.includes('--check')){console.log('Source and link configuration checked.');process.exit(0);}
const output=path.join(root,'dist');
await rm(output,{recursive:true,force:true});
await mkdir(output,{recursive:true});
await cp(source,output,{recursive:true});
await writeFile(path.join(output,'index.html'),html);
console.log('Built dist/. Upload its contents to the website host.');
