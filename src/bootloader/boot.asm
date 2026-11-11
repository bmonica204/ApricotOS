org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A
%define STAGE2_LOAD_SEG 0x0000
%define STAGE2_LOAD_OFF 0x7E00
%define STAGE2_LBA 8
%define STAGE2_SECTORS 8

jmp short start
nop

bdb_oem:						db 'MSWIN4.1'
bdb_bytes_per_sector:			dw 512
bdb_sectors_per_cluster:		db 1
bdb_reserved_sectors:			dw 32
bdb_fat_count:					db 2
bdb_dir_entries_count:			dw 0
bdb_total_sectors:				dw 0
bdb_media_descriptor_type:		db 0F8h
bdb_sectors_per_fat:			dw 0
bdb_sectors_per_track:			dw 63
bdb_heads:						dw 255
bdb_hidden_sectors:				dd 0
bdb_large_sector_count:			dd 81920
bdb_sectors_per_fat32:          dd 0
bdb_flags:                      dw 0
bdb_fat_version:                dw 0
bdb_root_cluster:               dd 2
bdb_fsinfo_sector:              dw 1
bdb_backup_boot:                dw 6
bdb_reserved:                   times 12 db 0

ebr_drive_number:				db 0x80
                            	db 0
ebr_signature:					db 29h
ebr_volume_id:					db 12h, 34h, 56h, 78h
ebr_volume_label:				db 'APRICOT OS'
ebr_system_id:					db 'FAT32  '

times 90-($-$$) db 0
%if ($-$$) != 90
%error "FAT32 BPB needs to be 90 bytes"
%endif

start:
    cli
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [ebr_drive_number], dl

    mov si, msg_loading_32bit
    call print_string

    mov ah, 0x42
    mov dl, [ebr_drive_number]
    mov si, dap
    int 13h
    jc disk_error

    mov dl, [ebr_drive_number]
    jmp STAGE2_LOAD_SEG:STAGE2_LOAD_OFF

disk_error:
    mov si, msg_error_32bit
    call print_string
    cli
.halt:
    hlt
    jmp .halt

print_string:
    lodsb
    or al, al
    jz .done
    mov ah, 0x0E
    int 10h
    jmp print_string
.done:
    ret

msg_loading_32bit:					db 'Switching to 32bit Protected Mode...', ENDL, 0
msg_error_32bit:					db "Disk read error!", ENDL, 0

align 4
dap:
	db 0x10
    db 0
    dw STAGE2_SECTORS
    dw STAGE2_LOAD_OFF
    dw STAGE2_LOAD_SEG
    dq STAGE2_LBA

times 510-($-$$) db 0
dw 0AA55h