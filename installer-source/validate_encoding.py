from pathlib import Path
import re

def validate_encoding(payload):
    """Reject broken UTF-8 and UTF-8 decoded through Windows-1251 in UI sources."""
    mapping={}
    for number in list(range(0x400,0x530))+list(range(0x2000,0x2040))+[0xa0,0xab,0xbb,0xd7,0x2116]:
        char=chr(number)
        try:broken=char.encode('utf-8').decode('cp1251')
        except UnicodeError:continue
        if broken!=char:mapping[broken]=char
    pattern=re.compile('|'.join(re.escape(s) for s in sorted(mapping,key=len,reverse=True)))
    checked=0
    for folder in ['portable_config','defaults']:
        for p in (Path(payload)/folder).rglob('*'):
            if p.is_file() and p.suffix in ('.lua','.conf','.json'):
                text=p.read_text(encoding='utf-8-sig',errors='strict')
                match=pattern.search(text)
                if match:raise ValueError('Broken Russian encoding in '+str(p)+' near '+repr(match.group()))
                checked+=1
    return checked

if __name__=='__main__':
    import sys
    print('UTF-8 validated:',validate_encoding(sys.argv[1]),'files')
