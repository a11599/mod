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

mod = build build$(ps)$(build) build$(ps)$(build)$(ps)mod &
	build$(ps)$(build)$(ps)mod$(ps)convert.obj &
	build$(ps)$(build)$(ps)mod$(ps)dev_dac.obj &
	build$(ps)$(build)$(ps)mod$(ps)dev_none.obj &
	build$(ps)$(build)$(ps)mod$(ps)dev_sb.obj &
	build$(ps)$(build)$(ps)mod$(ps)player.obj &
	build$(ps)$(build)$(ps)mod$(ps)routine.obj &
	build$(ps)$(build)$(ps)mod$(ps)wtbl_sw.obj

# Validate build target environment value

build_ok = 0
!ifeq build debug
%log_level = debug
debug_objs = ..$(ps)pmi$(ps)build$(ps)$(build)$(ps)rtl$(ps)log.obj
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

# Build library

incremental: $(mod)
full: clean $(mod)

# Create binary distribution package

dist: .SYMBOLIC
	$(watcom_bin_dir)wmake full
	$(watcom_bin_dir)wmake build=release full
	@if not exist dist mkdir dist
	@if not exist dist$(ps)debug mkdir dist$(ps)debug
	@if not exist dist$(ps)debug$(ps)mod mkdir dist$(ps)debug$(ps)mod
	@if not exist dist$(ps)release$(ps)mod mkdir dist$(ps)release$(ps)mod
	@$(del) dist$(ps)debug$(ps)mod$(ps)*.*
	@$(del) dist$(ps)release$(ps)mod$(ps)*.*
	@$(copy) build$(ps)debug$(ps)mod$(ps)*.obj dist$(ps)debug$(ps)mod
	@$(copy) build$(ps)release$(ps)mod$(ps)*.obj dist$(ps)release$(ps)mod

# Cleanup

clean: .SYMBOLIC .MULTIPLE
	@if exist build$(ps)$(build)$(ps)mod $(del) build$(ps)$(build)$(ps)mod$(ps)*.*
	@if exist build$(ps)$(build)$(ps)mod rmdir build$(ps)$(build)$(ps)mod


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

build$(ps)$(build): build .SYMBOLIC .ALWAYS
	@if not exist build$(ps)$(build) mkdir build$(ps)$(build)

build$(ps)$(build)$(ps)mod: build$(ps)$(build) .SYMBOLIC .ALWAYS
	@if not exist build$(ps)$(build)$(ps)mod mkdir build$(ps)$(build)$(ps)mod

# .inc file dependencies

src$(ps)mod$(ps)api$(ps)mod.inc: &
	src$(ps)mod$(ps)consts$(ps)public.inc &
	src$(ps)mod$(ps)structs$(ps)public.inc

	$(watcom_bin_dir)wtouch src$(ps)mod$(ps)api$(ps)mod.inc

# .obj file dependencies with included external files and build instructions

build$(ps)$(build)$(ps)mod$(ps)convert.obj: src$(ps)mod$(ps)convert.asm

	$(nasm_bin) $(nasm_pe_opts) $[@ -o $^@

build$(ps)$(build)$(ps)mod$(ps)dev_dac.obj: src$(ps)mod$(ps)dev_dac.asm &
	..$(ps)pmi$(ps)src$(ps)pmi$(ps)api$(ps)pmi.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)string.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)log.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)irq.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)timer.inc &
	src$(ps)mod$(ps)config.inc &
	src$(ps)mod$(ps)api$(ps)wtbl_sw.inc &
	src$(ps)mod$(ps)api$(ps)routine.inc &
	src$(ps)mod$(ps)structs$(ps)public.inc &
	src$(ps)mod$(ps)consts$(ps)public.inc &
	src$(ps)mod$(ps)structs$(ps)dev.inc &
	src$(ps)mod$(ps)consts$(ps)dev.inc

	$(nasm_bin) $(nasm_pe_opts) $[@ -o $^@

build$(ps)$(build)$(ps)mod$(ps)dev_none.obj: src$(ps)mod$(ps)dev_none.asm &
	..$(ps)pmi$(ps)src$(ps)pmi$(ps)api$(ps)pmi.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)string.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)log.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)irq.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)timer.inc &
	src$(ps)mod$(ps)api$(ps)routine.inc &
	src$(ps)mod$(ps)structs$(ps)dev.inc

	$(nasm_bin) $(nasm_pe_opts) $[@ -o $^@

build$(ps)$(build)$(ps)mod$(ps)dev_sb.obj: src$(ps)mod$(ps)dev_sb.asm &
	..$(ps)pmi$(ps)src$(ps)pmi$(ps)api$(ps)pmi.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)env_arg.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)string.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)log.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)irq.inc &
	src$(ps)mod$(ps)config.inc &
	src$(ps)mod$(ps)api$(ps)wtbl_sw.inc &
	src$(ps)mod$(ps)api$(ps)routine.inc &
	src$(ps)mod$(ps)structs$(ps)public.inc &
	src$(ps)mod$(ps)consts$(ps)public.inc &
	src$(ps)mod$(ps)structs$(ps)dev.inc &
	src$(ps)mod$(ps)consts$(ps)dev.inc

	$(nasm_bin) $(nasm_pe_opts) $[@ -o $^@

build$(ps)$(build)$(ps)mod$(ps)player.obj: src$(ps)mod$(ps)player.asm &
	..$(ps)pmi$(ps)src$(ps)pmi$(ps)api$(ps)pmi.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)env_arg.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)string.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)log.inc &
	src$(ps)mod$(ps)config.inc &
	src$(ps)mod$(ps)api$(ps)convert.inc &
	src$(ps)mod$(ps)api$(ps)routine.inc &
	src$(ps)mod$(ps)structs$(ps)public.inc &
	src$(ps)mod$(ps)consts$(ps)public.inc &
	src$(ps)mod$(ps)structs$(ps)mod_file.inc &
	src$(ps)mod$(ps)structs$(ps)dev.inc

	$(nasm_bin) $(nasm_pe_opts) $[@ -o $^@

build$(ps)$(build)$(ps)mod$(ps)routine.obj: src$(ps)mod$(ps)routine.asm &
	..$(ps)pmi$(ps)src$(ps)pmi$(ps)api$(ps)pmi.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)string.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)log.inc &
	src$(ps)mod$(ps)config.inc &
	src$(ps)mod$(ps)api$(ps)convert.inc &
	src$(ps)mod$(ps)structs$(ps)public.inc &
	src$(ps)mod$(ps)structs$(ps)mod_file.inc &
	src$(ps)mod$(ps)consts$(ps)dev.inc &
	src$(ps)mod$(ps)structs$(ps)dev.inc

	$(nasm_bin) $(nasm_pe_opts) $[@ -o $^@

build$(ps)$(build)$(ps)mod$(ps)wtbl_sw.obj: src$(ps)mod$(ps)wtbl_sw.asm &
	..$(ps)pmi$(ps)src$(ps)pmi$(ps)api$(ps)pmi.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)string.inc &
	..$(ps)pmi$(ps)src$(ps)rtl$(ps)api$(ps)log.inc &
	src$(ps)mod$(ps)config.inc &
	src$(ps)mod$(ps)structs$(ps)public.inc &
	src$(ps)mod$(ps)consts$(ps)dev.inc &
	src$(ps)mod$(ps)structs$(ps)mod_file.inc

	$(nasm_bin) $(nasm_pe_opts) $[@ -o $^@
