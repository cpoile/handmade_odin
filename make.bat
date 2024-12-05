@echo off

if not exist c:\Users\Chris\git\odin\handmade_hero\build mkdir c:\Users\Chris\git\odin\handmade_hero\build

odin build c:\Users\Chris\git\odin\handmade_hero\src -out:c:\Users\Chris\git\odin\handmade_hero\build\handmade.exe -debug -define:HANDMADE_INTERNAL=true
