#!/usr/bin/env python3
"""Validate committed translations offline; never call a translation service at runtime."""
import pathlib,re,json
root=pathlib.Path(__file__).resolve().parent.parent
source=root/'Sources'
# Balanced Swift string parsing, including expressions nested inside interpolation.
def string_end(s,i):
 j=i+1
 while j<len(s):
  if s[j]=='"': return j+1
  if s[j]=='\\':
   if s[j+1:j+2]=='(':
    j=expr_end(s,j+2)
   else:j+=2
  else:j+=1
 raise ValueError(s[i:i+100])
def expr_end(s,j):
 depth=1
 while depth:
  if s[j]=='"':j=string_end(s,j);continue
  if s[j]=='(':depth+=1
  if s[j]==')':depth-=1
  j+=1
 return j

def key(raw):
 out='';j=0;n=0
 while j<len(raw):
  if raw[j:j+2]=='\\(':
   e=expr_end(raw,j+2);out+='{'+str(n)+'}';n+=1;j=e
  else:out+=raw[j];j+=1
 return out.replace('\\n','\n').replace('\\"','"').replace('\\\\','\\')

resources=source/'MonitorCore/Localization/Resources'
catalogs={p.stem:json.loads(p.read_text()) for p in resources.glob('*.json')}
assert set(catalogs)=={'en','ru','es','fr','de','pt-BR','it','zh-Hans','ja','ko','ar','hi'}
base=catalogs['ru']
for language, catalog in catalogs.items():
    assert set(catalog)==set(base), f'{language}: missing or extra messages'
    for message, translation in catalog.items():
        assert translation.strip(), (language,message)
        assert sorted(re.findall(r'\{\d+\}',message))==sorted(re.findall(r'\{\d+\}',translation)), (language,message)
        assert 'MACPULSE_' not in translation
for path in source.rglob('*.swift'):
    text=path.read_text()
    for match in re.finditer(r'(?<![A-Za-z])L\("',text):
        i=match.end()-1
        message=key(text[i+1:string_end(text,i)-1])
        assert message in base, f'{path}: missing message {message!r}'
print(f'Validated {len(base)} messages in {len(catalogs)} languages and all L() call sites.')
