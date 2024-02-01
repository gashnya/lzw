section .text
global lzw_decode

%define CLEAR_CODE      256
%define EOI_CODE        257
%define TABLE_START     258
%define TABLE_SIZE      4096
%define STACK_SIZE      24864
%define START_CODE_SIZE 9

%macro get_next_code 1
    xor eax, eax

    mov ebx, [in_size]
    mov cl, [offset]
    mov ch, [code_size]

    movzx ax, ch
    movzx dx, cl
    add ax, dx

    mov dx, ax
    add ax, 7
    shr ax, 3
    add eax, esi

    cmp eax, ebx
    ja .end_with_err

.gnc_no_overflow_%+%1:
    mov eax, ebx
    sub eax, esi
    cmp eax, 4
    jae .gnc_case_4_%+%1

    jmp [gnc_switch_%+%1 + eax * 4]

.gnc_case_1_%+%1:
    mov al, [esi]
    add cl, 24
    shl al, cl
    mov cl, 32
    sub cl, ch
    shr al, cl
    jmp .gnc_end_%+%1

.gnc_case_2_%+%1:
    movbe ax, [esi]
    add cl, 16
    shl eax, cl
    mov cl, 32
    sub cl, ch
    shr eax, cl
    jmp .gnc_end_%+%1

.gnc_case_3_%+%1:
    mov al, [esi]
    shl eax, 16
    movbe ax, [esi + 1]
    add cl, 8
    shl eax, cl
    mov cl, 32
    sub cl, ch
    shr eax, cl
    jmp .gnc_end_%+%1

.gnc_case_4_%+%1:
    movbe eax, [esi]
    shl eax, cl
    mov cl, 32
    sub cl, ch
    shr eax, cl

.gnc_end_%+%1:
    movzx ebx, dx
    and bx, 7
    mov [offset], bl

    movzx ebx, dx
    shr bx, 4
    add bx, 1
    add esi, ebx

    inc DWORD [code_cnt]
    mov ebx, [code_cnt]
    add ebx, 2
    mov cl, ch
    shr ebx, cl
    cmp ebx, 1
    sete ch
    add [code_size], ch

    mov [code], ax
%endmacro
;-------------------------------------
%macro write_to_out 1
    mov ebp, [table_ptr + ecx * 4]

    xor ebx, ebx

    mov dx, ax
    cmp dx, 4
    jb .out_write_4b_%+%1

.loop_write_4b_%+%1:
    mov eax, ebp
    add eax, ebx
    mov eax, [eax]
    mov [edi], eax
    add ebx, 4
    add edi, 4
    sub dx, 4
    cmp dx, 4
    jae .loop_write_4b_%+%1
.out_write_4b_%+%1:
    cmp dx, 2
    jb .out_write_2b_%+%1

.loop_write_2b_%+%1:
    mov eax, ebp
    add eax, ebx
    mov ax, [eax]
    mov [edi], ax
    add ebx, 2
    add edi, 2
    sub dx, 2
    cmp dx, 2
    jae .loop_write_2b_%+%1
.out_write_2b_%+%1:
    cmp dx, 0
    je .out_write_%+%1

.loop_write_1b_%+%1:
    mov eax, ebp
    add eax, ebx
    mov al, [eax]
    mov [edi], al
    inc ebx
    inc edi
    sub dx, 1
    jnz .loop_write_1b_%+%1
%endmacro

;-------------------------------------

lzw_decode:
    %define in_ptr      esp + STACK_SIZE + 16 + 4
    %define in_size     esp + STACK_SIZE + 16 + 8
    %define out_ptr     esp + STACK_SIZE + 16 + 12
    %define out_size    esp + STACK_SIZE + 16 + 16

    %define table_char      esp + 24608 ; +   256 bytes
    %define table_ptr       esp + 8224  ; + 16384 bytes (4096 * 4)
    %define table_len       esp + 32    ; +  8192 bytes (4096 * 2)
    %define code_cnt        esp + 28 ; DWORD
    %define out_ptr_bp      esp + 24 ; DWORD
    %define out_ptr_bp_gl   esp + 20 ; DWORD
    %define code_cnt_bp     esp + 16 ; DWORD
    %define code            esp + 14 ; WORD
    %define old_code        esp + 12 ; WORD
    %define offset          esp + 11 ; BYTE
    %define code_size       esp + 10 ; BYTE

    push ebx
    push esi
    push edi
    push ebp

    sub esp, STACK_SIZE

    %assign i 0
    %rep 8
        mov al, [esp + STACK_SIZE - 4096 * i]
    %assign i i + 1
    %endrep

    mov esi, [in_ptr]
    test esi, esi
    jz .end_with_err

    mov edi, [out_ptr]
    test edi, edi
    jz .end_with_err

    mov edx, 255 ; 255 * 8 + 4
