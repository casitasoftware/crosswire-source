const root=document.documentElement,theme=document.getElementById('theme'),dq=matchMedia('(prefers-color-scheme: dark)');
try{theme.value=localStorage.getItem('crosswire-theme')||'system'}catch{}
if(theme.value!=='light'&&theme.value!=='dark')theme.value='system';
function effective(){return theme.value==='system'?(dq.matches?'dark':'light'):theme.value}
function setPicture(pic,img,mode){const src=pic.querySelectorAll('source');src.forEach((s,i)=>{if(i)s.remove()});src[0].media='(max-width: 600px)';src[0].srcset=`assets/library-${mode}-detail.svg`;img.src=`assets/library-${mode}.svg`}
function applyTheme(){if(theme.value==='system')delete root.dataset.theme;else root.dataset.theme=theme.value;try{localStorage.setItem('crosswire-theme',theme.value)}catch{}syncImages()}
const tabs=[...document.querySelectorAll('[role=tab]')],heroPic=document.getElementById('hero-picture');
function preview(mode){tabs.forEach(t=>{const active=t.dataset.appearance===mode;t.setAttribute('aria-selected',String(active));t.tabIndex=active?0:-1});const url=`assets/library-${mode}.svg`,img=document.getElementById('library-image'),pic=document.getElementById('library-picture');pic.querySelector('source').srcset=`assets/library-${mode}-detail.svg`;img.src=url;img.alt=`${mode==='light'?'Light':'Dark'} appearance of the proposed Crosswire library interface.`;document.getElementById('full-preview').href=url;document.getElementById('preview-panel').setAttribute('aria-labelledby',`${mode}-tab`)}
function syncImages(){const m=effective();setPicture(heroPic,document.getElementById('hero-image'),m);preview(m)}
applyTheme();theme.addEventListener('change',applyTheme);dq.addEventListener('change',()=>{if(theme.value==='system')syncImages()});
const menu=document.querySelector('.menu'),nav=document.getElementById('nav');
function closeMenu(){menu.setAttribute('aria-expanded','false');nav.classList.remove('open')}
menu.addEventListener('click',()=>{const open=menu.getAttribute('aria-expanded')!=='true';menu.setAttribute('aria-expanded',String(open));nav.classList.toggle('open',open)});
nav.addEventListener('click',e=>{if(e.target.closest('a'))closeMenu()});
document.addEventListener('keydown',e=>{if(e.key==='Escape'&&nav.classList.contains('open')){closeMenu();menu.focus()}});
tabs.forEach((t,i)=>{t.addEventListener('click',()=>preview(t.dataset.appearance));t.addEventListener('keydown',e=>{let next;if(e.key==='ArrowRight'||e.key==='ArrowLeft')next=(i+1)%2;else if(e.key==='Home')next=0;else if(e.key==='End')next=1;if(next!==undefined){e.preventDefault();preview(tabs[next].dataset.appearance);tabs[next].focus()}})});
fetch('config.json').then(r=>{if(!r.ok)throw new Error('Configuration unavailable');return r.json()}).then(config=>{document.querySelectorAll('[data-url]').forEach(link=>{const url=config[link.dataset.url];if(url)link.href=url;else link.hidden=true})}).catch(()=>{});
