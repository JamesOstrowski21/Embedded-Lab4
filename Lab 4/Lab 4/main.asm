;
; Lab 4.asm
;
; Created: 3/28/2023 12:05:42 PM
; Authors : James Ostrowski and Kai Lindholm 
;

.include "m328Pdef.inc"
.cseg
.org 0x00 ; PC points here after reset

.def temp = r18
msg1: .db "DC = ", 0x00
msg2: .db "Fan = ", 0x00
msg3: .db " % ", 0x00

rjmp start

; Replace with your application code
start:
	ldi		temp, (1<<CS01) | (1<<CS00)
	out		TCCR0B, temp	; Timer clock = system clock / 64
	ldi		temp, 1 << TOV0
	out		TIFR0, temp		; CLear TOV0 / clear pending interrupts 
	ldi		temp, 1 << TOIE0
	sts		TIMSK0, temp	
    rcall LCDinit
	sbi PORTB, PB5
	ldi r24, 5
	ldi r30,LOW(2*msg1) ; Load Z register low
    ldi r31,HIGH(2*msg1) ; Load Z register high
    rcall displayCString
	ldi r24, 3
	ldi r30,LOW(2*msg3) ; Load Z register low
    ldi r31,HIGH(2*msg3) ; Load Z register high
    rcall displayCString
	rcall Secondline
	ldi r24, 6
	ldi r30,LOW(2*msg2) ; Load Z register low
    ldi r31,HIGH(2*msg2) ; Load Z register high
	rcall displayCString
	
main:
	rjmp main
Secondline:
	cbi PORTB, PB5
	ldi r17, 0x0C
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	sbi PORTB, PB5
	ret

displayCString:
L20:
	lpm ; r0 <-- first byte
	swap r0 ; Upper nibble in place
	out PORTC,r0 ; Send upper nibble out
	rcall LCDStrobe ; Latch nibble
	rcall delay_ms ; Wait
	swap r0 ; Lower nibble in place
	out PORTC,r0 ; Send lower nibble out
	rcall LCDStrobe ; Latch nibble
	rcall delay_ms ; Wait
	adiw zh:zl,1 ; Increment Z pointer
	dec r24 ; Repeat until
	brne L20 ; all characters are out
	ret


LCDStrobe:
	sbi PORTB, PB3
	rcall delay_ms
	rcall delay_ms
	cbi PORTB, PB3
	ret

LCDinit:
	ldi r16, 0xFF ;all 1s in B
	out DDRB, r16

	ldi r16, 0xFF ;all 1s in C
	out DDRC, r16

	ldi r16, 0x65 ;100 ms
	rcall delay_mms

	ldi r17, 0x03 ;8 bit mode 
	out PORTC, r17
	rcall LCDStrobe
	ldi r16, 5 ; 
	rcall delay_mms;8 bit mode, DB3 and DB2 high
	out PORTC, r17
	rcall LCDStrobe;pulse enable to change mode
	ldi r16, 1 ; >200us
	rcall delay_mms;8 bit mode, DB3 and DB2 high
	out PORTC, r17
	rcall LCDStrobe;pulse enable to change mode
	ldi r16, 6 ; >200us
	rcall delay_mms
	

	ldi r17, 0x02 ; 4 bit mode
	out PORTC, r17
	nop
	rcall LCDStrobe
	ldi r16, 6
	rcall delay_mms

	ldi r17, 0x02
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x08
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms

	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x08
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms

	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms
	ldi r17, 0x01
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	rcall delay_ms

	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	ldi r17, 0x06
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms

	ldi r17, 0x00
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	ldi r17, 0x0C
	out PORTC, r17
	nop
	rcall LCDStrobe
	rcall delay_ms
	ret
delay_mms:
	loop:
		rcall delay_ms
		dec r16
		brne loop
	ret


delay_ms:
		push	temp				
		ldi		temp, 6
		out		TCNT0, temp
		clr		temp
		wait2: 
			in		temp, TCNT0
			cpi		temp, 0x00		; has the overflow bit been set
			brne	wait2			; if not wait. 

		pop		temp
	    ret
	
