    org     0x1000
    bits    32

    jmp         editor

%include "utils.inc"

MAX_NUM_TABS    equ 10
BUFFER_SIZE     equ 2000 ; in bytes
TOTAL_BUFFERS   equ MAX_NUM_TABS*BUFFER_SIZE

; colors
TEXT_COLOR      equ WHITE_ON_BLACK
HINT_COLOR      equ GREY_ON_BLACK

; strings
welcome:        db  "This is a new tab, you can start typing right away!",0


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  A Simple text editor that runs on x86 hardware  ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

editor:
    mov         ebp, esp

    ; setup a buffer for each tab
    sub         esp, TOTAL_BUFFERS  ; buffers
    sub         esp, MAX_NUM_TABS*4 ; gap start
    sub         esp, MAX_NUM_TABS*4 ; gap end
    sub         esp, MAX_NUM_TABS*4 ; selection start
    sub         esp, MAX_NUM_TABS*4 ; selection end
    sub         esp, MAX_NUM_TABS   ; tab state
    sub         esp, 4              ; current tab index
    and         esp, 0xfffffff0     ; ensure the stack is aligned to 16-byte boundries

    ; stack variables offsets
buffers         equ TOTAL_BUFFERS
gap_start       equ buffers + MAX_NUM_TABS*4
gap_end         equ gap_start + MAX_NUM_TABS*4
select_start    equ gap_end + MAX_NUM_TABS*4
select_end      equ select_start + MAX_NUM_TABS*4
tab_state       equ select_end + MAX_NUM_TABS
current_tab     equ tab_state + 4


    ;;;;;;;;;;;;;;;;;;;;;;
    ;  Initialize State  ;
    ;;;;;;;;;;;;;;;;;;;;;;

    mov         edi, VIDMEM     ; VGA color text mode memory address

    ; Program State
    ; caps lock is on
CAPS_STATE      equ 0b0001
    ; shift is pressed
SHIFT_STATE     equ 0b0010
    ; ctrl is pressed
CTRL_STATE      equ 0b0100
    ; both shift and ctrl are pressed
SHIFT_CTRL_STATE equ 0b1000

    ; Tab State
    ; old tab
OLD_TAB         equ 0
    ; new tab
FRESH_TAB_STATE equ 1

    ; initial state
    ; no key is pressed, and the tab is new
    ; dx = 0x0100
    xor         edx, edx
    mov         dh, FRESH_TAB_STATE

    ; Initialize variables
    ; gap start array
    cld
    lea         edi, [ebp-gap_start]
    xor         eax, eax
    mov         ecx, MAX_NUM_TABS
    rep         stosd
    ; gap end array
    cld
    lea         edi, [ebp-gap_end]
    mov         ax, BUFFER_SIZE
    mov         ecx, MAX_NUM_TABS
    rep         stosd
    ; select start array
    cld
    lea         edi, [ebp-select_start]
    mov         ax, BUFFER_SIZE
    mov         ecx, MAX_NUM_TABS
    rep         stosd
    ; select end array
    cld
    lea         edi, [ebp-select_end]
    mov         ax, BUFFER_SIZE
    mov         ecx, MAX_NUM_TABS
    rep         stosd
    ; tab state array
    cld
    lea         edi, [ebp-tab_state]
    mov         al, 0x01
    mov         ecx, MAX_NUM_TABS
    rep         stosb
    ; current tab
    mov         dword [ebp-current_tab], 0

; Wait for keyboard input
.check:
    cmp         dh, FRESH_TAB_STATE
    jne         .wait_for_key
    ; print welcome message
    pusha
    mov         esi, welcome
    mov         ah, HINT_COLOR
    mov         bh, 10
    mov         bl, 15
    call        puts
    popa

.wait_for_key:
    in          al, 0x64
    test        al, 1   ; is data available at the data port?
    jz          .check
.interpretKey:
    ; Get the scan code of the key
    xor         eax, eax
    in          al, 0x60
