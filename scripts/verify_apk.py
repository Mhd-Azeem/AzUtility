import sys,struct,zipfile,hashlib,json
from pathlib import Path

file=Path(sys.argv[1]); manifest=None
with zipfile.ZipFile(file) as archive:
    data=archive.read('AndroidManifest.xml')
    abis=sorted({name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')})
strings=[]; tags=[]
def u32(offset): return struct.unpack_from('<I',data,offset)[0]
def u16(offset): return struct.unpack_from('<H',data,offset)[0]
def length8(offset):
    first=data[offset]
    return (((first&0x7f)<<8)|data[offset+1],offset+2) if first&0x80 else (first,offset+1)
def length16(offset):
    first=u16(offset)
    return (((first&0x7fff)<<16)|u16(offset+2),offset+4) if first&0x8000 else (first,offset+2)
position=u16(2)
while position<len(data):
    kind,header,size=struct.unpack_from('<HHI',data,position)
    if not size: raise ValueError('Invalid XML chunk')
    if kind==1:
        count=u32(position+8); flags=u32(position+16); start=position+u32(position+20)
        for i in range(count):
            offset=start+u32(position+header+i*4)
            if flags&0x100:
                _,offset=length8(offset); length,offset=length8(offset)
                strings.append(data[offset:offset+length].decode('utf-8'))
            else:
                length,offset=length16(offset); strings.append(data[offset:offset+length*2].decode('utf-16le'))
    if kind==0x102:
        name=strings[u32(position+20)]; count=u16(position+28); attribute_size=u16(position+26)
        attributes={}
        for i in range(count):
            offset=position+16+u16(position+24)+i*attribute_size
            key=strings[u32(offset+4)]; raw=u32(offset+8); value_type=data[offset+15]; value=u32(offset+16)
            attributes[key]=strings[raw] if raw!=0xffffffff else strings[value] if value_type==3 else bool(value) if value_type==18 else value
        if name in ['manifest','uses-sdk','application','activity']: tags.append({'element':name,**attributes})
    position+=size
result={'file':file.name,'sha256':hashlib.file_digest(file.open('rb'),'sha256').hexdigest(),'abis':abis,'manifest':tags}
print(json.dumps(result,indent=2))
assert tags[0]['package']=='com.az.utility'
assert abis==['arm64-v8a']
assert next(tag for tag in tags if tag['element']=='uses-sdk')['targetSdkVersion']>=35
