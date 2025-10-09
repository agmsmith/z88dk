;
;	Startup for Nabu
;

    module  nabu_crt0 


;--------
; Include zcc_opt.def to find out some info
;--------

    defc    crt0 = 1
    INCLUDE "zcc_opt.def"

;--------
; Some scope definitions
;--------

    EXTERN  _main           ;main() is always external to crt0 code

    PUBLIC  __Exit         ;jp'd to by exit()
    PUBLIC  l_dcal          ;jp(hl)

IF DEFINED_CRT_ORG_BSS
    defc    __crt_org_bss = CRT_ORG_BSS
ENDIF

IFNDEF      CRT_ORG_CODE
    defc    CRT_ORG_CODE = 0x0000
ENDIF

IF CRT_ORG_CODE = 0x0000
    ; By default we don't have any rst handlers
    defc    TAR__crt_enable_rst = $0000
ENDIF

IFDEF __NABU_BARE__
    ; Bare subtype, no stdio etc.  Assumes you are using DJ Sures' NABU_LIB
    ; which is a  user level hardware library included as source code.
    defc    TAR__fputc_cons_generic = 0
ELSE
    ; Default subtype has console output and input.
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
    defw    __CPU_CLOCK ; Just testing defines from nabu.cfg.
start:
IFNDEF __NABU_BARE__
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

IFNDEF __NABU_BARE__
    ; Code is shared with CP/M. This is a noop, but pulls in code
    ; into crt0_init and crt0_exit
    call    cpm_platform_init 
ENDIF

    INCLUDE "crt/classic/crt_init_atexit.inc"
IFNDEF __NABU_BARE__
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_init.inc"
ENDIF
    INCLUDE "crt/classic/crt_init_heap.inc"

    ; Turn on or off interrupts.
    INCLUDE "crt/classic/crt_init_eidi.inc"

    call    _main
__Exit:
    push    hl ; Save exit code.
    call    crt0_exit

IFNDEF __NABU_BARE__
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_exit.inc"
ENDIF

    pop     bc
    INCLUDE "crt/classic/crt_exit_eidi.inc"

IFNDEF __NABU_BARE__
__restore_sp_onexit:
    ld      sp,0  ; Modified code here with saved stack pointer.
    ret
ELSE
    ; Really should switch ROM bank in and jump to the reset vector.
BareEnd:
    halt
    jr BareEnd
ENDIF

l_dcal:
    jp      (hl)


    INCLUDE "crt/classic/crt_runtime_selection.inc" 
    INCLUDE	"crt/classic/crt_section.inc"

IFNDEF __NABU_BARE__
    INCLUDE "target/nabu/classic/nabu_hccabuf.asm"
    ; And include handling disabling screenmodes
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_disable.inc"
ENDIF