; check if its a make code or a break code
    test        al, 0x80
    jnz         .break_code
; Make Codes
;; Left Shift
    cmp         al, 0x2A
    jne         .rshift
    or          dl, SHIFT_STATE
    jmp         .makecodes_done
;; Right Shift
.rshift:
    cmp         al, 0x36
    jne         .ctrl
    or          dl, SHIFT_STATE
    jmp         .makecodes_done
;; Ctrl
.ctrl:
    cmp         al, 0x1D
    jne         .caps
    or          dl, CTRL_STATE
    jmp         .makecodes_done
;;CAPS LOCK:
.caps:
    cmp         al, 0x3A
    jne         .bkspace
    test        dl, CAPS_STATE
    jz          .enable_caps
    and         dl, ~CAPS_STATE
    jmp         .makecodes_done
.enable_caps:
    or          dl, CAPS_STATE
    jmp         .makecodes_done

;; Backspace
.bkspace:
    cmp         al, 0x0E
    jne         .del

    ; Delete from buffer
    pusha

    ; buffer params
    lea         edi, [ebp-buffers]
    mov         eax, [ebp-current_tab]
    mov         ecx, BUFFER_SIZE
    mul         ecx
    add         edi, eax

    mov         ecx, BUFFER_SIZE

    ; gap parameters
    mov         eax, [ebp-current_tab]
    mov         ebx, [ebp-gap_start+eax*4]
    mov         edx, [ebp-gap_end+eax*4]

    xor         eax, eax

    call        bufdel

    mov         eax, [ebp-current_tab]
    mov         [ebp-gap_start+eax*4], ebx
    mov         [ebp-gap_end+eax*4], edx
    popa
    jmp         .refreshScreen
.del:
    cmp         al, 0x53
    jne         .arrows

    ; Delete from buffer
    pusha

    ; buffer params
    lea         edi, [ebp-buffers]
    mov         eax, [ebp-current_tab]
    mov         ecx, BUFFER_SIZE
    mul         ecx
    add         edi, eax

    mov         ecx, BUFFER_SIZE

    ; gap parameters
    mov         eax, [ebp-current_tab]
    mov         ebx, [ebp-gap_start+eax*4]
    mov         edx, [ebp-gap_end+eax*4]

    mov         eax, 1

    call        bufdel

    mov         eax, [ebp-current_tab]
    mov         [ebp-gap_start+eax*4], ebx
    mov         [ebp-gap_end+eax*4], edx
    popa
    jmp         .refreshScreen
.arrows:
;; Arrows
;;; Up Arrow
    cmp         al, 0x48
    je          .nav
;;; Left Arrow
    cmp         al, 0x4B
    je          .nav
;;; Right Arrow
    cmp         al, 0x4D
    je          .nav
;; Down Arrow
    cmp         al, 0x50
    jne         .character
.nav:
    pusha
    push        eax ; save arrow scan code

    ; buffer params
    lea         edi, [ebp-buffers]
    mov         eax, [ebp-current_tab]
    mov         ecx, BUFFER_SIZE
    mul         ecx
    add         edi, eax

    ; gap parameters
    mov         eax, [ebp-current_tab]
    mov         ebx, [ebp-gap_start+eax*4]
    mov         edx, [ebp-gap_end+eax*4]

    pop         eax

    call        navigate

    mov         eax, [ebp-current_tab]
    mov         [ebp-gap_start+eax*4], ebx
    mov         [ebp-gap_end+eax*4], edx

    popa

    jmp         .refreshScreen
;; Characters
; Wait for the break code
.character:
    cmp         dh, FRESH_TAB_STATE
    jne         .makecodes_done
    ; clear the screen on the first key press
    pusha
    call        clrscr
    popa
    xor         dh, dh
.makecodes_done:
    jmp          .finish_loop

;;;;;;;;;;;;;;;;;
;  Break Codes  ;
;;;;;;;;;;;;;;;;;

