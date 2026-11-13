#!/usr/bin/env python3
"""Convert every .xml file under an addon directory into one Lua table file:
   return { ["relative/path.xml"] = {tag=..., attr={...}, text=..., children={...}}, ... }
Used by the mock WoW harness to instantiate the addon's XML frames."""
import sys, pathlib, xml.etree.ElementTree as ET

def strip_ns(tag):
    return tag.split('}', 1)[1] if '}' in tag else tag

def lua_str(s):
    level = 0
    while (']' + '=' * level + ']') in s or s.endswith(']' + '=' * level):
        level += 1
    eq = '=' * level
    # a leading newline inside a long bracket is dropped by Lua; keep it
    return '[' + eq + '[\n' + s + ']' + eq + ']'

def conv(el, out, indent=0):
    pad = ' ' * indent
    out.append(pad + '{tag=' + lua_str(strip_ns(el.tag)) + ',')
    if el.attrib:
        out.append(pad + ' attr={')
        for k, v in el.attrib.items():
            out.append(pad + '  [ ' + lua_str(strip_ns(k)) + ' ]=' + lua_str(v) + ',')
        out.append(pad + ' },')
    text = (el.text or '')
    if text.strip():
        out.append(pad + ' text=' + lua_str(text) + ',')
    kids = list(el)
    if kids:
        out.append(pad + ' children={')
        for k in kids:
            if not isinstance(k.tag, str):   # comments
                continue
            conv(k, out, indent + 2)
        out.append(pad + ' },')
    out.append(pad + '},')

def main(root, dest):
    root = pathlib.Path(root)
    out = ['return {']
    for xml in sorted(root.rglob('*.xml')):
        rel = xml.relative_to(root).as_posix()
        tree = ET.parse(xml)
        out.append('[ ' + lua_str(rel) + ' ] = ')
        conv(tree.getroot(), out, 2)
    out.append('}')
    pathlib.Path(dest).write_text('\n'.join(out), encoding='utf-8')

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
