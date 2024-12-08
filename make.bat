@echo off

if not exist c:\Users\Chris\git\odin\handmade_hero\build mkdir c:\Users\Chris\git\odin\handmade_hero\build

rem We're manually listing vets because I really don't want the -vet-using-* included -- it's too useful for win32

rem sometimes add  -vet-unused and -vet-unused-variables to check, but during game dev it's too restrictive

odin build c:\Users\Chris\git\odin\handmade_hero\src -out:c:\Users\Chris\git\odin\handmade_hero\build\handmade.exe -debug -define:HANDMADE_INTERNAL=true -vet-cast -vet-semicolon -vet-shadowing -vet-style -vet-unused-imports
