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

IF __NABU_BARE__
    ; "Bare" subtype, no stdio etc.  Assumes you are using DJ Sures' NABU_LIB
    ; (see https://nabu.ca/) which is a hardware library included as source
    ; code that does everything from VDP print support to interrupt handling.
;    defc    TAR__fputc_cons_generic = 0 ; So our fputc_cons_native gets used.
;    defc    TAR__fgetc_cons_inkey = 0
;    defc    TAR__no_ansifont = 1
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
ENDIF

    ; Need these for switching ROM bank in and out, control bits are in an
    ; I/O port on the sound chip of all places.
    PUBLIC  PSG_AY_REG
    PUBLIC  PSG_AY_DATA
    defc    PSG_AY_REG = $40
    defc    PSG_AY_DATA = $41

    ; We don't use atexit() functionality, so don't save space for them.
    defc    TAR__clib_exit_stack_size = 0

    ; Put the stack below $ff00, interrupt table will be at $ff00 and above. 
    defc    TAR__register_sp = $ff00

    INCLUDE "crt/classic/crt_rules.inc"

    org     CRT_ORG_CODE

    ; Three bytes of unused stuff, Nabu's ROM loader jumps into code just past
    ; them, so put in 0 = NOP.  May have been used for a 24 bit size of the
    ; segment or something else NABU Networky.
    defb    0,0,0
    jr      start
    defq    __CPU_CLOCK ; TODO: Remove.  Just testing defines from nabu.cfg.
start:
IF !__NABU_BARE__
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

IF !__NABU_BARE__
    ; Code is shared with CP/M. This is a noop, but pulls in code
    ; into crt0_init and crt0_exit
    call    cpm_platform_init 
ENDIF

    INCLUDE "crt/classic/crt_init_atexit.inc"
IF !__NABU_BARE__
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_init.inc"
ENDIF
    INCLUDE "crt/classic/crt_init_heap.inc"

    ; Turn on or off interrupts.
    INCLUDE "crt/classic/crt_init_eidi.inc"

    call    _main
__Exit:
    push    hl ; Save exit code.
    call    crt0_exit

IF !__NABU_BARE__
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_exit.inc"
ENDIF

    pop     bc
    INCLUDE "crt/classic/crt_exit_eidi.inc"

IF !__NABU_BARE__
__restore_sp_onexit:
    ld      sp,0  ; Modified code in here with saved stack pointer.
    ret
ELSE
    ; Really should switch ROM bank in and jump to the reset vector, though we
    ; may be running code in the RAM area used by the ROM so that may not work.
BareEnd:
    halt
    jr BareEnd
ENDIF

l_dcal:
    jp      (hl)

IF !__NABU_BARE__
    ; Selects print formats and stdio functions to use.
    INCLUDE "crt/classic/crt_runtime_selection.inc"
ENDIF
    INCLUDE	"crt/classic/crt_section.inc"

IF !__NABU_BARE__
    INCLUDE "target/nabu/classic/nabu_hccabuf.asm"
    ; And include handling disabling screenmodes
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_disable.inc"
ENDIF

