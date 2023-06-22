#------------------------------------------------------------------------------
# Therapy MOD player makefile
#------------------------------------------------------------------------------

# Compiler options

nasm_pe_opts = -i "src" -i "../pmi/src" -f win32

# Build mode
# Set to "release" in command line parameter to create a release build.
# Example for full recompilation of the release version:
# wmake build=release full

build = debug

# Target object files

mod = build build\$(build) build\$(build)\mod &
	build\$(build)\mod\convert.obj &
	build\$(build)\mod\dev_dac.obj &
	build\$(build)\mod\dev_none.obj &
	build\$(build)\mod\dev_sb.obj &
	build\$(build)\mod\player.obj &
	build\$(build)\mod\routine.obj &
	build\$(build)\mod\wtbl_sw.obj

# Validate build target environment value

build_ok = 0
!ifeq build debug
%log_level = debug
debug_objs = ..\pmi\build\$(build)\rtl\log.obj
build_ok = 1
!endif
!ifeq build release
%log_level =
debug_objs =
build_ok = 1
!endif
!ifneq build_ok 1
pmi = abort
rtl = abort
!endif

# Append \ at the end of nasm/watcom path variables if not empty

!ifneq nasm_dir
nasm_dir = $(nasm_dir)\
!endif
!ifneq watcom_dir
watcom_dir = $(watcom_dir)\
!endif

# Build library

incremental: $(mod)
full: clean $(mod)

# Create binary distribution package

dist: .SYMBOLIC
	$(watcom_dir)wmake full
	$(watcom_dir)wmake build=release full
	@if not exist dist mkdir dist
	@if not exist dist\debug mkdir dist\debug
	@if not exist dist\debug\mod mkdir dist\debug\mod
	@if not exist dist\release\mod mkdir dist\release\mod
	@del /q dist\debug\mod\*.*
	@del /q dist\release\mod\*.*
	@copy build\debug\mod\*.obj dist\debug\mod
	@copy build\release\mod\*.obj dist\release\mod

# Cleanup

clean: .SYMBOLIC .MULTIPLE
	@if exist build\$(build)\mod del /q build\$(build)\mod\*.*
	@if exist build\$(build)\mod rmdir build\$(build)\mod


#------------------------------------------------------------------------------
# Build application
#------------------------------------------------------------------------------

# Abort if unknown build environment is given

abort:
	echo "$(build)" is not a valid build target.
	@%abort

# Create directory for binary files

build: .SYMBOLIC .ALWAYS
	@if not exist build mkdir build

build\$(build): build .SYMBOLIC .ALWAYS
	@if not exist build\$(build) mkdir build\$(build)

build\$(build)\mod: build\$(build) .SYMBOLIC .ALWAYS
	@if not exist build\$(build)\mod mkdir build\$(build)\mod

# .inc file dependencies

src\mod\api\mod.inc: &
	src\mod\consts\public.inc &
	src\mod\structs\public.inc

	$(watcom_dir)wtouch src\mod\api\mod.inc

# .obj file dependencies with included external files and build instructions

build\$(build)\mod\convert.obj: src\mod\convert.asm

	$(nasm_dir)nasm $(nasm_pe_opts) $[@ -o $^@

build\$(build)\mod\dev_dac.obj: src\mod\dev_dac.asm &
	..\pmi\src\pmi\api\pmi.inc &
	..\pmi\src\rtl\api\string.inc &
	..\pmi\src\rtl\api\log.inc &
	..\pmi\src\rtl\api\irq.inc &
	..\pmi\src\rtl\api\timer.inc &
	src\mod\config.inc &
	src\mod\api\wtbl_sw.inc &
	src\mod\api\routine.inc &
	src\mod\structs\public.inc &
	src\mod\consts\public.inc &
	src\mod\structs\dev.inc &
	src\mod\consts\dev.inc

	$(nasm_dir)nasm $(nasm_pe_opts) $[@ -o $^@

build\$(build)\mod\dev_none.obj: src\mod\dev_none.asm &
	..\pmi\src\pmi\api\pmi.inc &
	..\pmi\src\rtl\api\string.inc &
	..\pmi\src\rtl\api\log.inc &
	..\pmi\src\rtl\api\irq.inc &
	..\pmi\src\rtl\api\timer.inc &
	src\mod\api\routine.inc &
	src\mod\structs\dev.inc

	$(nasm_dir)nasm $(nasm_pe_opts) $[@ -o $^@

build\$(build)\mod\dev_sb.obj: src\mod\dev_sb.asm &
	..\pmi\src\pmi\api\pmi.inc &
	..\pmi\src\rtl\api\env_arg.inc &
	..\pmi\src\rtl\api\string.inc &
	..\pmi\src\rtl\api\log.inc &
	..\pmi\src\rtl\api\irq.inc &
	src\mod\config.inc &
	src\mod\api\wtbl_sw.inc &
	src\mod\api\routine.inc &
	src\mod\structs\public.inc &
	src\mod\consts\public.inc &
	src\mod\structs\dev.inc &
	src\mod\consts\dev.inc

	$(nasm_dir)nasm $(nasm_pe_opts) $[@ -o $^@

build\$(build)\mod\player.obj: src\mod\player.asm &
	..\pmi\src\pmi\api\pmi.inc &
	..\pmi\src\rtl\api\env_arg.inc &
	..\pmi\src\rtl\api\string.inc &
	..\pmi\src\rtl\api\log.inc &
	src\mod\config.inc &
	src\mod\api\convert.inc &
	src\mod\api\routine.inc &
	src\mod\structs\public.inc &
	src\mod\consts\public.inc &
	src\mod\structs\mod_file.inc &
	src\mod\structs\dev.inc

	$(nasm_dir)nasm $(nasm_pe_opts) $[@ -o $^@

build\$(build)\mod\routine.obj: src\mod\routine.asm &
	..\pmi\src\pmi\api\pmi.inc &
	..\pmi\src\rtl\api\string.inc &
	..\pmi\src\rtl\api\log.inc &
	src\mod\config.inc &
	src\mod\api\convert.inc &
	src\mod\structs\public.inc &
	src\mod\structs\mod_file.inc &
	src\mod\consts\dev.inc &
	src\mod\structs\dev.inc

	$(nasm_dir)nasm $(nasm_pe_opts) $[@ -o $^@

build\$(build)\mod\wtbl_sw.obj: src\mod\wtbl_sw.asm &
	..\pmi\src\pmi\api\pmi.inc &
	..\pmi\src\rtl\api\string.inc &
	..\pmi\src\rtl\api\log.inc &
	src\mod\config.inc &
	src\mod\structs\public.inc &
	src\mod\consts\dev.inc &
	src\mod\structs\mod_file.inc

	$(nasm_dir)nasm $(nasm_pe_opts) $[@ -o $^@
