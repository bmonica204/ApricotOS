org 0x20000
bits 64


%define ENDL 0x0D, 0x0A

start:
	; print message
	mov rdi, 0xB8000
	mov rcx, 2000

.clear_loop:
	mov word [rdi], 0x0720
	add rdi, 2
	dec rcx
	jnz .clear_loop

	mov rsi, msg_hello
	mov rdi, 0xB8000

.loop:
	lodsb
	or al, al
	jz .halt

	mov [rdi], al
	mov byte [rdi + 1], 0x0F
	add rdi, 2
	jmp .loop

.halt:	
	cli
	hlt
	jmp .halt

msg_hello:				db 'Hello I am the 64bit Kernel!!!', 0