.break_code:
    cmp         al, 0x81 ; ESC
    je          .finish_loop
    cmp         al, 0x8E ; BKSP
    je          .finish_loop
    cmp         al, 0x9D ; CTRL
    je          .reset_ctrl
    cmp         al, 0xAA ; LEFT SHIFT
    je          .reset_shift
    cmp         al, 0xB6 ; RIGHT SHIFT
    je          .reset_shift
    cmp         al, 0xB9 ; SPACE
    jg          .finish_loop
; It is a break code of a character
    test        dl, CTRL_STATE
    jnz         .shortcut
    pusha

    test        dl, CAPS_STATE
    jz          .no_caps
    mov         ch, 1
    jmp         .check_shift
.no_caps:
    xor         ch, ch
.check_shift:
    test        dl, SHIFT_STATE
    jz          .no_shift
    mov         cl, 1
    jmp         .get_ascii
.no_shift:
    xor         cl, cl
.get_ascii:
    call        scanCodeToASCII

    push        eax

    ; buffer params
    lea         edi, [ebp-buffers]
    mov         eax, [ebp-current_tab]
    mov         ecx, BUFFER_SIZE
    mul         ecx
    add         edi, eax

    ; gap parameters
    mov         eax, [ebp-current_tab]
    mov         ebx, [ebp-gap_start+eax*4]
    mov         edx, [ebp-gap_end+eax*4]

    pop         eax

    call        bufins

    mov         eax, [ebp-current_tab]
    mov         [ebp-gap_start+eax*4], ebx
    mov         [ebp-gap_end+eax*4], edx
    popa

    jmp         .refreshScreen

;;;;;;;;;;;;;;;;
;  Shortcuts  ;
;;;;;;;;;;;;;;;;

.shortcut:
    cmp         al, 0x8f
    jne         .shortcut_done
    test        dl, SHIFT_STATE
    jnz         .backward_tab_switch
; forward tab switch
    ; save tab state
    push        eax
    push        esi
    mov         eax, [ebp-current_tab]
    lea         esi, [ebp-tab_state]
    mov         [esi+eax], dh
    pop         esi
    pop         eax

    ; switch tab
    pusha
    mov         eax, [ebp-current_tab]
    xor         edx, edx
    call        change_tab
    mov         [ebp-current_tab], eax
    popa

    ; restore tab state
    push        eax
    push        esi
    mov         eax, [ebp-current_tab]
    lea         esi, [ebp-tab_state]
    mov         dh, [esi+eax]
    pop         esi
    pop         eax
    jmp         .shortcut_done
.backward_tab_switch:
    ; save tab state
    push        eax
    push        esi
    mov         eax, [ebp-current_tab]
    lea         esi, [ebp-tab_state]
    mov         [esi+eax], dh
    pop         esi
    pop         eax

    ; switch tab
    pusha
    mov         eax, [ebp-current_tab]
    mov         edx, 1
    call        change_tab
    mov         [ebp-current_tab], eax
    popa

    ; restore tab state
    push        eax
    push        esi
    mov         eax, [ebp-current_tab]
    lea         esi, [ebp-tab_state]
    mov         dh, [esi+eax]
    pop         esi
    pop         eax
    jmp         .shortcut_done

.shortcut_done:
    jmp         .refreshScreen

.reset_shift:
    and         dl, ~SHIFT_STATE
    jmp         .finish_loop
.reset_ctrl:
    and         dl, ~CTRL_STATE
    jmp         .finish_loop
.refreshScreen:
    pusha

    call        clrscr

    ; buffer params
    lea         esi, [ebp-buffers]
    mov         eax, [ebp-current_tab]
    mov         ecx, BUFFER_SIZE
    mul         ecx
    add         esi, eax

    mov         ecx, BUFFER_SIZE

    ; gap parameters
    mov         eax, [ebp-current_tab]
    mov         ebx, [ebp-gap_start+eax*4]
    mov         edx, [ebp-gap_end+eax*4]

    ; select paramters
    mov         edi, [ebp-select_start+eax*4]
    mov         eax, [ebp-select_end+eax*4]

    call        bufprint

    popa
