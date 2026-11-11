.text
.globl chain_run,chain_begin,chain_end
.def chain_run; .scl 2; .type 32; .endef
chain_run:
    xorl %eax,%eax
chain_begin:
    .rept 130
    .byte 0x06
    .endr
chain_end:
    ret
.globl boundary_run,boundary_first,boundary_second
.def boundary_run; .scl 2; .type 32; .endef
boundary_run:
    xorl %eax,%eax
boundary_first:
    .byte 0x06
    addq $3,%rax
boundary_second:
    .byte 0x06
    ret
.globl ud2_run,ud2_first,ud2_second
.def ud2_run; .scl 2; .type 32; .endef
ud2_run:
    xorl %eax,%eax
ud2_first:
    ud2
ud2_second:
    ud2
    ret

.text
.globl load_bridge_run
.globl load_bridge_first
.globl load_bridge_second
load_bridge_run:
 movq %rdx, %rax
load_bridge_first:
 .byte 0x06
load_bridge_second:
 .byte 0xea
 ret

.text
.globl register_native_run
register_native_run:
 pushq %rbx
 subq $32, %rsp
 movdqu %xmm8, (%rsp)
 movq %rcx, %rbx
 movq 0(%rbx), %rax
 movq 8(%rbx), %rdx
 movq 16(%rbx), %r10
 movq 24(%rbx), %r11
 movdqu 32(%rbx), %xmm0
 movdqu 48(%rbx), %xmm1
 movdqu 64(%rbx), %xmm8
 movq 88(%rbx), %rcx
 pushq 80(%rbx)
 popfq
 call *register_native_code(%rip)
 movq %rax, 0(%rbx)
 movq %rdx, 8(%rbx)
 movq %r10, 16(%rbx)
 movq %r11, 24(%rbx)
 movq %rcx, 88(%rbx)
 movdqu %xmm0, 32(%rbx)
 movdqu %xmm1, 48(%rbx)
 movdqu %xmm8, 64(%rbx)
 pushfq
 popq %r8
 movq %r8, 80(%rbx)
 movdqu (%rsp), %xmm8
 addq $32, %rsp
 popq %rbx
 ret

.text
.globl register_trap_run
register_trap_run:
 pushq %rbx
 subq $32, %rsp
 movdqu %xmm8, (%rsp)
 movq %rcx, %rbx
 movq 0(%rbx), %rax
 movq 8(%rbx), %rdx
 movq 16(%rbx), %r10
 movq 24(%rbx), %r11
 movdqu 32(%rbx), %xmm0
 movdqu 48(%rbx), %xmm1
 movdqu 64(%rbx), %xmm8
 movq 88(%rbx), %rcx
 pushq 80(%rbx)
 popfq
.globl register_trap_first
.globl register_trap_second
register_trap_first:
 .byte 0x06
register_trap_second:
 .byte 0xea
 movq %rax, 0(%rbx)
 movq %rdx, 8(%rbx)
 movq %r10, 16(%rbx)
 movq %r11, 24(%rbx)
 movq %rcx, 88(%rbx)
 movdqu %xmm0, 32(%rbx)
 movdqu %xmm1, 48(%rbx)
 movdqu %xmm8, 64(%rbx)
 pushfq
 popq %r8
 movq %r8, 80(%rbx)
 movdqu (%rsp), %xmm8
 addq $32, %rsp
 popq %rbx
 ret

.text
.globl resume_fault_run,resume_fault_first,resume_fault_target,resume_fault_end
resume_fault_run:
 movq %rdx,%rax
resume_fault_first:
 .byte 0x06
resume_fault_target:
 movb (%r8),%dl
resume_fault_end:
 ret

.text
.globl resume_ud2_run,resume_ud2_first,resume_ud2_target,resume_ud2_end
resume_ud2_run:
 movq %rdx,%rax
resume_ud2_first:
 .byte 0x06
resume_ud2_target:
 ud2
resume_ud2_end:
 ret

.text
.globl classification_run,classification_first,classification_end
classification_run:
 movq %rcx,%rax
 pushq %rdx
 popfq
classification_first:
 .byte 0x06
classification_end:
 ret
.globl classification_aam,classification_aad,classification_callfar
.globl classification_ud2,classification_nop
classification_aam:
 .byte 0xd4,0x0a
 ret
classification_aad:
 .byte 0xd5,0x0a
 ret
classification_callfar:
 .byte 0x9a,0,0,0,0,0,0
 ret
classification_ud2:
 ud2
 ret
classification_nop:
 nop
 ret

.balign 16384
.fill 16383,1,0x90
.globl classification_boundary_aam
classification_boundary_aam:
.byte 0xd4
.space 4096,0x90

.balign 16384
.fill 16383,1,0x90
.globl classification_boundary_aad
classification_boundary_aad:
.byte 0xd5
.space 4096,0x90

.balign 16384
.fill 16383,1,0x90
.globl classification_boundary_callfar
classification_boundary_callfar:
.byte 0x9a
.space 4096,0x90

.balign 16384
.fill 16382,1,0x90
.globl classification_fit_aam
classification_fit_aam:
.byte 0xd4,0xa
.space 4096,0x90

.balign 16384
.fill 16382,1,0x90
.globl classification_fit_aad
classification_fit_aad:
.byte 0xd5,0xa
.space 4096,0x90

.balign 16384
.fill 16377,1,0x90
.globl classification_fit_callfar
classification_fit_callfar:
.byte 0x9a,0x0,0x0,0x0,0x0,0x0,0x0
.space 4096,0x90

.balign 16384
.fill 16368,1,0x90
.globl classification_window_aam
classification_window_aam:
.byte 0xd4,0xa
.fill 14,1,0x90
.space 4096,0x90

.balign 16384
.fill 16368,1,0x90
.globl classification_window_aad
classification_window_aad:
.byte 0xd5,0xa
.fill 14,1,0x90
.space 4096,0x90

.balign 16384
.fill 16368,1,0x90
.globl classification_window_callfar
classification_window_callfar:
.byte 0x9a,0x0,0x0,0x0,0x0,0x0,0x0
.fill 9,1,0x90
.space 4096,0x90
