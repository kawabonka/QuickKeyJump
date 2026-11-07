'use strict';
const $ = id => document.getElementById(id);
const td = new TurndownService({headingStyle:'atx',codeBlockStyle:'fenced',bulletListMarker:'-'});
td.use(turndownPluginGfm.gfm);
// Restore typed list markers at the text-node escaping stage, regardless of
// whether Office wraps the line in p, div, span, or ends a copied fragment there.
// Turndown bypasses escape() for code, so code blocks and inline code stay literal.
const escapeMarkdownText = td.escape.bind(td);
td.escape = function (text) {
 return escapeMarkdownText(text).replace(/(^|[^\\])\\-(?=[ \t\u00a0]|$)/g, '$1-');
};
let chinese=true, showSource=false, result='', rich='', plain='', timer;
const tr=(zh,en)=>chinese?zh:en;
function setLanguage(zh){chinese=zh;document.documentElement.lang=zh?'zh':'en';document.querySelectorAll('[data-zh]').forEach(el=>el.textContent=el.dataset[zh?'zh':'en']);$('input').placeholder=tr('在这里粘贴或输入 Markdown、HTML、Slack 或纯文本…','Paste or type Markdown, HTML, Slack, or plain text here…');convert();}
function clean(html){
 const doc=new DOMParser().parseFromString(html,'text/html');
 const allowed=new Set('P BR H1 H2 H3 H4 H5 H6 STRONG B EM I S DEL UL OL LI BLOCKQUOTE PRE CODE TABLE THEAD TBODY TR TH TD HR A DIV SPAN'.split(' '));
 for(const el of [...doc.body.querySelectorAll('*')].reverse()){
  if(['SCRIPT','STYLE','IFRAME','OBJECT','SVG','MATH','TEMPLATE'].includes(el.tagName)){el.remove();continue;}
  if(!allowed.has(el.tagName)){el.replaceWith(...el.childNodes);continue;}
  for(const attr of [...el.attributes]){if(!(el.tagName==='A'&&attr.name==='href'&&/^(https?:|mailto:)/i.test(attr.value)))el.removeAttribute(attr.name);}
 }
 return doc.body.innerHTML;
}
function escapeHTML(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function detect(s){if(/<\/?(?:p|div|h[1-6]|table|strong|ul|br|span|a)\b[^>]*>/i.test(s))return 'html';if(/<https?:[^>]+\|[^>]+>|(^|\s)~[^~\n]+~(?=\s|$)/m.test(s))return 'slack';if(/^\s{0,3}(#{1,6} |[-*] |\d+\. |> |```)|\*\*[^*]+\*\*|\[[^\]]+\]\([^)]+\)/m.test(s))return 'markdown';return 'plain';}
function slackToMarkdown(s){return s.replace(/<([^>|]+)\|([^>]+)>/g,'[$2]($1)').replace(/<(https?:[^>]+)>/g,'$1').replace(/(^|\s)\*([^*\n]+)\*(?=\s|$)/g,'$1**$2**').replace(/(^|\s)~([^~\n]+)~(?=\s|$)/g,'$1~~$2~~');}
function convert(){
 const input=$('input').value, source=$('source').value==='auto'?detect(input):$('source').value, target=$('target').value;
 $('detected').textContent=input?source.toUpperCase():'';
 try{
 let md=source==='html'?td.turndown(clean(input)):source==='slack'?slackToMarkdown(input):input;
 rich=source==='html'?clean(input):source==='plain'?'<p>'+escapeHTML(input).replace(/\n/g,'<br>')+'</p>':clean(marked.parse(md,{gfm:true,breaks:true}));
 const node=new DOMParser().parseFromString(rich,'text/html');
 node.querySelectorAll('br').forEach(el=>el.replaceWith('\n'));
 node.querySelectorAll('p,div,h1,h2,h3,h4,h5,h6,li,blockquote,pre,tr').forEach(el=>el.append('\n'));
 node.querySelectorAll('th,td').forEach(el=>el.append('\t'));
 plain=source==='plain'?input:node.body.textContent.replace(/\n{3,}/g,'\n\n').trim();
 result=target==='html'?rich:target==='plain'?plain:target==='markdown'?md:md.replace(/\[([^\]]+)\]\(([^)]+)\)/g,'<$2|$1>').replace(/^(#{1,6})\s+(.+)$/gm,'*$2*').replace(/\*\*([^*]+)\*\*/g,'*$1*').replace(/~~([^~]+)~~/g,'~$1~');
 if(!input){result='';rich='';plain='';}
 $('output').value=result;$('preview').innerHTML=rich;
 $('preview').hidden=target!=='html'||showSource;$('output').hidden=target==='html'&&!showSource;
 $('toggle').hidden=target!=='html';$('toggle').textContent=showSource?tr('查看预览','View preview'):tr('查看源码','View source');
 $('inputCount').textContent=Array.from(input).length+tr(' 字符',' characters');$('outputCount').textContent=Array.from(target==='html'?plain:result).length+tr(' 字符',' characters');$('copy').disabled=!input;
 }catch(e){$('status').textContent=tr('转换失败，请检查输入格式。','Conversion failed. Check the input format.');$('copy').disabled=true;}
}
function receiveClipboard(data){$('input').value=($('source').value==='auto'||$('source').value==='html')&&data.html?data.html:data.text;convert();$('status').textContent=$('input').value?tr('已粘贴','Pasted'):tr('剪贴板没有文本','No text on clipboard');}
function copyFinished(ok){$('status').textContent=ok?tr('已复制，可切换应用按 ⌘V 粘贴','Copied. Press ⌘V in your destination.'):tr('复制失败','Copy failed');}
$('paste').onclick=()=>window.webkit.messageHandlers.clipboard.postMessage({action:'paste'});
$('copy').onclick=()=>window.webkit.messageHandlers.clipboard.postMessage({action:'copy',text:$('target').value==='html'?plain:result,html:$('target').value==='html'?rich:''});
$('clear').onclick=()=>{$('input').value='';$('status').textContent='';convert();$('input').focus();};
$('toggle').onclick=()=>{showSource=!showSource;convert();};
$('input').oninput=()=>{clearTimeout(timer);timer=setTimeout(convert,120);$('status').textContent='';};
$('input').addEventListener('paste',e=>{const html=e.clipboardData.getData('text/html');if(html&&($('source').value==='auto'||$('source').value==='html')){e.preventDefault();$('input').setRangeText(html,$('input').selectionStart,$('input').selectionEnd,'end');convert();}});
$('source').onchange=$('target').onchange=convert;
$('preview').addEventListener('click',e=>{if(e.target.closest('a'))e.preventDefault();});
setLanguage(true);