.finish_loop:
    jmp         .check

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;  Handle navigation with in a tab  ;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

navigate:
;Parameters
;  al = scan code of an arrow
;  edi = current tab buffer
;  ebx = gap start offset
;  edx = gap end offset
;Output
;  ebx = final gap start offset
;  edx = final gap end offset
    enter       0, 16
    ; offsets
.current:       equ 4
.target:        equ .current + 4
.exists:        equ .target + 1


    and         al, 0x7f    ; make sure it is a make code

    cmp         al, 0x4b    ; LEFT
    jne         .right
    ; if the cursor is on the beginning of the buffer
    ; do nothing
    or          ebx, ebx
    je          .done
    ; otherwise, shift the gap to the left
    dec         ebx
    dec         edx
    mov         al, [edi+ebx]
    mov         [edi+edx], al
    jmp         .done

.right:
    cmp         al, 0x4d    ; RIGHT
    jne         .up

    ; if the cursor is on the end of the buffer
    ; or if there are no characters after the cursor
    ; do nothing
    cmp         edx, BUFFER_SIZE
    je          .done
    ; otherwise, shift the gap to the right
    mov         al, [edi+edx]
    mov         [edi+ebx], al
    inc         ebx
    inc         edx
    jmp         .done
.up:
    cmp         al, 0x48    ; UP
    jne         .down

    pusha
    call        previousline
    dec         ecx
    mov         [ebp-.target], ecx
    mov         [ebp-.exists], al
    popa

    cmp         byte [ebp-.exists], 0
    jz          .done

    pusha
    call        lineoffset
    dec         ecx
    mov         [ebp-.current], ecx
    popa

    pusha
    mov         eax, [ebp-.target]
    mov         ecx, BUFFER_SIZE
    call        linelen

    cmp         ecx, [ebp-.current]
    jl          .up_cutoff
    mov         eax, [ebp-.current]
    add         [ebp-.target], eax
    jmp         .move_up
.up_cutoff:
    add         [ebp-.target], ecx
.move_up:
    popa


    mov         eax, [ebp-.target]
    call        movegap
    jmp         .done

.down:
    cmp         al, 0x50    ; DOWN
    jne         .done

    pusha
    mov         ecx, BUFFER_SIZE
    call        nextline
    mov         [ebp-.target], ecx
    mov         [ebp-.exists], al
    popa

    cmp         byte [ebp-.exists], 0
    jz          .done

    pusha
    call        lineoffset
    mov         [ebp-.current], ecx
    popa

    pusha
    mov         eax, [ebp-.target]
    inc         eax
    mov         ecx, BUFFER_SIZE
    call        linelen

    cmp         ecx, [ebp-.current]
    jl          .down_cutoff
    mov         eax, [ebp-.current]
    add         [ebp-.target], eax
    jmp         .move_down
.down_cutoff:
    add         [ebp-.target], ecx
.move_down:
    popa

    mov         eax, [ebp-.target]
    call        movegap
.done:
    leave
    ret

change_tab:
;Parameters
;  eax = current tab
;  dl = 0 to go to the next tab, 1 for the previous one
;Output
;  eax = final tab
    or          edx, edx
    jnz         .backward
    cmp         eax, MAX_NUM_TABS-1
    je          .goto_first
    inc         eax
    jmp         .done
.goto_first:
    xor         eax, eax
    jmp         .done
.backward:
    or          eax, eax
    jz          .goto_last
    dec         eax
    jmp         .done
.goto_last:
    mov         eax, MAX_NUM_TABS-1
.done:
    ret

    times   (0x400000 - ($ - $$ - 0x200)) db 0
    ; vim: set ft=nasm:
    ; vim: set commentstring=;%s:
