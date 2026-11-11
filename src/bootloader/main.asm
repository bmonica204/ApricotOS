org 0x7E00
bits 16

%define ENDL 0x0D, 0x0A

kernel_load_segment equ 0x2000

; BPB (BIOS parameter block)
bpb equ 0x7C00
bpb_spc equ bpb + 13
bpb_reserved equ bpb + 14
bpb_fat_count equ bpb + 16
bpb_fat_size32 equ bpb + 36
bpb_root_cluster equ bpb + 44
dir_buffer equ 0x9000
fat_buffer equ 0x9200

start_stage2:
    cld
    mov [drive], dl
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov si, msg_loading
    call puts

    cmp byte [bpb_spc], 1
    jne bad_spc_error

    movzx eax, byte [bpb_fat_count]
    mul dword [bpb_fat_size32]
    movzx ecx, word [bpb_reserved]
    add eax, ecx
    mov [data_lba], eax

    mov eax, [bpb_root_cluster]
    mov [cur_cluster], eax
.next_dir_cluster:
    mov eax, [cur_cluster]
    mov bx, dir_buffer
    call read_cluster
    mov di, dir_buffer
.search_entry:
    mov al, [di]
    test al, al
    jz kernel_not_found_error
    cmp al, 0xE5
    je .skip

    test byte [di + 11], 0x08
    jnz .skip
.compare_name:
    mov si, file_kernel_bin
    mov cx, 11
    push di
    repe cmpsb
    pop di
    je .found_kernel
.skip:
    add di, 32
    cmp di, dir_buffer + 512
    jb .search_entry

    mov eax, [cur_cluster]
    call next_cluster
    cmp eax, 0x0FFFFFF8
    jae kernel_not_found_error
    mov [cur_cluster], eax
    jmp .next_dir_cluster
.found_kernel:
    mov ax, [di + 20]
    shl eax, 16
    mov ax, [di + 26]
    mov [cur_cluster], eax
    mov bx, kernel_load_segment
    mov es, bx
    xor bx, bx
.load_kernel_loop:
    mov eax, [cur_cluster]
    call read_cluster
    add bx, 512
    jnz .no_wrap
    mov ax, es
    add ax, 0x1000
    mov es, ax
.no_wrap:
    mov eax, [cur_cluster]
    call next_cluster
    cmp eax, 0x0FFFFFF8
    jae .read_finish
    mov [cur_cluster], eax
    jmp .load_kernel_loop
.read_finish:
    cli
    lgdt [gdt_descriptor]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword 0x08:init_pm

bad_spc_error:
    mov si, msg_bad_spc
    call puts
    jmp halt
kernel_not_found_error:
    mov si, msg_kernel_not_found
    call puts
    jmp halt

disk_error:
    mov si, msg_read_failed
    call puts
halt:
    cli
    hlt
    jmp halt

puts:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 0x10
    jmp puts
.done:
    ret

disk_read:
    pushad
    mov [dap_lba], eax
    mov [dap_count], cx
    mov [dap_off], bx
    mov [dap_seg], es
    mov si, dap
    mov dl, [drive]
    mov ah, 0x42
    int 13h
    jc disk_error
    popad
    ret

read_cluster:
    push eax
    push cx
    sub eax, 2
    add eax, [data_lba]
    mov cx, 1
    call disk_read
    pop cx
    pop eax
    ret

next_cluster:
    push es
    push bx
    push ecx
    push edx
    mov edx, eax
    shr eax, 7
    movzx ecx, word [bpb_reserved]
    add eax, ecx
    xor bx, bx
    mov es, bx
    mov bx, fat_buffer
    mov cx, 1
    call disk_read
    and edx, 127
    shl edx, 2
    mov bx, dx
    mov eax, [bx + fat_buffer]
    and eax, 0x0FFFFFFF
    pop edx
    pop ecx
    pop bx
    pop es
    ret

bits 32

init_pm:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000

    call setup_paging
    call enable_long_mode
    lgdt [gdt_64_pointer]
    jmp gdt_64.code:0x20000

setup_paging:
    mov edi, 0x10000
    mov cr3, edi
    xor eax, eax
    mov ecx, 4096
    rep stosd
    mov edi, cr3

    mov dword [edi], 0x11000 | 3
    mov dword [edi + 0x1000], 0x12000 | 3
    mov dword [edi + 0x2000], 0x13000 | 3

    mov edi, 0x13000
    mov eax, 3
    mov ecx, 512
.map_table:
    mov [edi], eax
    add eax, 4096
    add edi, 8
    loop .map_table
    ret

enable_long_mode:
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    mov ecx, 0xC0000080
    rdmsr
    or eax, 1 << 8
    wrmsr

    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax
    ret

bits 16
align 8

gdt_start:
    dq 0
gdt_code:
    dw 0xFFFF, 0x0000
    db 0x00, 10011010b, 11001111b, 0x00
gdt_data:
    dw 0xFFFF, 0x0000
    db 0x00, 10010010b, 11001111b, 0x00
gdt_end:
gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start
gdt_64:
    dq 0
.code: equ $ - gdt_64
    dq (1 << 43) | (1 << 44) | (1 << 47) | (1 << 53)
.data: equ $ - gdt_64
    dq (1 << 41) | (1 << 44) | (1 << 47)
gdt_64_pointer:
    dw $ - gdt_64 - 1
    dd gdt_64

align 4
dap:
    db 0x10, 0
dap_count: dw 0
dap_off:   dw 0
dap_seg:   dw 0
dap_lba:   dq 0

drive:              db 0
align 4
data_lba:           dd 0
cur_cluster:        dd 0

msg_loading: db 'Loading kernel...', ENDL, 0
msg_read_failed: db 'Disk read failed!', ENDL, 0
msg_kernel_not_found: db 'Kernel not found!', ENDL, 0
msg_bad_spc: db 'Need 1 sector/cluster!', ENDL, 0   
file_kernel_bin: db 'KERNEL  BIN'

%if ($-$$)> 0x1000
%error "Stage 2 too big: only 8 sectors are loaded"
%endif