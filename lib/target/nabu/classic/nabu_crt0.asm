;
;	Startup for Nabu, a circa 1981 Z80 based computer.
;

    module  nabu_crt0 


;--------
; Include zcc_opt.def to access defines etc, dynamically made at build time.
;--------

    defc    crt0 = 1
    INCLUDE "zcc_opt.def"

;--------
; Some scope definitions
;--------

    EXTERN  _main           ;main() is always external to crt0 code
    PUBLIC  __Exit          ;jp'd to by exit()
    PUBLIC  l_dcal          ;jp(hl) - used by compiler to jump indirect.

IFNDEF      CRT_ORG_CODE
    defc    CRT_ORG_CODE = 0x0000
ENDIF

    ; By default we don't have any rst handlers, since the interrupt table
    ; doesn't start at location 0.
    defc    TAR__crt_enable_rst = 0

IF NABU_BARE_ASM
    ; "Bare" subtype, no stdio etc.  Assumes you are using DJ Sures' NABU_LIB
    ; (see https://nabu.ca/) which is a hardware library included as source
    ; code that does everything from VDP print support to interrupt handling.
ELSE
    ; Subtype "Default" has console output and input.
    defc    TAR__fputc_cons_generic = 1
    defc    CONSOLE_COLUMNS = 32
IF !DEFINED_CONSOLE_ROWS
    defc    CONSOLE_ROWS = 24
ENDIF
    defc    CRT_KEY_DEL = 127
IFNDEF CLIB_DEFAULT_SCREEN_MODE
    ; Sets a VDP screen mode.
    defc    CLIB_DEFAULT_SCREEN_MODE = 2
ENDIF
    EXTERN  cpm_platform_init
    EXTERN  vdp_set_mode
ENDIF ; NABU_BARE_ASM

    ; We don't include atexit() functionality, so don't save space for them.
    defc    TAR__clib_exit_stack_size = 0

    ; Put the stack below $ff00, interrupt table will be at $ff00 and above. 
    defc    TAR__register_sp = $ff00

    INCLUDE "crt/classic/crt_rules.inc"

    org     CRT_ORG_CODE

    ; Three bytes of unused stuff, Nabu's ROM loader jumps into code just past
    ; them, so put in 0 = NOP.  May have been used for a 24 bit size of the
    ; segment or something else NABU Networky.
    defb    0,0,0

IF NABU_BARE_ASM
    ; Relocate the loaded program and data to the actual origin location, since
    ; the NABU ROMs load the segment somewhere after the ROMs, and it varies
    ; from one ROM version to another!  The most common ROM loads at $140d.
    ; So our code here needs to be position independent.  It works by writing
    ; some code to near the end of RAM ($FFE0) to get the program counter, and
    ; do an ldir to move the program.

    defc    IO_CONTROL = $0 ; I/O address of the control register.
    defc    CONTROL_ROMSEL = $01 ; Bit which controls ROM enable.
    defc    CONTROL_VDOBUF = $02 ; Bit which controls video output choice.
    defc    NABU_BARE_STUB_DESTINATION = $FFE0
    EXTERN  __RODATA_END_tail

nabu_bare_relocate:
    ; Switch out boot ROM so RAM is visible, connect VDP to video output.
    ld  a, CONTROL_ROMSEL | CONTROL_VDOBUF
    out (IO_CONTROL), a

    ; Write a little program stub into RAM at known memory addresses, which
    ; hopefully won't be overwritten by our program when it gets loaded into
    ; RAM at a higher address (up to 8K higher) than we expected.
    ld  hl, nabu_bare_stub_start
    ld  de, NABU_BARE_STUB_DESTINATION
    ld  bc, nabu_bare_stub_end-nabu_bare_stub_start
    ldir

    ; Get address of nabu_bare_pc: as loaded somewhere in memory into HL.
    call NABU_BARE_STUB_DESTINATION+nabu_bare_stub_get_pc-nabu_bare_stub_start
nabu_bare_pc:

    ; Set up the registers for an ldir to move the program down in memory.
    ; Doesn't work for moving it up in memory.
    ld   bc, nabu_bare_pc-CRT_ORG_CODE
    and  a, a ; Clear the carry flag.
    sbc  hl, bc ; HL set to address of loaded start of this program.
    ld   de, CRT_ORG_CODE ; Desired beginning of program in RAM.
    ld   bc, __RODATA_END_tail-CRT_ORG_CODE ; Size of this program in bytes.
    jp   NABU_BARE_STUB_DESTINATION+nabu_bare_stub_ldir-nabu_bare_stub_start

nabu_bare_stub_start:
nabu_bare_stub_get_pc:
    pop hl
    jp  (hl)
nabu_bare_stub_ldir:
    ldir
    jp  start ; Continue on with the rest of the C runtime initialisation.
nabu_bare_stub_end:
ENDIF ; NABU_BARE_ASM

start:
IF !NABU_BARE_ASM
    ; Save stack pointer by modifying code, so it gets restored on exit.
    ld      (__restore_sp_onexit+1),sp
ENDIF
    INCLUDE "crt/classic/crt_init_sp.inc"
    ; Set interrupt system mode 2, with interrupt table at $ff00.
    di
    ld      a,$ff
    ld      i,a
    im      2

    ; Setup BSS memory and perform other initialisation
    call    crt0_init

IF !NABU_BARE_ASM
    ; Code is shared with CP/M. This is a noop, but pulls in code
    ; into crt0_init and crt0_exit
    call    cpm_platform_init 
ENDIF

IF !NABU_BARE_ASM
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_init.inc"
ENDIF
    INCLUDE "crt/classic/crt_init_heap.inc"

    ; Turn on or off interrupts as specified by another define.
    INCLUDE "crt/classic/crt_init_eidi.inc"

    call    _main
__Exit:
    push    hl ; Save exit code.
    call    crt0_exit

IF !NABU_BARE_ASM
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_exit.inc"
ENDIF

    pop     bc
    INCLUDE "crt/classic/crt_exit_eidi.inc"

IF !NABU_BARE_ASM
__restore_sp_onexit:
    ld      sp,0  ; Modified code in here with saved stack pointer.
    ret
ELSE ; NABU_BARE_ASM
    ; Really should switch ROM bank in and jump to the reset vector, though we
    ; may be running code in the RAM area used by the ROM so that may not work.
BareEnd:
    halt
    jr BareEnd
ENDIF ; !NABU_BARE_ASM

l_dcal:
    jp      (hl)

IF !NABU_BARE_ASM
    ; Selects print formats and stdio functions to use.  But not in bare mode!
    INCLUDE "crt/classic/crt_runtime_selection.inc"
ENDIF
    INCLUDE	"crt/classic/crt_section.inc"

IF !NABU_BARE_ASM
    INCLUDE "target/nabu/classic/nabu_hccabuf.asm"
    ; And include handling disabling screenmodes
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_disable.inc"
ENDIF