.prepare_loop:
    mov WORD [table_len + edx * 2], 1
    mov BYTE [table_char + edx], dl
    lea ebx, [table_char + edx]
    mov DWORD [table_ptr + edx * 4], ebx
    dec edx
    jns .prepare_loop

    mov BYTE [code_size], START_CODE_SIZE
    mov BYTE [offset], 0
    mov DWORD [code_cnt], CLEAR_CODE

    mov [out_ptr_bp_gl], edi

    add [in_size], esi
    add [out_size], edi

.lzw_loop:
    get_next_code 1

    cmp ax, EOI_CODE
    je .end

    cmp eax, CLEAR_CODE
    jne .not_clear
;-------------------------------------
    mov BYTE [code_size], START_CODE_SIZE
    mov DWORD [code_cnt], CLEAR_CODE

    get_next_code 2

    cmp eax, EOI_CODE
    je .end

    cmp eax, TABLE_START
    jae .end_with_err

    mov [old_code], ax

    mov ecx, [out_size]
    sub ecx, edi
    cmp ecx, 1
    jb .end_with_err

    mov [table_ptr + eax * 4], edi
    mov [edi], al
    inc edi
    jmp .lzw_loop
.not_clear:
    mov ecx, [code_cnt]

    cmp eax, TABLE_SIZE
    jae .end_with_err

    cmp eax, ecx
    jae .not_in_table

    mov ecx, eax

    mov edx, [out_size]
    sub edx, edi
    movzx eax, WORD [table_len + ecx * 2]

    cmp eax, edx
    ja .end_with_err

    mov [out_ptr_bp], edi

    write_to_out 1

.out_write_1:
    mov ebx, [code_cnt]

    movzx eax, WORD [old_code]

    mov dx, [table_len + eax * 2]
    mov ebp, [table_ptr + eax * 4]

    inc dx

    mov WORD [table_len + ebx * 2], dx
    mov [table_ptr + ebx * 4], ebp

    mov ebp, [out_ptr_bp]
    mov [table_ptr + ecx * 4], ebp

    mov ax, [code]
    mov [old_code], ax
    jmp .lzw_loop
;-------------------------------------
.not_in_table:
    movzx ebx, WORD [old_code]
    mov ecx, [code_cnt]
    cmp ebx, ecx
    jae .end_with_err

    mov ecx, ebx

    mov edx, [out_size]
    sub edx, edi
    movzx eax, WORD [table_len + ecx * 2]
    inc eax

    cmp eax, edx
    ja .end_with_err

    mov [out_ptr_bp], edi

    dec eax

    write_to_out 2

.out_write_2:
    mov eax, [table_ptr + ecx * 4]
    mov al, [eax]
    mov [edi], al
    inc edi

    mov ebx, [code_cnt]

    mov dx, [table_len + ecx * 2]
    mov ebp, [out_ptr_bp]
    mov [table_ptr + ecx * 4], ebp

    inc dx

    mov WORD [table_len + ebx * 2], dx
    mov [table_ptr + ebx * 4], ebp

    mov ax, [code]
    mov [old_code], ax
    jmp .lzw_loop

;-------------------------------------
.end_with_err:
    mov eax, -1
    jmp .end_clear

.end:
    sub edi, [out_ptr_bp_gl]
    mov eax, edi

.end_clear:
    add esp, STACK_SIZE
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret

section .rodata
gnc_switch_1: dd lzw_decode.gnc_case_1_1, lzw_decode.gnc_case_1_1, lzw_decode.gnc_case_2_1, lzw_decode.gnc_case_3_1
gnc_switch_2: dd lzw_decode.gnc_case_1_2, lzw_decode.gnc_case_1_2, lzw_decode.gnc_case_2_2, lzw_decode.gnc_case_3_2
