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
    defc    NABU_BARE_STUB_DESTINATION = $FFE0 ; Should be above temp stack.
    defc    NABU_BARE_TEMP_STACK = $FF00
    EXTERN  __RODATA_END_tail

nabu_bare_relocate:
    di	; We're not ready to handle interrupts, need an interrupt table etc.
    ld  sp, NABU_BARE_TEMP_STACK ; Temporary stack, away from loaded code.
    ; Switch out boot ROM so RAM is visible, connect VDP to video output.
    ld  a, CONTROL_ROMSEL | CONTROL_VDOBUF
    out (IO_CONTROL), a

    ; Get the current program counter, where in memory are we?
    ld  hl, NABU_BARE_STUB_DESTINATION
    ld  (hl), $e1 ; pop hl opcode.
    inc hl
    ld  (hl), $e9 ; jp (hl) opcode.
    call NABU_BARE_STUB_DESTINATION ; Returns with program counter in HL.
nabu_bare_pc: ; HL points to nabu_bare_pc address as loaded in memory. 

    ; Write a little program stub (to move the main program around) into RAM at
    ; a known memory addresses, hopefully above where our program was loaded
    ; into memory.  Note that it can be loaded up to 8K higher, based on maximum
    ; 8K ROM size starting at location zero assuming the ROM loader isn't silly.

    ld   bc, nabu_bare_pc-CRT_ORG_CODE
    and  a, a ; Clear the carry flag.
    sbc  hl, bc ; HL set to address of origin of this program, after loading.
    push hl ; Useful, save for later.
    ld   bc, nabu_bare_stub_start-CRT_ORG_CODE
    add  hl, bc ; Get address of our stub code.
    ld   de, NABU_BARE_STUB_DESTINATION ; Desired beginning of program in RAM.
    ld   bc, nabu_bare_stub_end-nabu_bare_stub_start ; Size of our stub code.
    ldir

    ; Set up the registers for an ldir to move the program down in memory.
    ; Doesn't work for moving it up in memory.  When done, jumps to start: in
    ; the moved code.
    pop  hl ; Address of origin of this program, as loaded in RAM.
    ld   de, CRT_ORG_CODE ; Desired beginning of program in RAM.
    ld   bc, __RODATA_END_tail-CRT_ORG_CODE ; Size of this program in bytes.
    jp   NABU_BARE_STUB_DESTINATION+nabu_bare_stub_ldir-nabu_bare_stub_start

nabu_bare_stub_start:
nabu_bare_stub_ldir:
    ldir
    jp  start ; Continue on with the rest of the C runtime initialisation.
nabu_bare_stub_reset:
    ld  a, CONTROL_VDOBUF ; Turn off RAM, put back boot ROM, leave video on.
    out (IO_CONTROL), a
    jp  0 ; Start at location 0 in the ROM, likely the boot code.
nabu_bare_stub_end:
ENDIF ; NABU_BARE_ASM

start:
    di ; Best to avoid interrupts while moving the stack pointer around.
IF !NABU_BARE_ASM
    ; Save stack pointer by modifying later code, so it gets restored on exit.
    ld      (__restore_sp_onexit+1),sp
ENDIF
    INCLUDE "crt/classic/crt_init_sp.inc" ; Sets the stack pointer.
    ; Set interrupt system mode 2, with interrupt table at $ff00.
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

IF !NABU_BARE_ASM
    ; Turn on or off interrupts as specified by __crt_enable_eidi flags.
    INCLUDE "crt/classic/crt_init_eidi.inc"
ENDIF

    call    _main
__Exit:
    push    hl ; Save exit code.
    call    crt0_exit

IF !NABU_BARE_ASM
    INCLUDE "crt/classic/tms99x8/tms99x8_mode_exit.inc"
ENDIF

    pop     bc ; Exit code.

IF !NABU_BARE_ASM
    INCLUDE "crt/classic/crt_exit_eidi.inc"
__restore_sp_onexit:
    ld      sp, 0  ; Modified code in here with saved stack pointer.
    ret
ELSE ; NABU_BARE_ASM
    ; Switch the ROM bank in and jump to the location zero reset code.  Since
    ; this code may be in the RAM area used by the ROM, use a stub in high
    ; memory.
BareEnd:
    di
    im  0  ; Use stock interrupt mode like a hardware reset would do.
    ld  hl, nabu_bare_stub_start
    ld  de, NABU_BARE_STUB_DESTINATION
    ld  bc, nabu_bare_stub_end-nabu_bare_stub_start
    ldir
    jp  NABU_BARE_STUB_DESTINATION+nabu_bare_stub_reset-nabu_bare_stub_start
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

